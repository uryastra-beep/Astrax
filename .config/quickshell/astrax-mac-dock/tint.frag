#version 440

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec4 tint;
    float tintOn;
    float gray;
};

layout(binding = 1) uniform sampler2D source;
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

// iOS "tinted" look: icon luminance mapped from a dark tile of the tint colour up to the tint itself.
void main()
{
    vec4 c = texture(source, qt_TexCoord0);
    float a = c.a;
    vec3 rgb = a > 0.0 ? c.rgb / a : vec3(0.0);
    float l = dot(rgb, vec3(0.299, 0.587, 0.114));
    float t = clamp(pow(l, 0.75) * 1.3, 0.0, 1.0);
    vec3 dark = tint.rgb * 0.26;
    vec3 col = mix(rgb, mix(dark, tint.rgb, t), tintOn);
    col = mix(col, vec3(dot(col, vec3(0.299, 0.587, 0.114))), gray);
    fragColor = vec4(col * a, a) * qt_Opacity;
}
