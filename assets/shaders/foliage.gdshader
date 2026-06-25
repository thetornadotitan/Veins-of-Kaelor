shader_type spatial;
render_mode cull_disabled, vertex_lighting, depth_draw_opaque;

uniform float wind_strength = 0.3;
uniform float wind_speed = 1.0;
uniform sampler2D texture_albedo : hint_default_white, repeat_disable, filter_nearest;
uniform float alpha_scissor_threshold = 0.5;

void vertex() {
	float wind = sin(TIME * wind_speed + (VERTEX.y * 2.0) + INSTANCE_CUSTOM.x * 6.28) * wind_strength * INSTANCE_CUSTOM.y;
	VERTEX.x += wind;
}

void fragment() {
	vec4 tex = texture(texture_albedo, UV);
	ALBEDO = tex.rgb * COLOR.rgb;
	ALPHA = tex.a;
	ALPHA_SCISSOR_THRESHOLD = alpha_scissor_threshold;
}
