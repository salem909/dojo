shader_type spatial;
render_mode depth_draw_opaque, cull_disabled;

// ---- screen / depth samplers (Godot 4) ------------------------------------
uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform sampler2D DEPTH_TEXTURE  : hint_depth_texture, filter_linear_mipmap;

// ---- colours ---------------------------------------------------------------
uniform vec4 shallow_color : source_color = vec4(0.22, 0.66, 0.84, 0.85);
uniform vec4 deep_color    : source_color = vec4(0.04, 0.12, 0.35, 0.95);
uniform vec3 fresnel_color : source_color = vec3(0.25, 0.45, 0.65);
uniform vec3 foam_color    : source_color = vec3(0.95, 0.98, 1.00);

// ---- depth -----------------------------------------------------------------
uniform float beers_law    = 2.0;
uniform float depth_offset = -0.75;

// ---- fresnel ---------------------------------------------------------------
uniform float fresnel_power     = 8.0;   // higher = narrower band at extreme angles
uniform float fresnel_intensity = 0.45;  // cap: 0=no reflection, 1=full

// ---- distance fade (prevents bright horizon) -------------------------------
uniform float horizon_start = 30.0;   // view-space distance where fade begins
uniform float horizon_end   = 150.0;  // where it reaches full strength
uniform float horizon_dark  = 0.55;   // how much to darken at max distance (0–1)

// ---- waves (xy = direction, z = steepness, w = wavelength) -----------------
uniform vec4 wave_a = vec4(1.0,  1.0, 0.22, 4.0);
uniform vec4 wave_b = vec4(1.0,  0.6, 0.18, 2.5);
uniform vec4 wave_c = vec4(0.8,  1.3, 0.12, 1.2);
uniform vec4 wave_d = vec4(-0.6, 0.9, 0.08, 0.8);
uniform float wave_speed = 0.4;

// ---- foam ------------------------------------------------------------------
uniform float foam_threshold = 0.55;
uniform float foam_intensity = 0.6;
uniform float edge_foam_width = 0.8;

// ---- Gerstner helper -------------------------------------------------------
vec4 gerstner(vec4 param, vec2 pos, float time,
              inout vec3 tangent, inout vec3 binormal) {
    float steepness  = param.z;
    float wavelength = param.w;
    float k = 2.0 * PI / wavelength;
    float c = sqrt(9.8 / k);
    vec2  d = normalize(param.xy);
    float f = k * (dot(d, pos) - c * time);
    float a = steepness / k;

    tangent += normalize(vec3(
        1.0 - d.x * d.x * steepness * sin(f),
        d.x * steepness * cos(f),
        -d.x * d.y * steepness * sin(f)));
    binormal += normalize(vec3(
        -d.x * d.y * steepness * sin(f),
        d.y * steepness * cos(f),
        1.0 - d.y * d.y * steepness * sin(f)));

    return vec4(d.x * a * cos(f), a * sin(f), d.y * a * cos(f), 0.0);
}

// ---- procedural noise (for foam, no textures) ------------------------------
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i),            hash(i + vec2(1,0)), f.x),
               mix(hash(i + vec2(0,1)),hash(i + vec2(1,1)), f.x), f.y);
}
float fbm(vec2 p) {
    float v = 0.0;
    v += noise(p * 1.0) * 0.50;
    v += noise(p * 2.0) * 0.25;
    v += noise(p * 4.0) * 0.125;
    return v;
}

// ---- varyings --------------------------------------------------------------
varying float wave_height;

// ---- vertex ----------------------------------------------------------------
void vertex() {
    float time = TIME * wave_speed;
    vec3 wp    = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    vec3 tang  = vec3(0.0);
    vec3 bin   = vec3(0.0);

    vec4 v = vec4(VERTEX, 1.0);
    v += gerstner(wave_a, wp.xz, time, tang, bin);
    v += gerstner(wave_b, wp.xz, time, tang, bin);
    v += gerstner(wave_c, wp.xz, time, tang, bin);
    v += gerstner(wave_d, wp.xz, time, tang, bin);

    TANGENT  = tang;
    BINORMAL = bin;
    NORMAL   = normalize(cross(bin, tang));
    VERTEX   = v.xyz;
    wave_height = v.y;
}

// ---- fragment --------------------------------------------------------------
void fragment() {
    // -- view-space distance (for horizon fade + foam attenuation) --
    float view_dist = -VERTEX.z;  // view-space Z is negative into the screen

    // -- depth sampling (Beer's law absorption) --
    float depth_raw  = texture(DEPTH_TEXTURE, SCREEN_UV).r;
    float depth      = PROJECTION_MATRIX[3][2] / (depth_raw + PROJECTION_MATRIX[2][2]);
    float depth_blend = exp((depth + VERTEX.z + depth_offset) * -beers_law);
    depth_blend       = clamp(1.0 - depth_blend, 0.0, 1.0);
    float depth_pow   = clamp(pow(depth_blend, 2.5), 0.0, 1.0);

    // -- refraction via screen texture --
    vec3 screen_col = textureLod(SCREEN_TEXTURE, SCREEN_UV, depth_pow * 2.5).rgb;
    vec3 water_col  = mix(shallow_color.rgb, deep_color.rgb, depth_pow);
    vec3 color      = mix(screen_col * water_col, water_col * 0.25, depth_pow * 0.5);

    // -- fresnel (capped intensity to prevent white-out at distance) --
    float ndotv = clamp(dot(normalize(NORMAL), normalize(VIEW)), 0.0, 1.0);
    float fres  = pow(1.0 - ndotv, fresnel_power) * fresnel_intensity;
    color = mix(color, fresnel_color, fres);

    // -- wave-peak foam (attenuated at distance to prevent white speckling) --
    float dist_atten = 1.0 - smoothstep(25.0, 100.0, view_dist);
    float peak = smoothstep(foam_threshold, foam_threshold + 0.15, wave_height);
    float foam_noise = fbm(UV * 120.0 + TIME * 0.6);
    float foam = peak * foam_noise * foam_intensity * dist_atten;

    // -- edge foam (where water meets geometry) --
    float z_depth = PROJECTION_MATRIX[3][2] / (texture(DEPTH_TEXTURE, SCREEN_UV).x + PROJECTION_MATRIX[2][2]);
    float z_pos   = PROJECTION_MATRIX[3][2] / (FRAGCOORD.z + PROJECTION_MATRIX[2][2]);
    float z_dif   = abs(z_depth - z_pos);
    float edge_foam = (1.0 - smoothstep(0.0, edge_foam_width, z_dif))
                    * fbm(UV * 80.0 + TIME * 0.3) * 0.7 * dist_atten;

    color = mix(color, foam_color, clamp(foam + edge_foam, 0.0, 1.0));

    // -- horizon darkening (simulate atmospheric absorption over distance) --
    float horizon_fade = smoothstep(horizon_start, horizon_end, view_dist);
    color = mix(color, deep_color.rgb * (1.0 - horizon_dark), horizon_fade);

    ALBEDO    = color;
    METALLIC  = 0.05;
    ROUGHNESS = 0.35;
    SPECULAR  = 0.35;
}
