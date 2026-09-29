shader_type spatial;
varying vec3 local_point;
void vertex() { local_point=VERTEX; }
float hash(vec3 p) {return fract(sin(dot(p,vec3(17.3,73.1,49.7)))*43758.5453);}
void fragment() {
	vec3 p=local_point*1.2;
	vec3 cell=floor(p);
	float star=step(.981,hash(cell))*(1.0-smoothstep(.045,.24,length(fract(p)-.5)));
	float cloud=.5+.5*sin(p.x*.13+sin(p.y*.17)+p.z*.11);
	float gold=smoothstep(15.5,18.0,abs(local_point.x))*(1.0-smoothstep(88.0,92.0,local_point.y));
	ALBEDO=mix(mix(vec3(.009,.007,.018),vec3(.045,.009,.022),cloud)+star*vec3(.8,.35,.26),vec3(.48,.28,.08),gold);
	ROUGHNESS=.46;
	METALLIC=mix(.18,.8,gold);
	EMISSION=star*vec3(1.0,.18,.10)*.8;
}
