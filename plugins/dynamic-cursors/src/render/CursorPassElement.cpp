#include "CursorPassElement.hpp"
#include "renderer.hpp"
#include "../halo.hpp"

#include <hyprland/src/render/Renderer.hpp>
#include <cairo/cairo.h>
#include <map>
#include <vector>
#include <chrono>
#include <cmath>

using namespace Hyprutils::Utils;

CCursorPassElement::CCursorPassElement(const CCursorPassElement::SRenderData& data) : m_data(data) {
    ;
}

std::vector<UP<IPassElement>> CCursorPassElement::draw() {
    const bool effects = g_cursorStyle != 0; // "normal" style: classic cursor, no glow/trail/ring
    // HALO PATCH: the glow is drawn here (not baked in the cursor theme), tinted by cursor shape.
    // It is never stretched; the trail is made of older copies of it. Oldest (faintest) first, arrow on top.
    static std::map<int, SP<Render::ITexture>> halos;
    // ROULETTE: while loading, the glow is split into all the colors and spins. 36 pre-rendered phases (10 deg apart).
    static std::vector<SP<Render::ITexture>> rouletteByStyle[3];
    auto rouletteFrame = [&]() -> SP<Render::ITexture> {
        constexpr int    FRAMES   = 36;
        constexpr double PERIOD   = 1100.0; // ms per revolution
        const int* COLORS   = palette().roulette; // the 6 colors of the active palette
        auto&      roulette = rouletteByStyle[g_cursorStyle];
        if (roulette.empty()) {
            for (int f = 0; f < FRAMES; f++) {
                auto* surf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 256, 256);
                auto* cr   = cairo_create(surf);
                cairo_push_group(cr);
                for (int i = 0; i < 6; i++) {
                    double a0 = (f * 2 * M_PI / FRAMES) + i * (M_PI / 3), a1 = a0 + M_PI / 3;
                    int    c  = COLORS[i];
                    cairo_set_source_rgb(cr, ((c >> 16) & 0xff) / 255., ((c >> 8) & 0xff) / 255., (c & 0xff) / 255.);
                    cairo_move_to(cr, 120, 126);
                    cairo_arc(cr, 120, 126, 128, a0, a1 + 0.01);
                    cairo_close_path(cr);
                    cairo_fill(cr);
                }
                cairo_pop_group_to_source(cr);
                auto* mask = cairo_pattern_create_radial(120, 126, 0, 120, 126, 127);
                cairo_pattern_add_color_stop_rgba(mask, 0.00, 0, 0, 0, 0.95);
                cairo_pattern_add_color_stop_rgba(mask, 0.30, 0, 0, 0, 0.60);
                cairo_pattern_add_color_stop_rgba(mask, 0.65, 0, 0, 0, 0.22);
                cairo_pattern_add_color_stop_rgba(mask, 1.00, 0, 0, 0, 0.00);
                cairo_mask(cr, mask);
                cairo_surface_flush(surf);
                roulette.push_back(g_pHyprRenderer->createTexture(surf));
                cairo_pattern_destroy(mask);
                cairo_destroy(cr);
                cairo_surface_destroy(surf);
            }
        }
        using namespace std::chrono;
        double ms  = duration<double, std::milli>(steady_clock::now().time_since_epoch()).count();
        int    idx = (int)(std::fmod(ms, PERIOD) / PERIOD * FRAMES) % FRAMES;
        return roulette[idx];
    };

    // SPLIT: alias cursor -- left half link-blue, right half white, faded in the middle
    static SP<Render::ITexture> splitTexByStyle[3];
    auto                        splitFrame = [&]() -> SP<Render::ITexture> {
        auto& splitTex = splitTexByStyle[g_cursorStyle];
        if (!splitTex) {
            const int cA = palette().aliasA, cB = palette().aliasB;
            auto* surf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 256, 256);
            auto* cr   = cairo_create(surf);
            cairo_push_group(cr);
            auto* lin = cairo_pattern_create_linear(0, 0, 240, 0);
            cairo_pattern_add_color_stop_rgb(lin, 0.00, ((cA >> 16) & 0xff) / 255., ((cA >> 8) & 0xff) / 255., (cA & 0xff) / 255.);
            cairo_pattern_add_color_stop_rgb(lin, 0.35, ((cA >> 16) & 0xff) / 255., ((cA >> 8) & 0xff) / 255., (cA & 0xff) / 255.);
            cairo_pattern_add_color_stop_rgb(lin, 0.65, ((cB >> 16) & 0xff) / 255., ((cB >> 8) & 0xff) / 255., (cB & 0xff) / 255.);
            cairo_pattern_add_color_stop_rgb(lin, 1.00, ((cB >> 16) & 0xff) / 255., ((cB >> 8) & 0xff) / 255., (cB & 0xff) / 255.);
            cairo_set_source(cr, lin);
            cairo_paint(cr);
            cairo_pop_group_to_source(cr);
            auto* mask = cairo_pattern_create_radial(120, 126, 0, 120, 126, 127);
            cairo_pattern_add_color_stop_rgba(mask, 0.00, 0, 0, 0, 0.95);
            cairo_pattern_add_color_stop_rgba(mask, 0.30, 0, 0, 0, 0.60);
            cairo_pattern_add_color_stop_rgba(mask, 0.65, 0, 0, 0, 0.22);
            cairo_pattern_add_color_stop_rgba(mask, 1.00, 0, 0, 0, 0.00);
            cairo_mask(cr, mask);
            cairo_surface_flush(surf);
            splitTex = g_pHyprRenderer->createTexture(surf);
            cairo_pattern_destroy(lin);
            cairo_pattern_destroy(mask);
            cairo_destroy(cr);
            cairo_surface_destroy(surf);
        }
        return splitTex;
    };

    auto haloFor = [&](int rgb) -> SP<Render::ITexture> {
        if (rgb & 0x4000000)
            return splitFrame();
        if (rgb & 0x2000000)
            return rouletteFrame();
        const bool ring = (rgb & 0x1000000) != 0; // CLICK ANIMATION: ring variant (transparent center)
        rgb &= 0xffffff;
        const int key = rgb | (ring ? 0x1000000 : 0) | (g_cursorStyle << 28);
        auto it = halos.find(key);
        if (it != halos.end())
            return it->second;
        double r = ((rgb >> 16) & 0xff) / 255., g = ((rgb >> 8) & 0xff) / 255., b = (rgb & 0xff) / 255.;
        auto*  surf = cairo_image_surface_create(CAIRO_FORMAT_ARGB32, 256, 256);
        auto*  cr   = cairo_create(surf);
        auto*  grad = cairo_pattern_create_radial(120, 126, 0, 120, 126, 127);
        if (ring) {
            cairo_pattern_add_color_stop_rgba(grad, 0.00, r, g, b, 0.00);
            cairo_pattern_add_color_stop_rgba(grad, 0.55, r, g, b, 0.00);
            cairo_pattern_add_color_stop_rgba(grad, 0.80, r, g, b, 0.95);
            cairo_pattern_add_color_stop_rgba(grad, 1.00, r, g, b, 0.00);
        } else {
            cairo_pattern_add_color_stop_rgba(grad, 0.00, r, g, b, 0.95);
            cairo_pattern_add_color_stop_rgba(grad, 0.30, r * 0.88, g * 0.88, b * 0.88, 0.60);
            cairo_pattern_add_color_stop_rgba(grad, 0.65, r * 0.60, g * 0.60, b * 0.60, 0.22);
            cairo_pattern_add_color_stop_rgba(grad, 1.00, r * 0.45, g * 0.45, b * 0.45, 0.00);
        }
        cairo_set_source(cr, grad);
        cairo_paint(cr);
        cairo_surface_flush(surf);
        auto tex = g_pHyprRenderer->createTexture(surf);
        cairo_pattern_destroy(grad);
        cairo_destroy(cr);
        cairo_surface_destroy(surf);
        halos[key] = tex;
        return tex;
    };

    for (auto& g : m_data.ghosts) {
        if (!effects)
            break;
        auto tex = haloFor(g.haloRGB);
        if (!tex)
            continue;
        // rotate the glow around the hotspot like the arrow, so it stays centered on the arrow body
        CBox   gb = g.box;
        Mat3x3 gt = toTransform(gb, gb.rot, m_data.hotspot, 0, {1, 1});
        gb.rot    = 0;
        drawCursor(gt, tex, gb, g_pHyprRenderer->m_renderData.damage, false, g.alpha);
    }
    // COLOR FADE: when the shape (color) changes, the old glow stays and the new one fades in over it
    if (effects && m_data.haloMix < 1.F) {
        if (auto tex = haloFor(m_data.haloPrevRGB)) {
            CBox   hb = m_data.box;
            Mat3x3 ht = toTransform(hb, hb.rot, m_data.hotspot, m_data.haloStretchAngle, m_data.haloStretchMag);
            hb.rot    = 0;
            drawCursor(ht, tex, hb, g_pHyprRenderer->m_renderData.damage, false, 1.F);
        }
    }
    if (effects)
    if (auto tex = haloFor(m_data.haloRGB)) {
        CBox   hb = m_data.box;
        Mat3x3 ht = toTransform(hb, hb.rot, m_data.hotspot, m_data.haloStretchAngle, m_data.haloStretchMag);
        hb.rot    = 0;
        drawCursor(ht, tex, hb, g_pHyprRenderer->m_renderData.damage, false, m_data.haloMix);
    }

    // CLICK ANIMATION: expanding ring of light around the glow center
    if (m_data.rippleAlpha > 0.F && m_data.rippleScale > 0.F) {
        if (auto tex = haloFor(m_data.haloRGB | 0x1000000)) {
            CBox     rb = m_data.box;
            rb.rot      = 0;
            Vector2D c  = {rb.x + rb.w * (120. / 256.), rb.y + rb.h * (126. / 256.)};
            Mat3x3   rt = Mat3x3::identity();
            rt.translate(c);
            rt.scale({m_data.rippleScale, m_data.rippleScale});
            rt.translate({-c.x, -c.y});
            drawCursor(rt, tex, rb, g_pHyprRenderer->m_renderData.damage, false, m_data.rippleAlpha);
        }
    }

    Mat3x3 transform = toTransform(m_data.box, m_data.box.rot, m_data.hotspot, m_data.stretchAngle, m_data.stretchMagnitude, m_data.pressScale);
    m_data.box.rot   = 0;

    drawCursor(transform, m_data.tex, m_data.box, g_pHyprRenderer->m_renderData.damage, m_data.nearest);

    return {}; // no passes to be submitted later
}

bool CCursorPassElement::needsLiveBlur() {
    return false; // TODO?
}

bool CCursorPassElement::needsPrecomputeBlur() {
    return false; // TODO?
}

std::optional<CBox> CCursorPassElement::boundingBox() {
    return m_data.box.copy().scale(1.F / g_pHyprRenderer->m_renderData.pMonitor->m_scale).round();
}

CRegion CCursorPassElement::opaqueRegion() {
    return {}; // TODO:
}

void CCursorPassElement::discard() {
    ;
}
