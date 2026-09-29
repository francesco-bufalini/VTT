shader_type spatial;
uniform sampler2D diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nor_gl : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough : filter_linear_mipmap_anisotropic, repeat_enable;
void fragment() {
 vec2 uv=UV*vec2(28.0,14.0);
 vec3 stone=texture(diff,uv).rgb;
 ALBEDO=stone*vec3(0.20,0.23,0.25);
 NORMAL_MAP=texture(nor_gl,uv).rgb;
 NORMAL_MAP_DEPTH=1.25;
 ROUGHNESS=max(0.62,texture(rough,uv).r);
}
