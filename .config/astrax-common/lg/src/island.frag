#version 440

// --- global Liquid Glass settings (written by lg-apply from Settings > Liquid Glass) ---
const float LG_REFR = 1.0;
const float LG_CHROMA = 1.0;
const float LG_BLUR = 3.0;
const float LG_SAT = 1.22;
const float LG_LENS = 1.0;
const float LG_SPEC = 1.0;

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
};

layout(binding = 1) uniform sampler2D src;

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

float roundedDistance(vec2 point, vec2 halfSize, float r)
{
    vec2 q = abs(point - halfSize) - (halfSize - vec2(r));
    return (length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0)) - r;
}

vec2 outwardAt(vec2 point, vec2 halfSize, float r)
{
    vec2 q = abs(point - halfSize) - (halfSize - vec2(r));
    vec2 outside = max(q, vec2(0.0));
    vec2 _122;
    if (length(outside) > 9.9999997473787516355514526367188e-05)
    {
        _122 = normalize(outside);
    }
    else
    {
        bvec2 _136 = bvec2(q.x > q.y);
        _122 = vec2(_136.x ? vec2(1.0, 0.0).x : vec2(0.0, 1.0).x, _136.y ? vec2(1.0, 0.0).y : vec2(0.0, 1.0).y);
    }
    vec2 n = _122;
    return n * sign((point - halfSize) + vec2(9.9999997473787516355514526367188e-05));
}

vec3 backdrop(vec2 localPoint)
{
    vec2 center = size * 0.5;
    vec2 pixel = (origin + center) + ((localPoint - center) * stretch);
    vec2 uv = pixel / max(screen, vec2(1.0));
    // A restrained 1.5-logical-pixel blur, applied only to refracted background.
    vec2 d1 = vec2(LG_BLUR) / max(screen, vec2(1.0));
    vec2 uvc = clamp(uv, vec2(0.0), vec2(1.0));
    vec3 softened = texture(src, uvc).rgb * 0.24;
    for (int i = 0; i < 8; i++)
    {
        float a = 0.7853982 * float(i);
        vec2 o = vec2(cos(a), sin(a)) * d1 * ((i & 1) == 0 ? 1.0 : 0.6);
        softened += texture(src, clamp(uv + o, vec2(0.0), vec2(1.0))).rgb * 0.095;
    }
    // iOS 26 look: slightly more vivid and a touch brighter behind the glass
    float l = dot(softened, vec3(0.299, 0.587, 0.114));
    softened = mix(vec3(l), softened, LG_SAT) * 1.04;
    return softened;
}

void main()
{
    vec2 p = qt_TexCoord0 * size;
    vec2 halfSize = size * 0.5;
    float r = min(radius, min(halfSize.x, halfSize.y));
    vec2 signedPoint = p - halfSize;
    vec2 q = abs(signedPoint) - (halfSize - vec2(r));
    vec2 outer = max(q, vec2(0.0));
    float d = (length(outer) + min(max(q.x, q.y), 0.0)) - r;
    vec2 n;
    if (length(outer) > 9.9999997473787516355514526367188e-05)
    {
        n = normalize(outer);
    }
    else
    {
        bvec2 _212 = bvec2(q.x > q.y);
        n = vec2(_212.x ? vec2(1.0, 0.0).x : vec2(0.0, 1.0).x, _212.y ? vec2(1.0, 0.0).y : vec2(0.0, 1.0).y);
    }
    n *= sign(signedPoint + vec2(9.9999997473787516355514526367188e-05));
    vec2 tangent = vec2(-n.y, n.x);
    float depth = max(-d, 0.0);
    float bevel = max(1.0, min(min(halfSize.x, halfSize.y), 36.0));   // the glass covers the whole panel
    if (d > 0.75)
    {
        fragColor = vec4(0.0);
        return;
    }
    float u = clamp(depth / bevel, 0.0, 1.0);
    float coverage = 1.0 - smoothstep(-0.64999997615814208984375, 0.64999997615814208984375, d);
    float bevelMask = 1.0 - 0.3 * smoothstep(0.55, 1.0, u);
    float slope = (1.0 - u) / max(sqrt(max(1.0 - ((1.0 - u) * (1.0 - u)), 0.0)), 0.180000007152557373046875);
    vec3 surfaceNormal = normalize(vec3((-n) * slope, 1.0));
    vec3 ray = refract(vec3(0.0, 0.0, -1.0), surfaceNormal, 0.6849315166473388671875);
    float travel = length(ray.xy) / max(abs(ray.z), 0.20000000298023223876953125);
    float edgeProfile = pow(1.0 - u, 0.62000000476837158203125);
    float corner = smoothstep(0.0199999995529651641845703125, 0.449999988079071044921875, abs(n.x * n.y));
    float thickness = mix(12.0, 66.0, strength) * LG_REFR * (1.0 + (corner * 0.23999999463558197021484375));
    float bend = (travel * thickness) * edgeProfile;
    vec2 edgePoint = p + (n * depth);
    float tangentCoordinate = dot(edgePoint - halfSize, tangent);
    float tangentWarp = (((-tangentCoordinate) * strength) * edgeProfile) * (0.054999999701976776123046875 + (0.085000000894069671630859375 * corner));
    vec2 edgeRef = (p + (n * ((min(depth, bevel) + 3.0) + bend))) + (tangent * tangentWarp);
    vec2 refracted = mix(p, edgeRef, 1.0 - smoothstep(0.6 * bevel, bevel, depth));
    vec2 param = refracted;
    vec2 param_1 = halfSize;
    float param_2 = r;
    float clearance = roundedDistance(param, param_1, param_2);
    if (clearance < 3.0)
    {
        vec2 param_3 = refracted;
        vec2 param_4 = halfSize;
        float param_5 = r;
        refracted += (outwardAt(param_3, param_4, param_5) * (3.0 - clearance));
    }
    float cy = (p.y - halfSize.y) / max(halfSize.y, 1.0);   // -1 arriba .. +1 abajo, continuo
    refracted += (halfSize - p) / max(halfSize, vec2(1.0)) * vec2(2.0, 12.0) * strength * LG_LENS;
    float dispersion = ((1.6 + strength * 6.0) * pow(1.0 - u, 0.45) + 0.4) * LG_CHROMA;
    float scatter = mix(0.4000000059604644775390625, 1.25, u);
    vec2 param_6 = refracted;
    vec3 centerSample = backdrop(param_6);
    vec2 param_7 = refracted + (tangent * scatter);
    vec2 param_8 = refracted - (tangent * scatter);
    vec3 softSample = (backdrop(param_7) + backdrop(param_8)) * 0.5;
    vec3 col = mix(centerSample, softSample, vec3(0.2800000011920928955078125));
    vec2 param_9 = refracted + (n * dispersion) + vec2(0.0, cy * (1.5 + 5.0 * strength) * LG_CHROMA);
    col.x = backdrop(param_9).x;
    vec2 param_10 = refracted - (n * dispersion) - vec2(0.0, cy * (1.5 + 5.0 * strength) * LG_CHROMA);
    col.z = backdrop(param_10).z;
    float facing = dot(n, vec2(-0.60000002384185791015625, -0.800000011920928955078125));
    float fresnel = 0.039999999105930328369140625 + (0.959999978542327880859375 * pow(1.0 - surfaceNormal.z, 5.0));
    float rim = exp((-depth) / 1.1);
    float line = exp(-pow((depth - 0.9) / 0.55, 2.0));
    float glint = (pow(max(facing, 0.0), 3.5) * 0.4600000035762786865234375) + (pow(max(-facing, 0.0), 7.0) * 0.119999997317790985107421875);
    float innerLip = exp(-pow((depth - 2.5) / 1.2000000476837158203125, 2.0));
    float caustic = exp(-pow((depth - (bevel * 0.439999997615814208984375)) / ((bevel * 0.23999999463558197021484375) + 0.100000001490116119384765625), 2.0));
    col *= (1.0 - ((innerLip * 0.054999999701976776123046875) * strength));
    col += vec3(1.0) * (LG_SPEC * line * (0.05 + 0.34 * pow(max(facing, 0.0), 2.0) + 0.16 * pow(max(-facing, 0.0), 2.5)));
    col += (vec3(0.939999997615814208984375, 0.9700000286102294921875, 1.0) * ((((rim * (0.0350000001490116119384765625 + glint)) + (fresnel * 0.07999999821186065673828125)) + ((innerLip * glint) * 0.20000000298023223876953125)) + (((caustic * max(-facing, 0.0)) * strength) * 0.04500000178813934326171875)));
    float alpha = (coverage * bevelMask) * mix(0.550000011920928955078125, 0.89999997615814208984375, strength);
    fragColor = vec4(clamp(col, vec3(0.0), vec3(1.0)) * alpha, alpha) * qt_Opacity;
}

