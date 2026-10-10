#version 300 es
// TV Girl mode: recolors ONLY the pixels that are (almost) exactly the
// theme's fuchsia accents, based on their X position on each monitor:
// left = blue, right = fuchsia, with a soft fade in the middle.
// Doesn't touch the wallpaper or anything that isn't the exact theme color.
precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
layout(location = 0) out vec4 fragColor;

const vec3 FUCHSIA  = vec3(1.0, 0.2471, 0.8157);   // #ff3fd0 (mauve)
const vec3 BLUE     = vec3(0.2392, 0.5451, 1.0);   // #3d8bff
const vec3 FUCHSIA2 = vec3(1.0, 0.4784, 0.8784);   // #ff7ae0 (light peach)
const vec3 BLUE2    = vec3(0.3529, 0.6275, 1.0);   // #5aa0ff

void main() {
    vec4 c = texture(tex, v_texcoord);
    float t = smoothstep(0.30, 0.70, v_texcoord.x);   // 0 = left (blue), 1 = right (fuchsia)

    float m1 = 1.0 - smoothstep(0.05, 0.20, distance(c.rgb, FUCHSIA));
    float m2 = 1.0 - smoothstep(0.05, 0.18, distance(c.rgb, FUCHSIA2));

    vec3 shift1 = (mix(BLUE,  FUCHSIA,  t) - FUCHSIA)  * m1;
    vec3 shift2 = (mix(BLUE2, FUCHSIA2, t) - FUCHSIA2) * m2;
    fragColor = vec4(clamp(c.rgb + shift1 + shift2, 0.0, 1.0), c.a);
}
