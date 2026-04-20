shader_type spatial;

// Procedural terrain splatting: sand → grass → rock based on height and slope.
// No external textures needed — colors + noise provide all variation.

uniform vec3 sand_color  : source_color = vec3(0.85, 0.76, 0.52);
uniform vec3 grass_color : source_color = vec3(0.22, 0.50, 0.15);
uniform vec3 rock_color  : source_color = vec3(0.42, 0.40, 0.36);
uniform vec3 dirt_color  : source_color = vec3(0.45, 0.32, 0.18);

uniform float beach_height : hint_range(-2.0, 8.0)  = 1.5;
uniform float grass_height : hint_range(0.0, 20.0)  = 5.5;
uniform float blend_width  : hint_range(0.1, 4.0)   = 1.2;
uniform float cliff_slope  : hint_range(0.0, 1.0)   = 0.65;
uniform float noise_scale  : hint_range(0.0, 1.0)   = 0.12;
uniform float detail_scale : hint_range(0.1, 20.0)  = 3.0;

varying float v_height;
varying vec3  v_normal_world;
varying vec3  v_pos_world;

// ---- noise (procedural color variation) ------------------------------------
float hash(vec2 p) { return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453); }
float vnoise(vec2 p) {
    vec2 i = floor(p); vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1, 0)), f.x),
               mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), f.x), f.y);
}
float fbm3(vec2 p) {
    return vnoise(p) * 0.55 + vnoise(p * 2.1) * 0.30 + vnoise(p * 4.3) * 0.15;
}

void vertex() {
    v_height       = VERTEX.y;
    v_normal_world = (MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz;
    v_pos_world    = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
    vec2 uv = v_pos_world.xz * detail_scale;

    // Noise-based color variation per biome
    float n1 = fbm3(uv * 0.8);
    float n2 = fbm3(uv * 1.3 + 42.0);

    vec3 sand  = sand_color  + (n1 - 0.5) * noise_scale;
    vec3 grass = grass_color + (n2 - 0.5) * noise_scale;
    vec3 dirt  = dirt_color  + (n1 - 0.5) * noise_scale * 0.7;
    vec3 rock  = rock_color  + (n2 - 0.5) * noise_scale * 0.5;

    // Mix dirt into grass for patches
    float dirt_blend = smoothstep(0.35, 0.55, fbm3(uv * 0.4 + 7.0));
    vec3 ground = mix(grass, dirt, dirt_blend * 0.5);

    // ---- height-based weights ----
    float sand_w = 1.0 - smoothstep(beach_height - blend_width, beach_height + blend_width * 0.3, v_height);
    float rock_w = smoothstep(grass_height - blend_width, grass_height + blend_width, v_height);
    float grass_w = max(1.0 - sand_w - rock_w, 0.0);

    // ---- slope-based cliff override ----
    float slope = dot(normalize(v_normal_world), vec3(0.0, 1.0, 0.0));
    float cliff_w = 1.0 - smoothstep(cliff_slope - 0.12, cliff_slope + 0.05, slope);

    // Combine
    vec3 height_col = sand * sand_w + ground * grass_w + rock * rock_w;
    vec3 color = mix(height_col, rock, cliff_w);

    ALBEDO    = color;
    ROUGHNESS = mix(0.80, 0.95, cliff_w);
    METALLIC  = 0.0;
}
