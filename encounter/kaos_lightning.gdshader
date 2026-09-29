shader_type spatial;
render_mode unshaded, cull_disabled, shadows_disabled;
uniform float phase = 0.0;
void fragment() {
    float t = mod(TIME + phase, 2.7);
    float pulse = step(t, 0.09) + step(0.16,t)*step(t,0.21);
    if (pulse < 0.5) { discard; }
    ALBEDO = vec3(0.66,0.83,0.92);
    EMISSION = vec3(0.7,0.87,1.0)*1.8;
}
