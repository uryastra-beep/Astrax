#pragma once

#include <hyprland/src/render/pass/PassElement.hpp>
#include <hyprland/src/render/Texture.hpp>
#include <optional>

class CCursorPassElement : public IPassElement {
  public:
    // TRAIL PATCH: one fading afterimage of the cursor
    struct SGhost {
        CBox     box;
        float    alpha;
        double   stretchAngle;
        Vector2D stretchMagnitude;
        int      haloRGB = 0x7a2cf0;
    };

    struct SRenderData {
        SP<Render::ITexture> tex;
        CBox                 box;
        CRegion              damage;

        Vector2D hotspot;
        bool     nearest;
        double   stretchAngle;
        Vector2D stretchMagnitude;

        int                 haloRGB = 0x7a2cf0; // HALO PATCH
        int                 haloPrevRGB = 0x7a2cf0; // COLOR FADE: color we are fading from
        float               haloMix     = 1.F;      // COLOR FADE: 0 = still prev, 1 = fully haloRGB
        double              haloStretchAngle = 0;       // SCROLL STRETCH: the glow stretches too (only while scrolling)
        Vector2D            haloStretchMag   = {1, 1};
        float               pressScale  = 1.F;  // CLICK ANIMATION: arrow scale while pressed
        float               rippleScale = 0.F;  // CLICK ANIMATION: expanding ring (0 = none)
        float               rippleAlpha = 0.F;
        std::vector<SGhost> ghosts;     // TRAIL PATCH
    };

    CCursorPassElement(const SRenderData& data);
    virtual ~CCursorPassElement() = default;

    virtual std::vector<UP<IPassElement>> draw(Render::CRenderContext& ctx);
    virtual bool                          needsLiveBlur(Render::CRenderContext& ctx);
    virtual bool                          needsPrecomputeBlur(Render::CRenderContext& ctx);
    virtual std::optional<CBox>           boundingBox(Render::CRenderContext& ctx);
    virtual CRegion                       opaqueRegion(Render::CRenderContext& ctx);
    virtual void                          discard(Render::CRenderContext& ctx);

    virtual const char* passName() {
        return "CCursorPassElement";
    }

    virtual ePassElementType type() {
        return EK_CUSTOM;
    };

  private:
    SRenderData m_data;
};
