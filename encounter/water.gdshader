shader_type spatial;
render_mode cull_disabled;
varying vec3 world;
void vertex() {
 world = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
 float ripple = sin(world.x * 0.6 + world.z * 0.5 + TIME * 0.8 + sin(world.z*0.35));
 float swell = sin(world.x * 0.17 + world.z * 0.23 + TIME * 0.15);
 vec2 p = world.xz * 0.08;
 float cloud = sin(p.x+sin(p.y+TIME*.045))*sin(p.y*.7+TIME*.035)*.5+.5;
 float vein = pow(1.0-abs(sin((p.y*.6+cloud*3.0+TIME*.04)*7.0)),22.0);
 ALBEDO = mix(vec3(.15,.16,.17),vec3(.48,.49,.50),cloud*.55+ripple*.045)+vec3(.30,.31,.32)*vein*.32;
 EMISSION = ALBEDO * 0.08;
 NORMAL_MAP = normalize(vec3(ripple * 0.08, swell * 0.06, 1.0)) * 0.5 + 0.5;
 ROUGHNESS = 0.42;
 METALLIC = 0.18;
 SPECULAR = 0.22;
}
