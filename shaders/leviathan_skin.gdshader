shader_type spatial;
render_mode cull_back, diffuse_burley, specular_schlick_ggx;

uniform sampler2D skin_texture : source_color, filter_linear_mipmap;
uniform sampler2D skin_normal : hint_normal, filter_linear_mipmap;
uniform float arousal : hint_range(0.0, 1.0) = 0.0;
// Original normalized texture-space coordinates survive the metric swim rebind.
uniform mat4 rest_to_model = mat4(1.0);
varying vec3 rest_position;

void vertex() {
	rest_position = (rest_to_model * vec4(VERTEX, 1.0)).xyz;
}

void fragment() {
	vec3 pigment = texture(skin_texture, UV).rgb;
	ALBEDO = pigment * vec3(0.36, 0.44, 0.43);
	NORMAL_MAP = texture(skin_normal, UV).rgb;
	NORMAL_MAP_DEPTH = 0.8;
	ROUGHNESS = 0.42;
	METALLIC = 0.06;
	float bright = max(pigment.r, max(pigment.g, pigment.b));
	float chroma = bright - min(pigment.r, min(pigment.g, pigment.b));
	float spots = smoothstep(0.5, 0.78, bright) * (1.0 - smoothstep(0.12, 0.3, chroma));
	spots *= smoothstep(0.036, 0.063, rest_position.y) * (1.0 - smoothstep(0.11, 0.14, rest_position.y));
	spots *= smoothstep(-0.47, -0.35, rest_position.z) * (1.0 - smoothstep(0.36, 0.44, rest_position.z));
	float pulse = 0.45 + 0.25 * sin(TIME * 1.1 + rest_position.z * 20.0);
	EMISSION = vec3(0.12, 0.35, 0.32) * spots * pulse * (0.3 + arousal * 0.65);
}
