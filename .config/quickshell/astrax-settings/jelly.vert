#version 440

layout(location = 0) in vec4 qt_Vertex;
layout(location = 1) in vec2 qt_MultiTexCoord0;
layout(location = 0) out vec2 qt_TexCoord0;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    vec2 grab;      // point being dragged (item pixels): it follows the pointer 1:1
    vec2 lag;       // how far the window trails behind the pointer (pixels)
    float reach;    // distance at which a point lags by the full amount
    float squash;   // extra stretch along the motion, 0 = none
    vec4 gbox;      // genie: the window inside this item (x, y, w, h)
    vec2 gtarget;   // genie: dock icon (item pixels)
    float gp;       // genie progress: 0 = window as is, 1 = collapsed into the icon
};

float sm(float t) { t = clamp(t, 0.0, 1.0); return t * t * (3.0 - 2.0 * t); }
float ease3(float t) { t = clamp(t, 0.0, 1.0); return t < 0.5 ? 4.0 * t * t * t : 1.0 - pow(-2.0 * t + 2.0, 3.0) / 2.0; }

// same maths as the Hyprland genie plugin (meshPoint), so apps and Settings collapse alike
vec2 genie(vec2 pos)
{
    float u = clamp((pos.x - gbox.x) / gbox.z, 0.0, 1.0);
    float v = clamp((pos.y - gbox.y) / gbox.w, 0.0, 1.0);
    vec2 T = gtarget;
    float bx = gbox.x, by = gbox.y, bw = gbox.z, bh = gbox.w;
    float p = gp;
    float bottom = by + bh;
    float ptop = ease3((p - 0.32) / 0.68);
    float pbot = ease3(p / 0.52);
    float yTop = by + (T.y - by) * ptop;
    float yBot = bottom + (T.y - bottom) * pbot;
    float y = yTop + (yBot - yTop) * v;
    float dist = T.y - by;
    float q = abs(dist) < 1.0 ? 1.0 : clamp((y - by) / dist, 0.0, 1.0);
    float g = sm(p / 0.60);
    float sq = sm(q);
    float NEAR = pow(sq, 1.9);
    float FAR = pow(sq, 0.55);
    bool targetLeft = T.x < bx + bw / 2.0;
    float SL = targetLeft ? NEAR : FAR;
    float SR = targetLeft ? FAR : NEAR;
    float neck = sm(p / 0.55) * pow(v, 3.0);
    float xl = bx + (T.x - bx) * min(1.0, max(g * SL, neck));
    float xr = (bx + bw) + (T.x - (bx + bw)) * min(1.0, max(g * SR, neck));
    float k = sm((p - 0.88) / 0.12);
    xl += (T.x - xl) * k;
    xr += (T.x - xr) * k;
    return vec2(xl + (xr - xl) * u, y);
}

void main()
{
    qt_TexCoord0 = qt_MultiTexCoord0;
    vec2 p = qt_Vertex.xy;
    if (gp > 0.0005) p = genie(p);
    float d = clamp(distance(p, grab) / max(reach, 1.0), 0.0, 1.0);
    float w = d * d * (3.0 - 2.0 * d);          // smoothstep: near the hand moves with it, far parts drag behind
    w = mix(w, w * w, 0.35);                    // keep the area around the hand firm
    vec2 shift = -lag * w;
    // far points also stretch a little against the motion so the body feels soft, not just sheared
    shift -= lag * squash * w * (d - 0.5);
    gl_Position = qt_Matrix * vec4(p + shift, 0.0, 1.0);
}
