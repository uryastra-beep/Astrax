#version 440
layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;
layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float time;
    float aspect;
    vec4 k0; vec4 k1; vec4 k2; vec4 k3; vec4 k4; vec4 k5; vec4 k6; // colors (a = weight)
};

float blob(vec2 p, vec2 c, float r) {
    vec2 d = p - c;
    return (r * r) / (dot(d, d) + 0.002);
}

void main() {
    vec2 uv = qt_TexCoord0;
    vec2 p = vec2(uv.x * aspect, uv.y);
    float t = time;
    float A = aspect;
    p += 0.05 * vec2(sin(p.y * 3.1 + t * 0.35), cos(p.x * 2.7 - t * 0.30));

    vec4 K[7] = vec4[7](k0, k1, k2, k3, k4, k5, k6);

    // no background color: the bubbles ARE the background (weighted average of all)
    vec3 acc = vec3(0.0);
    float sum = 1e-4;

    for (int i = 0; i < 16; i++) {
        float fi = float(i);
        vec4 col_i = K[i % 7];
        vec2 c = vec2(A * (0.5 + 0.44 * sin(t * (0.06 + 0.009 * fi) + fi * 2.3)),
                      0.5 + 0.42 * cos(t * (0.08 + 0.008 * fi) + fi * 1.7));
        float r = 0.26 + 0.24 * sqrt(clamp(col_i.a, 0.0, 1.0));
        float f = blob(p, c, r);
        float w = f * f;
        acc += col_i.rgb * w;
        sum += w;
    }
    vec3 col = acc / sum;                // weighted average: faithful colors, never blown out to white

    float n = fract(sin(dot(uv * 1000.0, vec2(12.9898, 78.233))) * 43758.5453);
    col += (n - 0.5) * 0.01;
    fragColor = vec4(col, 1.0) * qt_Opacity;
}
