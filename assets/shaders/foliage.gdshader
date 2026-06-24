shader_type spatial;
render_mode cull_disabled, vertex_lighting;

uniform float wind_strength = 0.3;
uniform float wind_speed = 1.0;

void vertex() {
	float wind = sin(TIME * wind_speed + (VERTEX.y * 2.0) + INSTANCE_CUSTOM.x * 6.28) * wind_strength * INSTANCE_CUSTOM.y;
	VERTEX.x += wind;
}

void fragment() {
	ALBEDO = COLOR.rgb;
	ALPHA = 1.0;
}
