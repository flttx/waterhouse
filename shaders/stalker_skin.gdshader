shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D skin_texture : source_color, filter_linear_mipmap;
uniform sampler2D skin_normal : hint_normal, filter_linear_mipmap;
uniform vec3 tint = vec3(0.5, 0.53, 0.47);
uniform float arousal : hint_range(0.0, 1.0) = 0.0;
uniform bool lure_species = false;
varying vec3 rest_position;

void vertex() {
	rest_position = VERTEX;
}

void fragment() {
	vec3 pigment = texture(skin_texture, UV).rgb;
	ALBEDO = pigment * tint;
	NORMAL_MAP = texture(skin_normal, UV).rgb;
	NORMAL_MAP_DEPTH = 0.7;
	ROUGHNESS = 0.43;
	METALLIC = 0.03;
	EMISSION = vec3(0.09, 0.15, 0.12) * smoothstep(0.72, 0.95, max(pigment.r, max(pigment.g, pigment.b))) * arousal * 0.15;
	if (lure_species) {
		float bulb = 1.0 - smoothstep(0.045, 0.072, distance(rest_position, vec3(0.0, 0.49, 0.462)));
		EMISSION += vec3(0.35, 0.78, 0.65) * bulb * (1.3 + sin(TIME * 1.2) * 0.2);
	}
}
