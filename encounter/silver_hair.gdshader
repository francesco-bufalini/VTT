shader_type spatial;
render_mode cull_disabled;
void fragment() {
	float strand = sin(UV.x*75.0)*0.5+0.5;
	float fine = sin(UV.x*240.0)*0.5+0.5;
	ALBEDO = mix(vec3(0.37,0.39,0.40),vec3(0.72,0.74,0.73),0.45+strand*0.35+fine*0.10);
	ROUGHNESS = 0.58;
	SPECULAR = 0.42;
}
