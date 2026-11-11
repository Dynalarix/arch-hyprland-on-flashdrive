#version 300 es
// Retro CRT screen shader for Hyprland (decoration:screen_shader).
// Tweak the constants below, then run `hyprctl reload` to see the change.
precision highp float;

in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

const float SCANLINES   = 0.22;   // darkness of the gaps between lines (0 = off)
const float LINE_PERIOD = 3.0;    // screen pixels per scanline
const float MASK        = 0.10;   // RGB phosphor stripe strength (0 = off)
const float ABERRATION  = 0.0012; // red/blue colour fringing toward the edges
const float VIGNETTE    = 0.5;    // darker corners and edges (0 = off, 1 = strong)
const float GLOW        = 1.12;   // overall brightness boost to make up for the lines
const float TINT        = 0.0;    // 0 = keep colours, 1 = full green phosphor monochrome
const vec3  PHOSPHOR    = vec3(0.20, 1.00, 0.40); // tint colour (amber: 1.0, 0.70, 0.20)
const float CURVE       = 0.0;    // screen bulge; >0 looks great but makes clicks near the
                                  // edges land slightly off from the pointer

void main() {
    vec2 uv = v_texcoord;
    vec2 size = vec2(textureSize(tex, 0));

    if (CURVE > 0.0) {
        vec2 c = uv * 2.0 - 1.0;
        c *= 1.0 + CURVE * dot(c.yx, c.yx);
        uv = c * 0.5 + 0.5;
        if (uv.x < 0.0 || uv.x > 1.0 || uv.y < 0.0 || uv.y > 1.0) {
            fragColor = vec4(0.0, 0.0, 0.0, 1.0);
            return;
        }
    }

    // Colour fringing: red and blue sampled slightly apart, more at the edges.
    vec2 off = (uv - 0.5) * ABERRATION;
    vec3 col;
    col.r = texture(tex, uv + off).r;
    col.g = texture(tex, uv).g;
    col.b = texture(tex, uv - off).b;

    // Horizontal scanlines.
    float y = uv.y * size.y;
    float line = 0.5 + 0.5 * cos(y * 6.2831853 / LINE_PERIOD);
    col *= 1.0 - SCANLINES * (1.0 - line);

    // Vertical RGB phosphor stripes (aperture grille).
    int stripe = int(mod(floor(uv.x * size.x), 3.0));
    vec3 mask = vec3(1.0 - MASK);
    mask[stripe] = 1.0 + MASK;
    col *= mask;

    // Monochrome phosphor tint.
    float lum = dot(col, vec3(0.299, 0.587, 0.114));
    col = mix(col, lum * PHOSPHOR * 1.4, TINT);

    // Vignette.
    float v = 16.0 * uv.x * uv.y * (1.0 - uv.x) * (1.0 - uv.y);
    col *= mix(1.0, pow(v, 0.25), VIGNETTE);

    fragColor = vec4(clamp(col * GLOW, 0.0, 1.0), 1.0);
}
