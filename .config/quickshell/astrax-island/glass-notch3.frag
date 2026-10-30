#version 440

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float radius;
    float strength;
    float band;
    vec2 size;
    vec2 origin;
    vec2 screen;
    vec2 stretch;
    float wing;
};

layout(binding = 1) uniform sampler2D src;

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

// Notch glass. The shape is one piece: a box that hangs from the screen edge (its top is extended upward
// by EXT so the top edge never gets a rim) plus two concave "shoulders" `wing` px wide on each side at the
// top, where the notch flares into the screen edge. The item is the box plus both wings: size.x = box + 2*wing.
const float EXT = 80.0;

float sdBox(vec2 p, vec2 c, vec2 hs, float r)
{
    vec2 q = abs(p - c) - (hs - vec2(r));
    return (length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0)) - r;
}

// p is in shifted coordinates (y + EXT)
float sdf(vec2 p)
{
    float W = size.x;
    float H = size.y + EXT;
    float w = max(wing, 0.0);
    vec2 hs = vec2((W - 2.0 * w) * 0.5, H * 0.5);
    float rb = min(radius, min(hs.x, hs.y));
    vec2 c = vec2(W * 0.5, H * 0.5);
    float d = sdBox(p, c, hs, (p.y > c.y) ? rb : 0.0);
    if (w > 0.5)
    {
        float yb = EXT + w;
        float dl = max(sdBox(p, vec2(w * 0.5, yb * 0.5), vec2(w * 0.5, yb * 0.5), 0.0), w - length(p - vec2(0.0, EXT + w)));
        float dr = max(sdBox(p, vec2(W - w * 0.5, yb * 0.5), vec2(w * 0.5, yb * 0.5), 0.0), w - length(p - vec2(W, EXT + w)));
        d = min(d, min(dl, dr));
    }
    return d;
}

vec2 normalAt(vec2 p)
{
    vec2 e = vec2(0.75, 0.0);
    vec2 g = vec2(sdf(p + e.xy) - sdf(p - e.xy), sdf(p + e.yx) - sdf(p - e.yx));
    return (length(g) > 0.0001) ? normalize(g) : vec2(0.0, 1.0);
}

vec3 backdrop(vec2 localPoint)
{
    localPoint -= vec2(0.0, EXT);
    vec2 center = size * 0.5;
    vec2 pixel = (origin + center) + ((localPoint - center) * stretch);
    pixel.y = abs(pixel.y);
    vec2 uv = pixel / max(screen, vec2(1.0));
    vec2 delta = vec2(1.5) / max(screen, vec2(1.0));
    vec3 softened = texture(src, clamp(uv, vec2(0.0), vec2(1.0))).rgb * 0.4;
    softened += texture(src, clamp(uv + delta, vec2(0.0), vec2(1.0))).rgb * 0.15;
    softened += texture(src, clamp(uv - delta, vec2(0.0), vec2(1.0))).rgb * 0.15;
    softened += texture(src, clamp(uv + vec2(delta.x, -delta.y), vec2(0.0), vec2(1.0))).rgb * 0.15;
    softened += texture(src, clamp(uv + vec2(-delta.x, delta.y), vec2(0.0), vec2(1.0))).rgb * 0.15;
    return softened;
}

void main()
{
    vec2 p = (qt_TexCoord0 * size) + vec2(0.0, EXT);
    vec2 halfSize = vec2(size.x * 0.5, (size.y + EXT) * 0.5);
    float d = sdf(p);
    vec2 n = normalAt(p);
    vec2 tangent = vec2(-n.y, n.x);
    float depth = max(-d, 0.0);
    float bevel = max(1.0, min(band, min(halfSize.x - wing, size.y * 0.5)));
    if ((d > 0.75) || (depth >= bevel))
    {
        fragColor = vec4(0.0);
        return;
    }
    float u = clamp(depth / bevel, 0.0, 1.0);
    float coverage = 1.0 - smoothstep(-0.64999997615814208984375, 0.64999997615814208984375, d);
    float bevelMask = 1.0 - smoothstep(0.4000000059604644775390625, 1.0, u);
    float slope = (1.0 - u) / max(sqrt(max(1.0 - ((1.0 - u) * (1.0 - u)), 0.0)), 0.180000007152557373046875);
    vec3 surfaceNormal = normalize(vec3((-n) * slope, 1.0));
    vec3 ray = refract(vec3(0.0, 0.0, -1.0), surfaceNormal, 0.6849315166473388671875);
    float travel = length(ray.xy) / max(abs(ray.z), 0.20000000298023223876953125);
    float edgeProfile = pow(1.0 - u, 0.62000000476837158203125);
    float corner = smoothstep(0.0199999995529651641845703125, 0.449999988079071044921875, abs(n.x * n.y));
    float thickness = mix(6.0, 44.0, strength) * (1.0 + (corner * 0.23999999463558197021484375));
    float bend = (travel * thickness) * edgeProfile;
    vec2 edgePoint = p + (n * depth);
    float tangentCoordinate = dot(edgePoint - halfSize, tangent);
    float tangentWarp = (((-tangentCoordinate) * strength) * edgeProfile) * (0.054999999701976776123046875 + (0.085000000894069671630859375 * corner));
    vec2 refracted = (p + (n * ((depth + 3.0) + bend))) + (tangent * tangentWarp);
    float clearance = sdf(refracted);
    if (clearance < 3.0)
    {
        refracted += normalAt(refracted) * (3.0 - clearance);
    }
    float dispersion = (strength * 1.0499999523162841796875) * edgeProfile;
    float scatter = mix(0.4000000059604644775390625, 1.25, u);
    vec2 param_6 = refracted;
    vec3 centerSample = backdrop(param_6);
    vec2 param_7 = refracted + (tangent * scatter);
    vec2 param_8 = refracted - (tangent * scatter);
    vec3 softSample = (backdrop(param_7) + backdrop(param_8)) * 0.5;
    vec3 col = mix(centerSample, softSample, vec3(0.2800000011920928955078125));
    vec2 param_9 = refracted + (n * dispersion);
    col.x = mix(col.x, backdrop(param_9).x, 0.64999997615814208984375);
    vec2 param_10 = refracted - (n * dispersion);
    col.z = mix(col.z, backdrop(param_10).z, 0.64999997615814208984375);
    float facing = dot(n, vec2(-0.60000002384185791015625, -0.800000011920928955078125));
    float fresnel = 0.039999999105930328369140625 + (0.959999978542327880859375 * pow(1.0 - surfaceNormal.z, 5.0));
    float rim = exp((-depth) / 1.35000002384185791015625);
    float glint = (pow(max(facing, 0.0), 5.0) * 0.3400000035762786865234375) + (pow(max(-facing, 0.0), 7.0) * 0.119999997317790985107421875);
    float innerLip = exp(-pow((depth - 2.5) / 1.2000000476837158203125, 2.0));
    float caustic = exp(-pow((depth - (bevel * 0.439999997615814208984375)) / ((bevel * 0.23999999463558197021484375) + 0.100000001490116119384765625), 2.0));
    col *= (1.0 - ((innerLip * 0.054999999701976776123046875) * strength));
    col += (vec3(0.939999997615814208984375, 0.9700000286102294921875, 1.0) * ((((rim * (0.0350000001490116119384765625 + glint)) + (fresnel * 0.07999999821186065673828125)) + ((innerLip * glint) * 0.20000000298023223876953125)) + (((caustic * max(-facing, 0.0)) * strength) * 0.04500000178813934326171875)));
    float alpha = (coverage * bevelMask) * mix(0.550000011920928955078125, 0.89999997615814208984375, strength);
    fragColor = vec4(clamp(col, vec3(0.0), vec3(1.0)) * alpha, alpha) * qt_Opacity;
}

