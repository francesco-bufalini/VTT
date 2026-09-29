shader_type spatial;
uniform sampler2D diff : source_color, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D nor_gl : hint_normal, filter_linear_mipmap_anisotropic, repeat_enable;
uniform sampler2D rough : filter_linear_mipmap_anisotropic, repeat_enable;
varying vec3 world_position;
float hash(vec2 p) { return fract(sin(dot(p,vec2(127.1,311.7)))*43758.5453); }
float noise(vec2 p) {
 vec2 i=floor(p); vec2 f=fract(p); f=f*f*(3.0-2.0*f);
 return mix(mix(hash(i),hash(i+vec2(1,0)),f.x),mix(hash(i+vec2(0,1)),hash(i+vec2(1,1)),f.x),f.y);
}
void vertex() { world_position=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
void fragment() {
 vec2 p=world_position.xz;
 float n=noise(p*0.45)*0.65+noise(p*2.5)*0.35;
 float vein=pow(abs(sin(p.x*0.6+p.y*0.3+noise(p*0.15)*8.0)),18.0);
 vec2 tex_uv=p*0.22;
 vec3 stone=texture(diff,tex_uv).rgb;
 ALBEDO=vec3(dot(stone,vec3(0.333)))*vec3(0.87,0.93,0.96)*(0.34+n*0.28)*(1.0-vein*0.10);
 NORMAL_MAP=texture(nor_gl,tex_uv).rgb;
 NORMAL_MAP_DEPTH=0.75;
 ROUGHNESS=max(0.6,texture(rough,tex_uv).r);
}
