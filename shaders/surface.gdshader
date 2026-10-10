shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;

uniform vec4 base_color : source_color = vec4(0.33, 0.40, 0.39, 1.0);
uniform float tile_scale = 1.8;
uniform float grout_width = 0.006;
uniform float roughness_value = 0.55;
uniform float stain_strength = 0.34;
uniform bool ceramic = true;
uniform bool waterline = false;
varying vec3 world_position;
varying vec3 world_normal;

float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}
float noise(vec2 p) {
    vec2 i = floor(p);
    vec2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(hash(i), hash(i + vec2(1.0, 0.0)), f.x),
               mix(hash(i + vec2(0.0, 1.0)), hash(i + vec2(1.0)), f.x), f.y);
}
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize((MODEL_MATRIX * vec4(NORMAL, 0.0)).xyz);
}
void fragment() {
    vec3 n = abs(world_normal);
    vec2 p = world_position.xz;
    if (n.x > n.y && n.x > n.z) { p = world_position.zy; }
    else if (n.z > n.y) { p = world_position.xy; }
    vec2 t = p * tile_scale;
    vec2 edge = min(fract(t), 1.0 - fract(t));
    float grout = 1.0 - smoothstep(grout_width, grout_width + 0.006, min(edge.x, edge.y));
    float tile_tone = mix(0.84, 1.05, hash(floor(t)));
    float patina = noise(p * 0.37) * 0.65 + noise(p * 2.1) * 0.35;
    float grit = noise(p * 65.0);
    vec3 color = base_color.rgb * tile_tone;
    if (ceramic) {
        color = mix(color, base_color.rgb * 0.20, grout * 0.82);
    } else {
        color = base_color.rgb * (0.82 + grit * 0.25);
    }
    color *= 1.0 - stain_strength * patina;
    float damp = 1.0 - smoothstep(-1.4, 1.6, world_position.y);
    if (waterline) {
        float tide = 1.0 - smoothstep(0.03, 0.28, abs(world_position.y - 0.10));
        color = mix(color, vec3(0.10, 0.15, 0.10), tide * (0.45 + patina * 0.35));
        color *= 1.0 - damp * 0.22;
    }
    // Broken damp patches retain the dry grout and avoid a uniformly polished floor.
    float horizontal = smoothstep(0.7, 0.96, n.y);
    float wet_patch = smoothstep(0.52, 0.75, patina) * horizontal * (1.0 - grout);
    color *= 1.0 - wet_patch * 0.12;
    // Only the shallow band receives moving caustics; deep walls remain dark.
    float shallow = smoothstep(-7.0, -0.7, world_position.y) * (1.0 - smoothstep(-0.35, 0.05, world_position.y));
    float caustic = pow(max(0.0, sin(p.x * 2.4 + sin(p.y * 1.7 + TIME * 0.35)) * sin(p.y * 2.8 - TIME * 0.28)), 8.0);
    EMISSION = vec3(0.028, 0.065, 0.058) * caustic * shallow;
    ALBEDO = color;
    ROUGHNESS = clamp(roughness_value + grout * 0.23 + grit * 0.07 - damp * 0.16 - wet_patch * 0.18, 0.18, 1.0);
    SPECULAR = 0.42;
    NORMAL_MAP = vec3(0.5 + (grit - 0.5) * 0.05, 0.5 + (patina - 0.5) * 0.035, 1.0);
    NORMAL_MAP_DEPTH = 0.22;
}
