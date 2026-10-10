shader_type spatial;
render_mode blend_mix, depth_draw_never, cull_disabled, unshaded, fog_disabled;

varying float visibility;
void vertex() {
    vec3 center = (MODEL_MATRIX * vec4(0.0, 0.0, 0.0, 1.0)).xyz;
    center.x += sin(TIME * 0.17 + center.z) * 0.25;
    center.y += sin(TIME * 0.12 + center.x) * 0.20;
    vec3 view_center = (VIEW_MATRIX * vec4(center, 1.0)).xyz;
    float distance_to_camera = length(view_center);
    visibility = smoothstep(0.4, 1.8, distance_to_camera) * (1.0 - smoothstep(7.0, 18.0, distance_to_camera));
    visibility *= 1.0 - smoothstep(-0.25, 0.15, INV_VIEW_MATRIX[3].y);
    POSITION = PROJECTION_MATRIX * vec4(view_center + VERTEX, 1.0);
}
void fragment() {
    float disk = 1.0 - smoothstep(0.12, 0.5, length(UV - vec2(0.5)));
    ALBEDO = vec3(0.20, 0.32, 0.29);
    ALPHA = disk * visibility * 0.22;
}
