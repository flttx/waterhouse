shader_type spatial;
render_mode diffuse_burley, specular_schlick_ggx;
uniform vec4 skin_color : source_color = vec4(.09,.17,.16,1.0);
uniform float translucent = 0.0;
uniform float phase = 0.0;
uniform float glow = 0.02;
uniform float flexible = 0.0;
varying vec3 rest_position;
void vertex(){
 rest_position = VERTEX;
 float tail = smoothstep(0.0,3.5,VERTEX.z);
 VERTEX.x += sin(TIME*1.6-VERTEX.z*1.4+phase)*tail*.25*flexible;
 VERTEX.y += sin(TIME*.8+VERTEX.z+phase)*.04*flexible;
}
void fragment(){
 float folds = sin(rest_position.y*19.0+sin(rest_position.z*6.0))*sin(rest_position.x*11.0);
 float veins = pow(abs(sin(rest_position.x*7.0+rest_position.y*8.0+sin(rest_position.z*5.0))),14.0);
 ALBEDO = skin_color.rgb*(.78+.12*folds)+skin_color.rgb*.22*veins;
 ROUGHNESS = .72 + veins*.10;
 METALLIC=0.0;
 SPECULAR=.14;
 EMISSION=skin_color.rgb*glow*(.65+.35*sin(TIME*.9+phase));
}
