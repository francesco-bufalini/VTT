shader_type spatial;
render_mode cull_disabled;
uniform vec4 cloth_color : source_color = vec4(0.70,0.69,0.62,1.0);
uniform bool embroidery = false;
uniform sampler2D diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nor_gl : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough : filter_linear_mipmap_anisotropic, repeat_enable;
void fragment() {
 float weave = sin(UV.x*1200.0)*sin(UV.y*1600.0)*0.025;
 float motif = smoothstep(0.65,0.92, sin(UV.x*90.0+sin(UV.y*80.0))*cos(UV.y*55.0));
 float border = embroidery ? 1.0 : 1.0-smoothstep(0.015,0.07,min(UV.x,1.0-UV.x));
 vec3 thread = mix(vec3(0.28,0.22,0.13),vec3(0.68,0.56,0.32),motif);
 vec2 tex_uv=UV*vec2(3.0,8.0);
 vec3 fabric=texture(diff,tex_uv).rgb;
 float luminance=dot(fabric,vec3(0.333));
 ALBEDO = mix(cloth_color.rgb*(0.5+luminance*0.7), thread, border*0.65);
 NORMAL_MAP=texture(nor_gl,tex_uv).rgb;
 NORMAL_MAP_DEPTH=0.45;
 ROUGHNESS = mix(max(0.65,texture(rough,tex_uv).r),0.56,border);
 METALLIC = border * 0.3;
}
