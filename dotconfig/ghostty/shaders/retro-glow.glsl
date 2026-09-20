// Retro Terminal Glow & CRT Shader for Ghostty
// Recreates the classic Windows Terminal retro font glow effect.

// --- Tunable Parameters ---
#define GLOW_INTENSITY 0.75      // Strength of the glow (0.0 to 2.0)
#define GLOW_RADIUS 2.5         // Glow spread radius in pixels (1.0 to 6.0)
#define SCANLINE_INTENSITY 0.12  // Scanline darkness (0.0 for pure glow, 0.1-0.3 for CRT look)
#define VIGNETTE_INTENSITY 0.05  // Subtle edge darkening (0.0 to 0.3)

void mainImage(out vec4 fragColor, in vec2 fragCoord) {
    vec2 uv = fragCoord.xy / iResolution.xy;
    vec2 pixelSize = 1.0 / iResolution.xy;

    // Sample original terminal character
    vec4 baseColor = texture(iChannel0, uv);

    // Multi-tap Gaussian-style bloom kernel for smooth phosphor glow
    vec4 bloom = vec4(0.0);
    float totalWeight = 0.0;

    for (float x = -2.0; x <= 2.0; x += 1.0) {
        for (float y = -2.0; y <= 2.0; y += 1.0) {
            float dist = length(vec2(x, y));
            float weight = exp(-0.5 * (dist * dist) / 1.5);
            vec2 offset = vec2(x, y) * pixelSize * GLOW_RADIUS;
            bloom += texture(iChannel0, uv + offset) * weight;
            totalWeight += weight;
        }
    }
    bloom /= totalWeight;

    // Combine sharp base character with glowing aura
    vec4 finalColor = baseColor + (bloom * GLOW_INTENSITY);

    // Subtle scanlines
    if (SCANLINE_INTENSITY > 0.0) {
        float scanline = sin(fragCoord.y * 1.5) * 0.5 + 0.5;
        finalColor.rgb *= (1.0 - SCANLINE_INTENSITY * (1.0 - scanline));
    }

    // Subtle vignette
    if (VIGNETTE_INTENSITY > 0.0) {
        vec2 vigUv = (uv - 0.5) * 2.0;
        float vig = 1.0 - dot(vigUv, vigUv) * VIGNETTE_INTENSITY;
        finalColor.rgb *= clamp(vig, 0.0, 1.0);
    }

    fragColor = clamp(finalColor, 0.0, 1.0);
}
