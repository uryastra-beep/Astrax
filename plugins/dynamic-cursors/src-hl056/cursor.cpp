#include <any>    // IWYU pragma: keep
#include <chrono> // IWYU pragma: keep
#include <ranges> // IWYU pragma: keep
#define private public
#include <hyprland/src/pointer/cursor/CursorManager.hpp>
#include <hyprland/src/pointer/PointerManager.hpp>
#include <hyprland/src/render/OpenGL.hpp>
#include <hyprland/src/render/Renderer.hpp>
#include <hyprland/src/Compositor.hpp>
#undef private

#include <hyprcursor/hyprcursor.hpp>
#include <hyprland/src/config/ConfigValue.hpp>
#include <hyprland/src/protocols/core/Compositor.hpp>
#include <hyprland/src/state/MonitorState.hpp>
#include <hyprland/src/protocols/core/Seat.hpp>
#include <hyprland/src/debug/log/Logger.hpp>
#include <hyprland/src/helpers/math/Math.hpp>
#include <hyprlang.hpp>
#include <hyprutils/utils/ScopeGuard.hpp>
#include <cmath>
#include <unordered_map>
#include <cstdlib>
#include <climits>
#include <gbm.h>
#include <numbers>

#include "cursor.hpp"
#include "render/renderer.hpp"
#include "config/ConfigManager.hpp"
#include "mode/Mode.hpp"
#include "halo.hpp"
#include "render/CursorPassElement.hpp"

void tickRaw(SP<CEventLoopTimer> self, void* data) {
    if (g_pConfigHandler->isEnabled())
        g_pDynamicCursors->onTick(Pointer::mgr().get());

    const int TIMEOUT = g_pHyprRenderer->m_mostHzMonitor && g_pHyprRenderer->m_mostHzMonitor->m_refreshRate > 0 ? 1000.0 / g_pHyprRenderer->m_mostHzMonitor->m_refreshRate : 16;
    self->updateTimeout(std::chrono::milliseconds(TIMEOUT));
}

// COLOR FADE state: crossfade between glow colors when the cursor shape changes
static int                                   g_haloTarget = 0x7a2cf0, g_haloPrev = 0x7a2cf0;
static std::chrono::steady_clock::time_point g_haloFadeStart;
static constexpr float                       HALO_FADE_MS = 320.F;

// SCROLL STRETCH state: the arrow stretches toward the scroll direction while scrolling,
// then springs back (damped, with a small overshoot to the other side) when scrolling stops.
static float                                 g_scrollAmt = 0.F; // accumulated pull, 0..1
static double                                g_scrollDx = 0, g_scrollDy = 1; // unit direction of the scroll (screen space)
static std::chrono::steady_clock::time_point g_scrollLast;

// CLICK ANIMATION state (see clickAnim below)
static std::chrono::steady_clock::time_point g_clickDown, g_clickUp;
static bool                                  g_clickHeld = false, g_clickSeen = false;

CDynamicCursors::CDynamicCursors() {
    // CLICK ANIMATION: remember when buttons go down/up (the cursor reads this when drawing)
    static const auto LISTENER_BUTTON = Event::bus()->m_events.input.mouse.button.listen([](IPointer::SButtonEvent ev, Event::SCallbackInfo&) {
        auto now = std::chrono::steady_clock::now();
        if (ev.state == WL_POINTER_BUTTON_STATE_PRESSED) {
            g_clickDown = now;
            g_clickHeld = true;
            g_clickSeen = true;
        } else {
            g_clickUp   = now;
            g_clickHeld = false;
        }
    });

    // SCROLL STRETCH: every wheel/touchpad event adds a bit of pull toward its direction
    static const auto LISTENER_AXIS = Event::bus()->m_events.input.mouse.axis.listen([](IPointer::SAxisEvent ev, Event::SCallbackInfo&) {
        if (ev.delta == 0.0)
            return;
        double dx = 0, dy = 0, sgn = ev.delta > 0 ? 1.0 : -1.0;
        if (ev.axis == WL_POINTER_AXIS_HORIZONTAL_SCROLL)
            dx = sgn;
        else
            dy = sgn;
        if (dx != g_scrollDx || dy != g_scrollDy) { // direction changed: start over
            g_scrollAmt = 0.F;
            g_scrollDx  = dx;
            g_scrollDy  = dy;
        }
        g_scrollAmt  = std::min(1.F, g_scrollAmt + std::clamp((float)(std::abs(ev.delta) / 50.0), 0.04F, 0.2F));
        g_scrollLast = std::chrono::steady_clock::now();
    });

    this->tick = SP<CEventLoopTimer>(new CEventLoopTimer(std::chrono::microseconds(500), tickRaw, nullptr));
    g_pEventLoopManager->addTimer(this->tick);
}

CDynamicCursors::~CDynamicCursors() {
    // stop and deallocate timer
    g_pEventLoopManager->removeTimer(this->tick);
    this->tick.reset();

    // release software lock
    if (zoomSoftware) {
        Pointer::mgr()->unlockSoftwareAll();
        zoomSoftware = false;
    }
}

/*
Reimplements rendering of the software cursor.
Is also largely identical to hyprlands impl, but uses our custom rendering to rotate the cursor.
*/
// ---- TRAIL PATCH ----
// motion trail: afterimages of the cursor that fade out. To disable: load the stock plugin instead (see plugins.lua).
static constexpr int    TRAIL_LIFE_MS   = 180;  // how long an afterimage lives
static constexpr int    TRAIL_SAMPLE_MS = 6;    // spacing between afterimages
static constexpr float  TRAIL_ALPHA     = 0.9F; // opacity of the newest afterimage
static constexpr double TRAIL_MIN_DIST  = 4.0;
static constexpr double TRAIL_STEP_PX   = 5.0;   // distance between interpolated afterimages
static constexpr float  TRAIL_PER_GHOST = 0.16F; // opacity multiplier per afterimage (they overlap and add up)
static constexpr size_t TRAIL_MAX_GHOSTS = 140;  // render budget per frame  // px, skip afterimages overlapping the cursor

struct STrailPoint {
    int                                   haloRGB;
    CBox                                  box;
    double                                stretchAngle;
    Vector2D                              stretchMagnitude;
    std::chrono::steady_clock::time_point t;
};
// per-monitor state: box coords are monitor-local, so trails must never mix between monitors
struct STrailMon {
    std::vector<STrailPoint> pts;
    CBox                     bbox; // bounding box of live trail (global/logical coords), for damage
    double                   lastX = 0, lastY = 0;
    bool                     haveLast = false;
};
static std::unordered_map<void*, STrailMon> g_trailMons;

// ---- CLICK ANIMATION ----
// press: the arrow shrinks toward its tip (and stays small while held); release: springs back.
// press also fires a ring of light that expands and fades.

static float easeOut(float u) {
    u = std::clamp(u, 0.F, 1.F);
    return 1.F - (1.F - u) * (1.F - u) * (1.F - u);
}

static bool clickAnim(float& press, float& rippleScale, float& rippleAlpha) {
    press = 1.F; rippleScale = 0.F; rippleAlpha = 0.F;
    if (!g_clickSeen)
        return false;
    auto  now  = std::chrono::steady_clock::now();
    float down = std::chrono::duration<float, std::milli>(now - g_clickDown).count();
    float up   = std::chrono::duration<float, std::milli>(now - g_clickUp).count();
    bool  live = false;

    if (g_clickHeld) {
        press = 1.F - 0.20F * easeOut(down / 70.F);
        live  = down < 70.F;
    } else if (up < 160.F && g_clickUp > g_clickDown) {
        press = 0.80F + 0.20F * easeOut(up / 160.F);
        live  = true;
    }
    // (the expanding ring on click was removed on request; only the press-shrink animation stays)
    return live;
}

// returns true while the scroll animation is running; amount is signed (negative = overshoot to the opposite side)
static bool scrollAnim(float& amount) {
    amount = 0.F;
    if (g_scrollAmt <= 0.F)
        return false;
    float since = std::chrono::duration<float, std::milli>(std::chrono::steady_clock::now() - g_scrollLast).count();
    if (since < 110.F) { // still scrolling: keep stretching
        amount = g_scrollAmt;
        return true;
    }
    float t = since - 110.F; // released: damped spring with overshoot
    amount  = g_scrollAmt * std::exp(-t / 130.F) * std::cos(2.F * (float)M_PI * t / 300.F);
    if (t > 500.F || std::abs(amount) < 0.01F && t > 150.F) {
        g_scrollAmt = 0.F;
        amount      = 0.F;
        return false;
    }
    return true;
}

void CDynamicCursors::renderSoftware(Pointer::CPointerManager* pointers, PHLMONITOR pMonitor, const Time::steady_tp& now, CRegion& damage, std::optional<Vector2D> overridePos,
                                     bool screencopy, bool forceRender) {
    if (!pointers->hasCursor())
        return;

    refreshCursorStyle(); // CURSOR STYLE: re-read ~/.config/cursor-style (throttled)
    auto state = pointers->stateFor(pMonitor);
    auto zoom  = resultShown.scale;

    if (!state->hardwareFailed && state->softwareLocks == 0 && !screencopy) {
        if (pointers->m_currentCursorImage.surface)
            pointers->m_currentCursorImage.surface->resource()->frame(now);

        return;
    }

    // don't render cursor on screencopy if using sw cursors
    // otherwise we draw the cursor again for screencopy when using sw cursors
    // unless this is toplevel capture and we *actually* have to force render cursors
    if (screencopy && !forceRender && (state->hardwareFailed || state->softwareLocks != 0))
        return;

    auto box = state->box.copy();
    if (overridePos.has_value()) {
        box.x = overridePos->x;
        box.y = overridePos->y;

        box.translate(-pointers->m_currentCursorImage.hotspot);
    }

    auto texture = pointers->getCurrentCursorTexture();
    bool nearest = false;

    if (zoom > 1) {
        // this first has to undo the hotspot transform from getCursorBoxGlobal
        box.x += pointers->m_currentCursorImage.hotspot.x;
        box.y += pointers->m_currentCursorImage.hotspot.y;

        auto high = highres.getTexture();

        if (high) {
            texture  = high;
            auto buf = highres.getBuffer();

            // we calculate a more accurate hotspot location if we have bigger shapes
            box.x -= (buf->m_hotspot.x / buf->size.x) * pointers->m_currentCursorImage.size.x * zoom;
            box.y -= (buf->m_hotspot.y / buf->size.y) * pointers->m_currentCursorImage.size.y * zoom;

            // only use nearest-neighbour if magnifying over size
            nearest = CONFIG(highresNearest) == 2 && pointers->m_currentCursorImage.size.x * zoom > buf->size.x;

        } else {
            box.x -= pointers->m_currentCursorImage.hotspot.x * zoom;
            box.y -= pointers->m_currentCursorImage.hotspot.y * zoom;

            nearest = CONFIG(highresNearest);
        }
    }

    if (!texture)
        return;

    box.w *= zoom;
    box.h *= zoom;

    // PER-MONITOR CLIP PATCH: the big (rotated) cursor image spills over monitor edges, only draw it on the monitor that holds the pointer
    auto   pp        = pointers->m_pointerPos;
    bool   pointerOn = pp.x >= pMonitor->m_position.x && pp.y >= pMonitor->m_position.y && pp.x < pMonitor->m_position.x + pMonitor->m_size.x &&
        pp.y < pMonitor->m_position.y + pMonitor->m_size.y;

    if (!pointerOn || box.intersection(CBox{{}, {pMonitor->m_size}}).empty()) {
        // TRAIL PATCH: cursor left this monitor; flush its trail and repaint the area once so no ghost stays stuck
        auto it = g_trailMons.find(pMonitor.get());
        if (it != g_trailMons.end() && (!it->second.pts.empty() || it->second.bbox.w > 0)) {
            if (it->second.bbox.w > 0)
                g_pHyprRenderer->damageBox(it->second.bbox, false);
            it->second.pts.clear();
            it->second.bbox     = CBox{};
            it->second.haveLast = false;
        }
        return;
    }

    box.scale(pMonitor->m_scale);
    box.x = std::round(box.x);
    box.y = std::round(box.y);

    // we rotate the cursor by our calculated amount
    box.rot = resultShown.rotation;

    CCursorPassElement::SRenderData data;
    data.tex = texture;
    data.box = box;

    data.hotspot          = pointers->m_currentCursorImage.hotspot * state->monitor->m_scale * zoom;
    data.nearest          = nearest;
    data.stretchAngle     = resultShown.stretch.angle;
    data.stretchMagnitude = resultShown.stretch.magnitude;
    if (!g_anims.speed)
        data.stretchMagnitude = Vector2D{1, 1}; // ANIMATION TOGGLE: stretch by speed off
    data.haloRGB          = haloColorForShape(g_curShape); // HALO PATCH
    bool colorLive = false; // COLOR FADE
    {
        auto nowF = std::chrono::steady_clock::now();
        if (data.haloRGB != g_haloTarget) {
            g_haloPrev      = g_haloTarget;
            g_haloTarget    = data.haloRGB;
            g_haloFadeStart = nowF;
        }
        float t = std::chrono::duration<float, std::milli>(nowF - g_haloFadeStart).count() / HALO_FADE_MS;
        data.haloPrevRGB = g_haloPrev;
        float tc         = std::clamp(t, 0.F, 1.F);
        data.haloMix     = tc * tc * tc * (tc * (tc * 6.F - 15.F) + 10.F); // smootherstep: no visible start/end kink
        colorLive        = t < 1.F;
    }
    bool clickLive = clickAnim(data.pressScale, data.rippleScale, data.rippleAlpha); // CLICK ANIMATION
    float scrollAmount = 0.F; // SCROLL STRETCH
    bool  scrollLive   = scrollAnim(scrollAmount);
    if (!g_anims.scroll) { // ANIMATION TOGGLE: scroll stretch off
        scrollAmount = 0.F;
        scrollLive   = false;
    }
    if (std::abs(scrollAmount) > 0.001F) {
        // stretch toward the scroll direction (negative amount = the other way, the spring-back overshoot)
        double sx = g_scrollDx, sy = g_scrollDy;
        if (scrollAmount < 0) { sx = -sx; sy = -sy; }
        double k = std::abs(scrollAmount);
        // same convention as the stretch mode: the tail points opposite to the "velocity", so pass -direction
        double vx = -sx, vy = -sy;
        double ang = -std::atan(vx / vy) + M_PI; // vy == 0 -> atan(+-inf) = +-pi/2
        if (vy > 0)
            ang += M_PI;
        data.stretchAngle     = ang;
        data.stretchMagnitude = Vector2D{1.0 - k * 0.30, 1.0 + k * 0.85};
        // the glow stretches too
        data.haloStretchAngle = ang;
        data.haloStretchMag   = Vector2D{1.0 - k * 0.25, 1.0 + k * 1.10};

    }

    // TRAIL PATCH: update history, build ghosts (state is per monitor)
    {
        auto  nowT = std::chrono::steady_clock::now();
        auto& tm   = g_trailMons[pMonitor.get()];
        auto& g_trail = tm.pts;
        std::erase_if(g_trail, [&](const STrailPoint& p) { return std::chrono::duration_cast<std::chrono::milliseconds>(nowT - p.t).count() > TRAIL_LIFE_MS; });

        // CONTINUOUS TRAIL: interpolate extra afterimages along every segment of the path, so the glow
        // reads as one smooth streak of light instead of separate dots. Oldest first.
        {
            struct SNode {
                CBox  box;
                float alpha;
                int   rgb;
            };
            std::vector<SNode> nodes;
            for (auto& p : g_trail) {
                double age   = std::chrono::duration<double, std::milli>(nowT - p.t).count();
                float  alpha = TRAIL_ALPHA * (1.F - (float)(age / TRAIL_LIFE_MS));
                if (alpha > 0.F)
                    nodes.push_back({p.box, alpha, p.haloRGB});
            }
            nodes.push_back({box, TRAIL_ALPHA, data.haloRGB}); // the cursor itself closes the path

            for (size_t i = 0; i + 1 < nodes.size() && data.ghosts.size() < TRAIL_MAX_GHOSTS; i++) {
                auto&  a0   = nodes[i];
                auto&  a1   = nodes[i + 1];
                double dx   = a1.box.x - a0.box.x, dy = a1.box.y - a0.box.y;
                double dist = std::sqrt(dx * dx + dy * dy);
                if (dist > 600.0)
                    continue; // monitor jump, not a stroke
                int n = std::max(1, (int)std::ceil(dist / TRAIL_STEP_PX));
                for (int k = 0; k < n && data.ghosts.size() < TRAIL_MAX_GHOSTS; k++) {
                    double t = (double)k / n;
                    CBox   gb = a0.box;
                    gb.x      = a0.box.x + dx * t;
                    gb.y      = a0.box.y + dy * t;
                    double rd = a1.box.rot - a0.box.rot;
                    while (rd > M_PI) rd -= 2 * M_PI;
                    while (rd < -M_PI) rd += 2 * M_PI;
                    gb.rot       = a0.box.rot + rd * t;
                    float alpha  = (a0.alpha + (a1.alpha - a0.alpha) * (float)t) * TRAIL_PER_GHOST;
                    double ex = gb.x - box.x, ey = gb.y - box.y;
                    if (std::sqrt(ex * ex + ey * ey) < TRAIL_MIN_DIST || alpha <= 0.F)
                        continue;
                    data.ghosts.push_back({gb, alpha, 0.0, Vector2D{1, 1}, a0.rgb});
                }
            }
        }

        // only record while actually moving, otherwise the trail would never die out
        bool moved = tm.haveLast && std::hypot(box.x - tm.lastX, box.y - tm.lastY) >= 1.0;
        // a jump this large means the cursor came from another monitor: no trail across that
        if (tm.haveLast && std::hypot(box.x - tm.lastX, box.y - tm.lastY) > 400.0) {
            g_trail.clear();
            moved = false;
        }
        tm.lastX = box.x; tm.lastY = box.y; tm.haveLast = true;
        if (moved && (g_trail.empty() || std::chrono::duration_cast<std::chrono::milliseconds>(nowT - g_trail.back().t).count() >= TRAIL_SAMPLE_MS))
            g_trail.push_back({data.haloRGB, box, resultShown.stretch.angle, resultShown.stretch.magnitude, nowT});

        // bounding box of everything alive, in logical coords, so damage covers the fading trail
        if (!g_trail.empty()) {
            double x0 = box.x, y0 = box.y, x1 = box.x + box.w, y1 = box.y + box.h;
            for (auto& p : g_trail) {
                x0 = std::min(x0, p.box.x); y0 = std::min(y0, p.box.y);
                x1 = std::max(x1, p.box.x + p.box.w); y1 = std::max(y1, p.box.y + p.box.h);
            }
            double diag = std::sqrt(box.w * box.w + box.h * box.h);
            tm.bbox = CBox{x0 - diag, y0 - diag, (x1 - x0) + diag * 2, (y1 - y0) + diag * 2};
            tm.bbox.scale(1.0 / pMonitor->m_scale);
            tm.bbox.translate(pMonitor->m_position);
            // keep frames coming until the trail has faded out
            g_pHyprRenderer->damageBox(tm.bbox, false);
        } else
            tm.bbox = CBox{};
    }

    // ANIMATION TOGGLES (~/.config/cursor-anims)
    if (!g_anims.trail)
        data.ghosts.clear();
    if (!g_anims.click) {
        data.pressScale = 1.F;
        clickLive       = false;
    }
    if (!g_anims.colorfade) {
        data.haloMix = 1.F;
        colorLive    = false;
    }
    if (!g_anims.rotate)
        data.box.rot = 0;
    if (g_cursorStyle == 0) { // CURSOR STYLE normal: classic cursor
        data.ghosts.clear();
        data.pressScale = 1.F; data.rippleAlpha = 0.F; data.rippleScale = 0.F;
        data.haloStretchMag = Vector2D{1, 1};
        data.stretchMagnitude = Vector2D{1, 1};
        scrollLive = false; clickLive = false; colorLive = false;
    }
    bool rouletteLive = g_cursorStyle != 0 && (data.haloRGB & HALO_ROULETTE) != 0; // ROULETTE: keep frames coming while loading
    if (clickLive || colorLive || rouletteLive || scrollLive) {
        // CLICK ANIMATION: keep damaging so the next frames are drawn until the animation ends
        double pad = std::sqrt(box.w * box.w + box.h * box.h) * 1.2;
        CBox   ab  = CBox{box.x - pad, box.y - pad, box.w + pad * 2, box.h + pad * 2};
        ab.scale(1.0 / pMonitor->m_scale);
        ab.translate(pMonitor->m_position);
        g_pHyprRenderer->damageBox(ab, false);
    }

    g_pHyprRenderer->m_renderPass.add(makeUnique<CCursorPassElement>(data));

    if (pointers->m_currentCursorImage.surface)
        pointers->m_currentCursorImage.surface->resource()->frame(now);
}

/*
This function implements damaging the screen such that the software cursor is drawn.
It is largely identical to hyprlands implementation, but expands the damage region, to accommodate various rotations.
*/
void CDynamicCursors::damageSoftware(Pointer::CPointerManager* pointers) {

    // we damage a padding of the diagonal around the hotspot, to accommodate for all possible hotspots and rotations
    auto     zoom     = resultShown.scale;
    Vector2D size     = pointers->m_currentCursorImage.size / pointers->m_currentCursorImage.scale * zoom;
    int      diagonal = size.size();
    Vector2D padding  = {diagonal, diagonal};

    CBox b = CBox{pointers->m_pointerPos, size + (padding * 2)}.translate(-(pointers->m_currentCursorImage.hotspot * zoom + padding));

    static auto PNOHW = CConfigValue<Hyprlang::INT>("cursor:no_hardware_cursors");

    // TRAIL PATCH: also damage the fading trails
    for (auto& [k, tm] : g_trailMons) {
        if (tm.bbox.w > 0) {
            double x0 = std::min(b.x, tm.bbox.x), y0 = std::min(b.y, tm.bbox.y);
            double x1 = std::max(b.x + b.w, tm.bbox.x + tm.bbox.w), y1 = std::max(b.y + b.h, tm.bbox.y + tm.bbox.h);
            b = CBox{x0, y0, x1 - x0, y1 - y0};
        }
    }

    for (auto& mw : pointers->m_monitorStates) {
        if (mw->monitor.expired())
            continue;

        if ((mw->softwareLocks > 0 || mw->hardwareFailed || *PNOHW) && b.overlaps({mw->monitor->m_position, mw->monitor->m_size})) {
            g_pHyprRenderer->damageBox(b, mw->monitor->shouldSkipScheduleFrameOnMouseEvent());
            break;
        }
    }
}

/*
This function reimplements the hardware cursor buffer drawing.
It is largely copied from hyprland, but adjusted to allow the cursor to be rotated.
*/
SP<Aquamarine::IBuffer> CDynamicCursors::renderHardware(Pointer::CPointerManager* pointers, SP<Pointer::CPointerManager::SMonitorPointerState> state,
                                                        SP<Render::ITexture> texture) {
    auto output = state->monitor->m_output;

    auto maxSize = output->cursorPlaneSize();
    auto zoom    = resultShown.scale;

    auto cursorSize     = pointers->m_currentCursorImage.size * zoom;
    int  cursorDiagonal = cursorSize.size();
    auto cursorPadding  = Vector2D{cursorDiagonal, cursorDiagonal};
    auto targetSize     = cursorSize + cursorPadding * 2;

    if (maxSize == Vector2D{})
        return nullptr;

    if (maxSize != Vector2D{-1, -1}) {
        if (targetSize.x > maxSize.x || targetSize.y > maxSize.y) {
            Log::logger->log(Log::TRACE, "hardware cursor too big! {} > {}", pointers->m_currentCursorImage.size, maxSize);
            return nullptr;
        }
    } else {
        maxSize = targetSize;
        if (maxSize.x < 16 || maxSize.y < 16)
            maxSize = {16, 16}; // fix some annoying crashes in nest
    }

    if (!state->monitor->m_cursorSwapchain || maxSize != state->monitor->m_cursorSwapchain->currentOptions().size ||
        state->monitor->m_cursorSwapchain->currentOptions().length != 3) {

        if (!state->monitor->m_cursorSwapchain) {
            auto backend = state->monitor->m_output->getBackend();
            auto primary = backend->getPrimary();

            state->monitor->m_cursorSwapchain = Aquamarine::CSwapchain::create(state->monitor->m_output->getBackend()->preferredAllocator(), primary ? primary.lock() : backend);
        }

        auto options = state->monitor->m_cursorSwapchain->currentOptions();
        options.size = maxSize;
        // we still have to create a triple buffering swapchain, as we seem to be running into some sort of race condition
        // or something. I'll continue debugging this when I find some energy again, I've spent too much time here already.
        options.length   = 3;
        options.scanout  = true;
        options.cursor   = true;
        options.multigpu = state->monitor->m_output->getBackend()->preferredAllocator()->drmFD() != g_pCompositor->m_drm.fd;
        // We do not set the format. If it's unset (DRM_FORMAT_INVALID) then the swapchain will pick for us,
        // but if it's set, we don't wanna change it.

        if (!state->monitor->m_cursorSwapchain->reconfigure(options)) {
            Log::logger->log(Log::TRACE, "Failed to reconfigure cursor swapchain");
            return nullptr;
        }
    }

    // if we already rendered the cursor, revert the swapchain to avoid rendering the cursor over
    // the current front buffer
    // this flag will be reset in the preRender hook, so when we commit this buffer to KMS
    // see https://github.com/hyprwm/Hyprland/commit/4c3b03516209a49244a8f044143c1162752b8a7a
    // this is however still not enough, see above
    if (state->cursorRendered)
        state->monitor->m_cursorSwapchain->rollback();

    state->cursorRendered = true;

    auto buf = state->monitor->m_cursorSwapchain->next(nullptr);
    if (!buf) {
        Log::logger->log(Log::TRACE, "Failed to acquire a buffer from the cursor swapchain");
        return nullptr;
    }

    CRegion damage = {0, 0, INT16_MAX, INT16_MAX};

    g_pHyprRenderer->m_renderData.pMonitor = state->monitor;
    auto RBO                               = g_pHyprRenderer->getOrCreateRenderbuffer(buf, state->monitor->m_cursorSwapchain->currentOptions().format);

    // we just fail if we cannot create a render buffer, this will force hl to render software cursors, which we support
    if (!RBO)
        return nullptr;

    RBO->bind();

    CRegion damageRegion = {0, 0, INT_MAX, INT_MAX};
    g_pHyprRenderer->beginFullFakeRender(state->monitor.lock(), damageRegion, RBO->getFB());
    g_pHyprRenderer->startRenderPass();

    if (CONFIG(hwDebug))
        g_pHyprRenderer->draw(CClearPassElement::SClearData{CHyprColor{rand() / float(RAND_MAX), rand() / float(RAND_MAX), rand() / float(RAND_MAX), 1.F}});
    else
        g_pHyprRenderer->draw(CClearPassElement::SClearData{{0.F, 0.F, 0.F, 0.F}});

    CBox   xbox      = {cursorPadding, Vector2D{Pointer::mgr()->m_currentCursorImage.size / Pointer::mgr()->m_currentCursorImage.scale * state->monitor->m_scale * zoom}.round()};
    Mat3x3 transform = toTransform(xbox, resultShown.rotation, Pointer::mgr()->m_currentCursorImage.hotspot * state->monitor->m_scale * zoom, resultShown.stretch.angle,
                                   resultShown.stretch.magnitude);

    drawCursor(transform, texture, xbox, damageRegion, zoom > 1 && CONFIG(highresNearest));

    g_pHyprRenderer->endRender();
    g_pHyprRenderer->m_renderData.pMonitor.reset();

    return buf;
}

/*
Implements the hardware cursor setting.
It is also mostly the same as stock hyprland, but with the hotspot translated more into the middle.
*/
bool CDynamicCursors::setHardware(Pointer::CPointerManager* pointers, SP<Pointer::CPointerManager::SMonitorPointerState> state, SP<Aquamarine::IBuffer> buf) {
    if (!(state->monitor->m_output->getBackend()->capabilities() & Aquamarine::IBackendImplementation::eBackendCapabilities::AQ_BACKEND_CAPABILITY_POINTER))
        return false;

    if (!state->monitor->m_cursorSwapchain)
        return false;

    // we need to transform the hotspot manually as we need to indent it by the padding
    int      diagonal = pointers->m_currentCursorImage.size.size();
    Vector2D padding  = {diagonal, diagonal};

    const auto HOTSPOT = CBox{((pointers->m_currentCursorImage.hotspot * state->monitor->m_scale) + padding) * resultShown.scale, {0, 0}}
                             .transform(Math::wlTransformToHyprutils(Math::invertTransform(state->monitor->m_transform)),
                                        state->monitor->m_cursorSwapchain->currentOptions().size.x, state->monitor->m_cursorSwapchain->currentOptions().size.y)
                             .pos();

    Log::logger->log(Log::TRACE, "[pointer] hw transformed hotspot for {}: {}", state->monitor->m_name, HOTSPOT);

    if (!state->monitor->m_output->setCursor(buf, HOTSPOT))
        return false;

    state->cursorFrontBuffer = buf;

    if (!state->monitor->shouldSkipScheduleFrameOnMouseEvent())
        state->monitor->scheduleFrame(Aquamarine::IOutput::AQ_SCHEDULE_CURSOR_SHAPE);

    state->monitor->m_scanoutNeedsCursorUpdate = true;

    return true;
}

/*
Handles cursor move events.
*/
void CDynamicCursors::onCursorMoved(Pointer::CPointerManager* pointers) {
    if (!pointers->hasCursor())
        return;

    const auto CURSORBOX = pointers->getCursorBoxGlobal();
    bool       recalc    = false;

    for (auto& m : State::monitorState()->monitors()) {
        auto state = pointers->stateFor(m);

        state->box = pointers->getCursorBoxLogicalForMonitor(state->monitor.lock());

        auto CROSSES = !m->logicalBox().intersection(CURSORBOX).empty();

        if (!CROSSES && state->cursorFrontBuffer) {
            Log::logger->log(Log::TRACE, "onCursorMoved for output {}: cursor left the viewport, removing it from the backend", m->m_name);
            pointers->setHWCursorBuffer(state, nullptr);
            continue;
        } else if (CROSSES && !state->cursorFrontBuffer) {
            Log::logger->log(Log::TRACE, "onCursorMoved for output {}: cursor entered the output, but no front buffer, forcing recalc", m->m_name);
            recalc = true;
        }

        if (!state->entered)
            continue;

        Hyprutils::Utils::CScopeGuard x([m] { m->onCursorMovedOnMonitor(); });

        if (state->hardwareFailed)
            continue;

        const auto CURSORPOS = pointers->getCursorPosForMonitor(m);
        m->m_output->moveCursor(CURSORPOS);

        state->monitor->m_scanoutNeedsCursorUpdate = true;
    }

    if (recalc)
        pointers->updateCursorBackend();

    // ignore warp
    if (!isMove && CONFIG(ignoreWarps)) {
        auto mode = this->currentMode();
        if (mode)
            mode->warp(lastPos, pointers->m_pointerPos);

        if (CONFIG(shakeEnabled))
            shake.warp(lastPos, pointers->m_pointerPos);
    }

    calculate(MOVE);

    isMove  = false;
    lastPos = pointers->m_pointerPos;
}

void CDynamicCursors::setShape(const std::string& shape) {
    g_curShape = shape; // HALO PATCH
    g_pConfigHandler->m_shapeRules->activate(shape);
    highres.loadShape(shape);
}

void CDynamicCursors::unsetShape() {
    setShape("clientside");
}

void CDynamicCursors::updateTheme() {
    highres.update();
}

/*
Handle cursor tick events.
*/
void CDynamicCursors::onTick(Pointer::CPointerManager* pointers) {
    calculate(TICK);
}

IMode* CDynamicCursors::currentMode() {
    switch (CONFIG(mode)) {
        case MODE_ROTATE: return &rotate;
        case MODE_TILT: return &tilt;
        case MODE_STRETCH: return &stretch;
        default: return nullptr;
    }
}

void CDynamicCursors::calculate(EModeUpdate type) {

    IMode* mode = currentMode();

    // calculate angle and zoom
    if (mode) {
        // reset mode if it has changed
        if (mode != lastMode)
            mode->reset();

        if (mode->strategy() == type)
            resultMode = mode->update(Pointer::mgr()->m_pointerPos);

        // ROTATE+STRETCH PATCH: in rotate mode also run stretch and merge it in
        // (stretch is applied along the velocity after the cursor is rotated)
        if (mode == &rotate) {
            if (mode != lastMode)
                stretch.reset();
            if (type == TICK)
                resultStretchPart = stretch.update(Pointer::mgr()->m_pointerPos);
            resultMode.stretch = resultStretchPart.stretch;
        }
    } else
        resultMode = SModeResult();

    lastMode = mode;

    if (CONFIG(shakeEnabled)) {
        if (type == TICK)
            resultShake = shake.update(Pointer::mgr()->m_pointerPos);

        // reset mode results if shaking
        if (resultShake > 1 && !CONFIG(shakeEffects))
            resultMode = SModeResult();
    } else
        resultShake = 1;

    auto result = resultMode;
    result.scale *= resultShake;

    if (resultShown.hasDifference(&result, CONFIG(threshold) * (std::numbers::pi / 180.0), 0.01, 0.01)) {
        resultShown = result;
        resultShown.clamp(CONFIG(threshold) * (std::numbers::pi / 180.0), 0.01, 0.01); // clamp low values so it is rendered pixel-perfectly when no effect

        // lock software cursors if zooming
        if (resultShown.scale > 1) {
            if (!zoomSoftware) {
                Pointer::mgr()->lockSoftwareAll();
                zoomSoftware = true;
            }
        } else {
            if (zoomSoftware) {
                // damage so it is cleared properly
                Pointer::mgr()->damageIfSoftware();

                Pointer::mgr()->unlockSoftwareAll();
                zoomSoftware = false;
            }
        }

        // damage software and change hardware cursor shape
        Pointer::mgr()->damageIfSoftware();

        bool entered = false;

        for (auto& m : State::monitorState()->monitors()) {
            auto state = Pointer::mgr()->stateFor(m);

            if (state->entered)
                entered = true;
            if (state->hardwareFailed || !state->entered)
                continue;

            Pointer::mgr()->attemptHardwareCursor(state);
        }

        // there should always be one monitor entered
        // this fixes an issue where the cursor shape would not properly update after change
        if (!entered) {
            Log::logger->log(Log::INFO, "[dynamic-cursors] updating because none entered");
            Pointer::mgr()->recheckEnteredOutputs();
            Pointer::mgr()->updateCursorBackend();
        }
    }
}

void CDynamicCursors::setMove() {
    isMove = true;
}

void CDynamicCursors::dispatchMagnify(std::optional<int> duration, std::optional<float> size) {
    if (!CONFIG(shakeEnabled))
        return;

    shake.force(duration, size);
}
