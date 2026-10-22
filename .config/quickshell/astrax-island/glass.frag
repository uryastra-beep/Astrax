#version 440
// Liquid Glass refraction for the island: a lens at the rim of the pill that
// bends the screen behind it (edge band only, sampled from OUTSIDE the pill so
// the island never sees itself), with a little chromatic dispersion and a
// specular rim. The interior is left to the translucent fill + compositor blur.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float radius;      // corner radius, px
    float strength;    // 0..1 how hard the rim bends
    float band;        // width of the lens band, px
    vec2 size;         // pill size, px
    vec2 origin;       // pill top-left on the screen, px
    vec2 screen;       // screen size, px
};
layout(binding = 1) uniform sampler2D src;

void main() {
    vec2 p = qt_TexCoord0 * size;
    vec2 c = size * 0.5;
    vec2 q = abs(p - c) - (c - vec2(radius));
    float d = length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - radius;   // < 0 inside
    vec2 n;
    if (q.x > 0.0 || q.y > 0.0) n = normalize(max(q, vec2(0.0)));
    else n = (q.x > q.y) ? vec2(1.0, 0.0) : vec2(0.0, 1.0);
    n *= sign(p - c + vec2(1e-4));

    float depth = max(-d, 0.0);
    float t = clamp(1.0 - depth / band, 0.0, 1.0);
    float lens = t * t * (3.0 - 2.0 * t);              // smooth, strongest at the rim

    // mirror the point across the rim: content from just outside the pill gets
    // pulled in, flipped, like looking through a thick curved edge
    float m = (depth * 2.0 + 2.0) * mix(0.6, 1.6, strength);
    vec3 col;
    for (int i = 0; i < 3; ++i) {
        float disp = 1.0 + (float(i) - 1.0) * 0.07 * strength;     // R, G, B bend a bit differently
        vec2 pos = (origin + p + n * m * disp) / screen;
        col[i] = texture(src, clamp(pos, vec2(0.0), vec2(1.0)))[i];
    }
    col *= 1.12;

    // specular rim, lit from the top-left, plus a faint inner glow
    float facing = max(dot(n, normalize(vec2(-0.55, -0.85))), 0.0);
    float rim = smoothstep(0.0, 1.0, 1.0 - depth / 2.5) ;
    col += vec3(1.0) * (rim * (0.12 + 0.55 * facing));
    col += vec3(1.0) * lens * 0.05;

    float inside = 1.0 - smoothstep(-0.75, 0.75, d);      // clip to the rounded shape
    float a = lens * (0.7 + 0.3 * strength) * inside;
    fragColor = vec4(col * a, a) * qt_Opacity;
}
