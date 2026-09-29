shader_type spatial;
uniform sampler2D diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nor_gl : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough : filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 stone_position;
void vertex() { stone_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
 vec3 p=stone_position;
 float grain=fract(sin(dot(floor(p*12.0),vec3(12.3,43.7,87.1)))*43758.54);
 float wear=sin(p.x*0.37+sin(p.y*0.51))*sin(p.z*0.32+p.y*0.18)*0.5+0.5;
 float seam=1.0-smoothstep(0.0,0.04,min(fract(p.y*0.65),1.0-fract(p.y*0.65)));
 vec3 n=abs(NORMAL); n/=max(n.x+n.y+n.z,0.001);
 vec3 stone=texture(diff,p.yz*0.23).rgb*n.x+texture(diff,p.xz*0.23).rgb*n.y+texture(diff,p.xy*0.23).rgb*n.z;
 ALBEDO=mix(stone,vec3(0.32,0.34,0.32),0.4)*(0.7+wear*0.3)*(1.0-seam*0.22);
 ROUGHNESS=0.92;
}
