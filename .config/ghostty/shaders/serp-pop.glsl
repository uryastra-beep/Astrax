// serp-pop: mimics the letter "pop" of the Serpantinum inputs.
// Every time the cursor moves (type/delete) a flash of the cursor color
// appears on the cell, starting big and shrinking to its size
// (scale 1.7 -> 1.0) while fading out, with a soft bounce.
// Ghostty uniforms: iCurrentCursor (xy = top-left corner, zw = size),
// iTimeCursorChange, iCurrentCursorColor.

const float DURATION = 0.26;

float sdBox(vec2 p, vec2 b, float r) {
    vec2 d = abs(p) - b + r;
    return length(max(d, 0.0)) + min(max(d.x, d.y), 0.0) - r;
}

float easeOutBack(float x) {
    float c1 = 1.70158, c3 = c1 + 1.0;
    return 1.0 + c3 * pow(x - 1.0, 3.0) + c1 * pow(x - 1.0, 2.0);
}

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    fragColor = texture(iChannel0, uv);

    float t = clamp((iTime - iTimeCursorChange) / DURATION, 0.0, 1.0);
    if (t >= 1.0) return;

    // centre of the cursor cell (Ghostty coordinates: y goes up)
    vec2 size = iCurrentCursor.zw;
    vec2 center = vec2(iCurrentCursor.x + size.x * 0.5, iCurrentCursor.y - size.y * 0.5);
    // the letter "jumps": big scale -> 1 with a little bounce
    float scale = mix(1.7, 1.0, easeOutBack(t));
    vec2 half_ = vec2(max(size.x, size.y * 0.55), size.y) * 0.5 * scale;
    float d = sdBox(fragCoord - center, half_, min(half_.x, half_.y) * 0.45);

    float fade = 1.0 - t;
    float ring = smoothstep(2.2, 0.0, abs(d)) * 0.85;      // borde
    float fill = smoothstep(1.0, -1.0, d) * 0.18;          // relleno tenue
    float a = (ring + fill) * fade * fade;
    fragColor.rgb = mix(fragColor.rgb, iCurrentCursorColor.rgb, clamp(a, 0.0, 1.0));
}
