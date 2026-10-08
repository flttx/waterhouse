shader_type canvas_item;
render_mode unshaded;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float underwater : hint_range(0.0,1.0) = 0.0;
uniform float stress : hint_range(0.0,1.0) = 0.0;
uniform float injury : hint_range(0.0,1.0) = 0.0;
uniform float brightness : hint_range(0.7,1.6) = 1.12;
uniform float grain_enabled = 1.0;

float hash(vec2 p){return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453);}
void fragment(){
	vec2 uv = SCREEN_UV;
	vec2 wobble = vec2(sin(uv.y*18.0+TIME*1.3), cos(uv.x*15.0+TIME*0.8))*0.0019*underwater;
	vec3 col = texture(screen_texture,uv+wobble).rgb;
	float vignette = smoothstep(0.25,0.85,length((uv-.5)*vec2(1.0,.85)));
	col = mix(col,col*vec3(.43,.86,.82)+vec3(.008,.025,.024),underwater*.8);
	col *= brightness*(1.0-vignette*(.3+stress*.35+underwater*.2));
	float grain = (hash(FRAGCOORD.xy+floor(TIME*24.0))-0.5)*.026*grain_enabled;
	col += grain;
	col = mix(col,vec3(.22,.025,.022),vignette*injury*.62);
	COLOR = vec4(col,1.0);
}
