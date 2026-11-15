#version 440
// iPhone-style digit change: the new digit is revealed from BOTTOM to TOP with a very soft edge.
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float progress;   // 0..1
    float band;       // height of the gradient (fraction of the digit)
};
layout(binding = 1) uniform sampler2D source;
void main()
{
    float h = 1.0 - qt_TexCoord0.y;                       // 0 abajo, 1 arriba
    float a = clamp((progress * (1.0 + band) - h) / band, 0.0, 1.0);
    vec4 c = texture(source, qt_TexCoord0);
    fragColor = c * a * qt_Opacity;
}
