shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_disabled, diffuse_burley, specular_schlick_ggx;

uniform vec4 water_color : source_color = vec4(0.018, 0.13, 0.15, 1.0);
uniform vec3 ripple_origin = vec3(0.0, -3.0, 0.0);
uniform float ripple_strength = 0.0;
uniform float time_offset = 0.0;
uniform vec2 pool_center = vec2(0.0, 0.0);
uniform vec2 pool_half_size = vec2(19.0, 42.0);
uniform bool analytic_lamps = true;
varying vec3 world_position;

float height_at(vec2 p, float t) {
    float h = sin(p.x * 0.45 + p.y * 0.29 + t * 0.54) * 0.045;
    h += sin(p.y * 1.22 - p.x * 0.76 - t * 0.81) * 0.023;
    h += sin(p.x * 2.9 + p.y * 2.3 + t * 1.09) * 0.007;
    float dist = length(p - ripple_origin.xz);
    h += sin(dist * 2.5 - t * 3.2) * exp(-dist * 0.10) * ripple_strength * 0.16;
    return h;
}
void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    float t = TIME + time_offset;
    VERTEX.y += height_at(world_position.xz, t);
    world_position.y += height_at(world_position.xz, t);
}
void fragment() {
    float t = TIME + time_offset;
    vec2 p = world_position.xz;
    float h = height_at(p, t);
    float dx = (height_at(p + vec2(0.08, 0.0), t) - h) / 0.08;
    float dz = (height_at(p + vec2(0.0, 0.08), t) - h) / 0.08;
    vec3 normal_world = normalize(vec3(-dx, 1.0, -dz));
    NORMAL = normalize((VIEW_MATRIX * vec4(normal_world, 0.0)).xyz);
    float fresnel = pow(1.0 - abs(dot(NORMAL, VIEW)), 4.0);
    float wavelets = sin(p.x * 9.2 + t * 0.6) * sin(p.y * 8.6 - t * 0.8);
    vec2 basin_p = p - pool_center;
    float rim = 1.0 - smoothstep(0.0, 0.42, min(pool_half_size.x - abs(basin_p.x), pool_half_size.y - abs(basin_p.y)));
    float foam = clamp(rim * (0.055 + wavelets * 0.028), 0.0, 0.09);
    // Analytic reflections of the authored ceiling strips remain available on OpenGL.
    // Reflected viewing rays intersect the lamp plane; wave normals break up the streaks.
    vec3 camera_world = INV_VIEW_MATRIX[3].xyz;
    vec3 reflected_ray = reflect(normalize(world_position - camera_world), normal_world);
    float glint = 0.0;
    if (analytic_lamps && reflected_ray.y > 0.01 && camera_world.y > 0.0) {
        vec3 lamp_hit = world_position + reflected_ray * ((10.97 - world_position.y) / reflected_ray.y);
        for (int i = 0; i < 4; i++) {
            float lamp_z = pool_center.y + (-34.0 + float(i) * 24.0) * (pool_half_size.y / 42.0);
            float strip_z = max(abs(lamp_hit.z - lamp_z) - 1.47, 0.0);
            float strip_x = abs(abs(lamp_hit.x - pool_center.x) - (pool_half_size.x - 3.0));
            glint += exp(-strip_x * strip_x * 28.0 - strip_z * strip_z * 5.0);
        }
    }
    ALBEDO = mix(water_color.rgb, vec3(0.13, 0.24, 0.25), fresnel * 0.43) + foam;
    EMISSION = vec3(0.012, 0.042, 0.049) * (1.0 + h * 2.0) + vec3(0.28, 0.54, 0.58) * glint * fresnel;
    METALLIC = 0.32;
    ROUGHNESS = 0.15 + wavelets * 0.03;
    SPECULAR = 0.78;
    ALPHA = clamp(mix(0.88, 0.99, fresnel) + foam, 0.0, 1.0);
}
