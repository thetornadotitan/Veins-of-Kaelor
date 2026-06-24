shader_type spatial;
render_mode cull_disabled, depth_draw_always, blend_mix;

uniform vec4 shallow_color : source_color = vec4(0.2, 0.5, 0.7, 0.6);
uniform vec4 deep_color : source_color = vec4(0.05, 0.15, 0.3, 0.9);
uniform float water_level = 8.0;
uniform float max_depth = 20.0;
uniform float foam_threshold = 1.5;
uniform float edge_fade = 2.0;

uniform float wave_a_strength = 0.3;
uniform float wave_a_freq = 0.5;
uniform vec2 wave_a_dir = vec2(1.0, 0.0);
uniform float wave_a_speed = 1.0;

uniform float wave_b_strength = 0.15;
uniform float wave_b_freq = 0.8;
uniform vec2 wave_b_dir = vec2(0.0, 1.0);
uniform float wave_b_speed = 1.1;

uniform float wave_c_strength = 0.1;
uniform float wave_c_freq = 1.2;
uniform vec2 wave_c_dir = vec2(0.7, 0.7);
uniform float wave_c_speed = 0.9;

uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

vec3 gerstner(vec2 pos, vec2 dir, float steepness, float wavelength, float speed) {
	float k = 2.0 * 3.14159 / wavelength;
	float c = sqrt(9.8 / k);
	float f = k * (dot(dir, pos) - c * speed * TIME);
	float a = steepness / k;
	return vec3(dir.x * a * cos(f), a * sin(f), dir.y * a * cos(f));
}

void vertex() {
	vec3 p = VERTEX;
	p += gerstner(p.xz, wave_a_dir, wave_a_strength, 12.0, wave_a_speed);
	p += gerstner(p.xz, wave_b_dir, wave_b_strength, 8.0, wave_b_speed);
	p += gerstner(p.xz, wave_c_dir, wave_c_strength, 5.0, wave_c_speed);
	VERTEX = p;
}

void fragment() {
	float scene_depth_raw = textureLod(depth_texture, SCREEN_UV, 0.0).r;

	#if CURRENT_RENDERER == RENDERER_COMPATIBILITY
		vec3 ndc = vec3(SCREEN_UV, scene_depth_raw) * 2.0 - 1.0;
	#else
		vec3 ndc = vec3(SCREEN_UV * 2.0 - 1.0, scene_depth_raw);
	#endif

	vec4 view = INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
	view.xyz /= view.w;
	float linear_scene_depth = -view.z;

	vec3 water_ndc_pos = vec3(SCREEN_UV * 2.0 - 1.0, FRAGCOORD.z);
	vec4 water_view = INV_PROJECTION_MATRIX * vec4(water_ndc_pos, 1.0);
	water_view.xyz /= water_view.w;
	float linear_water_depth = -water_view.z;

	float depth_diff = linear_scene_depth - linear_water_depth;

	ALPHA = 0.0;

	if (depth_diff < 0.0) {
		discard;
	}

	float water_thickness = depth_diff;
	float depth_factor = clamp(water_thickness / max_depth, 0.0, 1.0);
	vec4 base_color = mix(shallow_color, deep_color, depth_factor);
	ALBEDO = base_color.rgb;
	ALPHA = base_color.a;

	ALPHA *= smoothstep(0.0, edge_fade, water_thickness);

	float foam = 1.0 - smoothstep(foam_threshold * 0.5, foam_threshold, water_thickness);
	ALBEDO = mix(ALBEDO, vec3(0.9, 0.95, 1.0), foam * 0.6);

	float wave_pattern = sin(VERTEX.x * 3.0 + TIME * 2.0) * sin(VERTEX.z * 3.0 + TIME * 1.5);
	ALBEDO += vec3(0.02) * wave_pattern;

	ROUGHNESS = 0.1;
	METALLIC = 0.0;
}
