#version 440

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 dir;      // shutter travel along the motion, in uv units (full length of the smear)
    vec2 zoom;     // scale change over the exposure per axis (0.1 = grows 10%)
    vec2 anchor;   // the point the element scales around, in uv
    vec4 uvRect;   // the part of the source this quad shows: x, y, w, h in uv (the quad is cropped to what the smear can reach)
};

layout(binding = 1) uniform sampler2D source;
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

const int TAPS = 25;

// Real motion blur: the picture is averaged over the positions the element passed through while the
// shutter was open (translation along `dir`, scaling around `anchor`), not a faded copy of it.
void main()
{
    vec2 uv = uvRect.xy + qt_TexCoord0 * uvRect.zw;
    vec4 sum = vec4(0.0);
    float wsum = 0.0;
    for (int i = 0; i < TAPS; i++) {
        float t = float(i) / float(TAPS - 1) - 0.5;
        // the pixel at uv now came from here at time t of the exposure
        vec2 p = uv - dir * t - (uv - anchor) * zoom * t;
        float inside = (p.x >= 0.0 && p.x <= 1.0 && p.y >= 0.0 && p.y <= 1.0) ? 1.0 : 0.0;
        // triangular weights: the middle of the exposure counts more, so the smear has soft ends
        float w = 1.0 - abs(t) * 1.4;
        sum += texture(source, clamp(p, vec2(0.0), vec2(1.0))) * inside * w;
        wsum += w;
    }
    fragColor = (sum / wsum) * qt_Opacity;
}
