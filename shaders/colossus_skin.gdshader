shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;
uniform sampler2D skin_texture : source_color, filter_linear_mipmap;
uniform sampler2D skin_normal : hint_normal, filter_linear_mipmap;
uniform bool has_normal = false;
uniform float arousal = 0.0;
uniform float head_turn = 0.0;

void vertex() {
	float head_weight = smoothstep(-8.0, -2.0, VERTEX.y);
	float turn = head_turn * head_weight;
	mat3 swivel = mat3(vec3(cos(turn), 0.0, -sin(turn)), vec3(0.0, 1.0, 0.0), vec3(sin(turn), 0.0, cos(turn)));
	VERTEX = swivel * (VERTEX - vec3(0.0, -5.0, 0.0)) + vec3(0.0, -5.0, 0.0);
	NORMAL = normalize(swivel * NORMAL);
	VERTEX += NORMAL * sin(TIME * 0.9 - VERTEX.y * 0.3) * 0.045;
}

void fragment() {
	vec3 pigment = texture(skin_texture, UV).rgb;
	ALBEDO = pigment * vec3(0.48, 0.53, 0.44);
	if (has_normal) { NORMAL_MAP = texture(skin_normal, UV).rgb; NORMAL_MAP_DEPTH = 0.6; }
	ROUGHNESS = 0.39;
	float amber = smoothstep(0.04, 0.17, pigment.r - pigment.b) * smoothstep(0.3, 0.65, pigment.r);
	EMISSION = vec3(0.24, 0.35, 0.12) * amber * (0.12 + arousal * 0.85);
}
