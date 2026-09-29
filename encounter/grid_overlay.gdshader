shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never;
uniform vec4 base_color : source_color = vec4(0.0);
uniform vec4 minor_line_color : source_color = vec4(0.38, 0.58, 0.59, 1.0);
uniform vec4 major_line_color : source_color = vec4(0.6, 0.7, 0.68, 1.0);
uniform float cell_size = 1.0;
uniform float major_every = 5.0;
uniform float shoulder_gap = 0.0;
uniform float interaction_strength = 0.55;
varying vec2 grid_pos;
float grid_line(vec2 p, float spacing) {
 vec2 q = p / spacing;
 vec2 line = abs(fract(q - 0.5) - 0.5) / max(fwidth(q), vec2(0.0001));
 return 1.0 - min(min(line.x, line.y), 1.0);
}
void vertex() {
 grid_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xz;
}
void fragment() {
 if (shoulder_gap > 0.0 && abs(grid_pos.x) < shoulder_gap) { discard; }
 float minor = grid_line(grid_pos, cell_size);
 float major = grid_line(grid_pos, cell_size * major_every);
 ALBEDO = mix(base_color.rgb, minor_line_color.rgb, minor);
 ALBEDO = mix(ALBEDO, major_line_color.rgb, major);
 ALPHA = max(base_color.a, max(minor * 0.6, major * 0.8)*interaction_strength);
}
