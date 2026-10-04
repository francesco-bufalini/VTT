shader_type spatial;

render_mode unshaded, blend_mix, depth_draw_never, cull_disabled;

// A very small clip-space bias keeps grid lines visible when a cell face is
// exactly coplanar with a solid surface, without disabling depth testing.
void vertex() {
	Z_CLIP_SCALE = 1.0005;
}

void fragment() {
	ALBEDO = grid_color.rgb;
	ALPHA = grid_color.a;
}
