#version 440

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float strength;
    float band;
    float hasBackdrop;
    float vignette;
    float outline;
    vec2 size;
    vec2 origin;
    vec2 screen;
    vec4 tint;
};

layout(binding = 1) uniform sampler2D src;      // screen capture (backdrop)
layout(binding = 2) uniform sampler2D maskTex;  // digit shape (alpha)

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

const int DIRS = 16;
const int STEPS = 10;

float maskAt(vec2 uv)
{
    // outside the item = outside the glyph (or an edge touching the limit looks "cut")
    if (uv.x < 0.0 || uv.y < 0.0 || uv.x > 1.0 || uv.y > 1.0) return 0.0;
    return texture(maskTex, uv).a;
}

vec3 backdrop(vec2 localPoint)
{
    if (hasBackdrop < 0.5) return vec3(0.16, 0.10, 0.28);
    vec2 pixel = origin + localPoint;
    vec2 uv = clamp(pixel / max(screen, vec2(1.0)), vec2(0.0), vec2(1.0));
    vec2 d = vec2(1.5) / max(screen, vec2(1.0));
    vec3 c = texture(src, uv).rgb * 0.4;
    c += texture(src, clamp(uv + d, vec2(0.0), vec2(1.0))).rgb * 0.15;
    c += texture(src, clamp(uv - d, vec2(0.0), vec2(1.0))).rgb * 0.15;
    c += texture(src, clamp(uv + vec2(d.x, -d.y), vec2(0.0), vec2(1.0))).rgb * 0.15;
    c += texture(src, clamp(uv + vec2(-d.x, d.y), vec2(0.0), vec2(1.0))).rgb * 0.15;
    return c;
}

void main()
{
    vec2 uv = qt_TexCoord0;
    vec2 p = uv * size;
    vec2 px = 1.0 / max(size, vec2(1.0));
    float cov = maskAt(uv);
    if (cov < 0.004) { fragColor = vec4(0.0); return; }

    float bevel = max(2.0, band);

    // distance to the edge (px): first radius where any ray leaves the glyph
    float depth = bevel;
    for (int s = 1; s <= STEPS; ++s) {
        float r = float(s) * bevel / float(STEPS);
        float hit = 0.0;
        for (int i = 0; i < DIRS; ++i) {
            float a = 6.2831853 * float(i) / float(DIRS);
            vec2 o = vec2(cos(a), sin(a));
            hit = max(hit, 1.0 - step(0.3, maskAt(uv + o * r * px)));
        }
        if (hit > 0.5) { depth = max(r - 0.5 * bevel / float(STEPS), 0.0); break; }
    }

    // outward normal: toward where there is NO glyph, at a small radius
    vec2 n = vec2(0.0);
    if (depth < bevel) {
        float rho = depth + 2.0;
        for (int i = 0; i < DIRS; ++i) {
            float a = 6.2831853 * float(i) / float(DIRS);
            vec2 o = vec2(cos(a), sin(a));
            n += o * (1.0 - maskAt(uv + o * rho * px));
        }
        n = (length(n) > 0.001) ? normalize(n) : vec2(0.0, -1.0);
    }

    float u = clamp(depth / bevel, 0.0, 1.0);
    float bevelMask = 1.0 - smoothstep(0.4, 1.0, u);

    // ---- interior: almost transparent glass with a soft tint ----
    vec3 base = backdrop(p);
    vec3 interior = mix(base, vec3(1.0), 0.07);
    interior = mix(interior, tint.rgb, 0.16 * smoothstep(0.0, 1.0, uv.y));
    interior += vec3(0.10) * pow(1.0 - uv.y, 2.0);   // soft highlight at the top

    // ---- edge: island-style refraction ----
    vec3 col = interior;
    float edgeAlpha = mix(0.55, 0.9, strength);
    if (depth < bevel) {
        vec2 tangent = vec2(-n.y, n.x);
        float slope = (1.0 - u) / max(sqrt(max(1.0 - (1.0 - u) * (1.0 - u), 0.0)), 0.18);
        vec3 surfaceNormal = normalize(vec3(-n * slope, 1.0));
        vec3 ray = refract(vec3(0.0, 0.0, -1.0), surfaceNormal, 0.6849315);
        float travel = length(ray.xy) / max(abs(ray.z), 0.2);
        float edgeProfile = pow(1.0 - u, 0.62);
        float thickness = mix(6.0, 44.0, strength);
        float bend = travel * thickness * edgeProfile;
        vec2 refracted = p + n * (depth + 3.0 + bend);

        float dispersion = strength * 1.05 * edgeProfile;
        float scatter = mix(0.4, 1.25, u);
        vec3 centerSample = backdrop(refracted);
        vec3 softSample = (backdrop(refracted + tangent * scatter) + backdrop(refracted - tangent * scatter)) * 0.5;
        vec3 e = mix(centerSample, softSample, 0.28);
        e.r = mix(e.r, backdrop(refracted + n * dispersion).r, 0.65);
        e.b = mix(e.b, backdrop(refracted - n * dispersion).b, 0.65);

        float facing = dot(n, vec2(-0.6, -0.8));
        float fresnel = 0.04 + 0.96 * pow(1.0 - surfaceNormal.z, 5.0);
        float rim = exp(-depth / 1.35);
        float glint = pow(max(facing, 0.0), 5.0) * 0.34 + pow(max(-facing, 0.0), 7.0) * 0.12;
        float innerLip = exp(-pow((depth - 2.5) / 1.2, 2.0));
        float caustic = exp(-pow((depth - bevel * 0.44) / (bevel * 0.24 + 0.1), 2.0));
        e *= 1.0 - innerLip * 0.055 * strength;
        e += vec3(0.94, 0.97, 1.0) * (rim * (0.035 + glint) + fresnel * 0.08
             + innerLip * glint * 0.2 + caustic * max(-facing, 0.0) * strength * 0.045);
        col = mix(interior, clamp(e, vec3(0.0), vec3(1.0)), bevelMask);
    }
    float alpha = cov * mix(0.30, edgeAlpha, bevelMask);
    // inner white vignette: light that fades from the edge inwards
    float v = pow(1.0 - u, 1.6) * vignette;
    col = mix(col, vec3(1.0), v * 0.6);
    alpha = max(alpha, cov * v * 0.7);
    // very thin white outline (sub-pixel): only the antialiasing band of the edge
    float line = pow(clamp(4.0 * cov * (1.0 - cov), 0.0, 1.0), 0.7);
    col = mix(col, vec3(1.0), line * outline);
    alpha = max(alpha, cov * line * outline);
    fragColor = vec4(clamp(col, vec3(0.0), vec3(1.0)) * alpha, alpha) * qt_Opacity;
}
