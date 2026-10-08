shader_type spatial;
render_mode blend_mix, depth_prepass_alpha, cull_disabled;
uniform vec4 skin_color : source_color = vec4(.20,.46,.43,1);
uniform float phase = 0.0;
void vertex(){
 VERTEX.xz *= 1.0 + sin(TIME*1.1+phase)*.045;
}
void fragment(){
 float edge=pow(1.0-abs(dot(NORMAL,VIEW)),2.0);
 ALBEDO=skin_color.rgb*(.45+edge*.3);
 ALPHA=.30+edge*.42;
 ROUGHNESS=.28;
 SPECULAR=.45;
 EMISSION=skin_color.rgb*(.08+edge*.24);
 BACKLIGHT=skin_color.rgb*.25;
}
