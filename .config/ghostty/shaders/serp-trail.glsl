// serp-trail: cursor trail like kitty's (cursor_trail). When the cursor
// moves, a cell-shaped "smear" joins the previous position with the new
// one and pulls back towards the cursor while fading out.

const float DURATION = 0.32;

// distance to a thick segment (capsule) between a and b
float sdSegment(vec2 p, vec2 a, vec2 b, float r) {
    vec2 pa = p - a, ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-4), 0.0, 1.0);
    return length(pa - ba * h) - r;
}

float easeOutCubic(float x) { return 1.0 - pow(1.0 - x, 3.0); }

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord / iResolution.xy;
    fragColor = texture(iChannel0, uv);

    float t = clamp((iTime - iTimeCursorChange) / DURATION, 0.0, 1.0);
    if (t >= 1.0) return;

    vec2 sizeC = iCurrentCursor.zw;
    vec2 sizeP = iPreviousCursor.zw;
    vec2 cur  = vec2(iCurrentCursor.x + sizeC.x * 0.5, iCurrentCursor.y - sizeC.y * 0.5);
    vec2 prev = vec2(iPreviousCursor.x + sizeP.x * 0.5, iPreviousCursor.y - sizeP.y * 0.5);
    // 1-cell moves (normal typing) don't leave a long trail
    if (distance(cur, prev) < sizeC.x * 1.5) return;

    // the tail runs towards the cursor
    vec2 tail = mix(prev, cur, t * t * (3.0 - 2.0 * t));
    float r = sizeC.y * 0.42;
    float d = sdSegment(fragCoord, tail, cur, r);

    float a = smoothstep(1.5, -1.5, d) * (1.0 - t) * 0.55;
    fragColor.rgb = mix(fragColor.rgb, iCurrentCursorColor.rgb, a);
}
