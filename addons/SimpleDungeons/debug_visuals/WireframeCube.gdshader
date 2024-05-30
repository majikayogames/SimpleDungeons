shader_type spatial;
render_mode unshaded, cull_disabled, depth_test_disabled;
uniform vec2 grid_size;
uniform vec3 color = vec3(0.);

void fragment() {
	vec2 uv = fract(UV * grid_size);
	vec2 eps = 0.0015 * grid_size;
	vec2 inv_eps = 1.0 - eps;
	if(uv.x > eps.x && uv.x < inv_eps.x && uv.y > eps.y && uv.y < inv_eps.y) {
		discard;
	}
	ALBEDO = color;
}