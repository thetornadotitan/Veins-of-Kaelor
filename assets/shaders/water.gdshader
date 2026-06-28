shader_type spatial;
render_mode blend_mix, depth_draw_opaque, cull_back, diffuse_toon, specular_toon;

// --- COLORS ---
group_uniforms Colors;
uniform vec3 color_deep : source_color = vec3(0.08, 0.18, 0.4);
uniform vec3 color_shallow : source_color = vec3(0.15, 0.55, 0.65);
uniform vec3 color_foam : source_color = vec3(0.95, 0.95, 0.95);
uniform vec3 color_caustic : source_color = vec3(0.15, 0.65, 0.75);

// --- TRANSPARENCY, REFRACTION, REFLECTION ---
group_uniforms Optics;
uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
// How far down you can see before the water becomes completely opaque
uniform float transparency_clarity : hint_range(0.0, 20.0, 0.1) = 15.0; 
// How strongly the water bends the light of the terrain underneath
uniform float refraction_strength : hint_range(0.0, 0.05, 0.001) = 0.005;
// Stylized sky reflection color
uniform vec3 color_sky : source_color = vec3(0.45, 0.65, 0.95);
// How strong the sky reflects at glancing angles
uniform float reflection_strength : hint_range(0.0, 1.0, 0.05) = 0.05;

// --- DEPTH & FOAM ---
group_uniforms Depth_Settings;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;
uniform float depth_distance : hint_range(0.0, 10.0, 0.1) = 3.0;
uniform float foam_distance : hint_range(0.0, 2.0, 0.05) = 0.1;

// --- WAVES & PIXELATION ---
group_uniforms Style;
uniform float voxel_scale : hint_range(1.0, 100.0) = 32.0; 
uniform float color_quantization : hint_range(2.0, 64.0, 1.0) = 64.0;

group_uniforms Animation;
uniform vec2 swell_dir = vec2(1.0, 0.5);
uniform float swell_speed = 0.02;
uniform float swell_scale = 0.05;
uniform vec2 band_dir = vec2(-1.0, 0.5);
uniform float band_speed = 0.05;
uniform float band_scale = 0.2;
uniform float sparkle_speed = 0.1;
uniform float sparkle_scale = 1.0;
uniform float sparkle_threshold = 0.95;

// --- PROCEDURAL NOISE ---
float hash(vec2 p) {
    return fract(sin(dot(p, vec2(127.1, 311.7))) * 43758.5453);
}

// Tiling version of noise
float noise(vec2 p) {
    // 1. Define your tiling period (must match your mod 128.0)
    float period = 128.0;
    
    // 2. Wrap the input coordinates to the period immediately
    vec2 p_wrapped = mod(p, period);
    
    // 3. Perform calculations on the wrapped coordinate
    vec2 i = floor(p_wrapped);
    vec2 f = fract(p_wrapped);
    vec2 u = f * f * (3.0 - 2.0 * f);
    
    // 4. Wrap the indices inside the hash lookups to ensure the 
    // noise grid connects perfectly at the edges
    return mix(mix(hash(mod(i + vec2(0.0, 0.0), period)), 
                   hash(mod(i + vec2(1.0, 0.0), period)), u.x),
               mix(hash(mod(i + vec2(0.0, 1.0), period)), 
                   hash(mod(i + vec2(1.0, 1.0), period)), u.x), u.y);
}

void fragment() {
    // 1. World Position & UV Quantization
    // 1. Get the world position of the PIXEL, not the vertex
    // This removes reliance on the mesh's local coordinates
    vec4 world_surface = INV_VIEW_MATRIX * vec4(VERTEX, 1.0);
    
    // Instead of modding just the UVs, use a consistent world coordinate
    // that is always positive and continuous
    vec2 world_pos_xz = world_surface.xz; 

    // Calculate UVs using a continuous world grid
    vec2 uv = floor(world_pos_xz * voxel_scale) / voxel_scale;

    // 2. TRUE World-Space Depth Calculation
    float depth_val = texture(depth_texture, SCREEN_UV).r;
    vec3 ndc = vec3(SCREEN_UV, depth_val) * 2.0 - 1.0;
    vec4 world_terrain = INV_VIEW_MATRIX * INV_PROJECTION_MATRIX * vec4(ndc, 1.0);
    world_terrain.xyz /= world_terrain.w;
    float water_depth = max(world_surface.y - world_terrain.y, 0.0);

    // 3. REFRACTION (Screen Texture Wobble)
    // Create a vector to push the screen UV around based on our pixelated noise
    vec2 distortion = vec2(
        noise(uv * 2.0 + TIME * 0.2),
        noise(uv * 2.0 - TIME * 0.2)
    ) * 2.0 - 1.0;
    
    vec2 refracted_uv = SCREEN_UV + (distortion * refraction_strength);
    vec3 refracted_bg = texture(screen_texture, refracted_uv).rgb;
    // Quantize the background so the terrain underneath *also* matches the retro style
    refracted_bg = floor(refracted_bg * color_quantization) / color_quantization;

    // 4. TRANSPARENCY & WATER COLOR
    float depth_blend = clamp(water_depth / depth_distance, 0.0, 1.0);
    vec3 water_color = mix(color_shallow, color_deep, depth_blend);
    
    // Mix the refracted background with the water color based on depth
    float opacity_blend = clamp(water_depth / transparency_clarity, 0.0, 1.0);
    vec3 base_color = mix(refracted_bg, water_color, opacity_blend);

    // 5. STYLIZED SKY REFLECTION (Quantized Fresnel)
    // Calculates how flat the camera angle is relative to the water
    float fresnel = sqrt(1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0));
    // Break the smooth reflection into chunky bands
    float quantized_fresnel = floor(fresnel * 4.0) / 4.0;
    base_color = mix(base_color, color_sky, quantized_fresnel * reflection_strength);

    // 6. Large Slow Swells 
    vec2 swell_uv = uv * swell_scale + TIME * swell_dir * swell_speed;
    float swell_noise = noise(swell_uv);
    base_color = mix(base_color, base_color * 0.6, swell_noise * 0.4);

    // 7. Mid-frequency Bands 
    vec2 band_uv = uv * band_scale + TIME * band_dir * band_speed;
    float band_noise = sin(band_uv.x * 10.0 + noise(band_uv) * 5.0) * 0.5 + 0.5;
    base_color = mix(base_color, color_shallow * 1.3, band_noise * 0.15);

    // 8. Sparkles / Caustic Highlights
    vec2 sparkle_uv = uv * sparkle_scale + TIME * vec2(0.5, 0.5) * sparkle_speed;
    float s_noise = noise(sparkle_uv * 10.0);
    if (s_noise > sparkle_threshold - (fresnel * 0.05)) {
        base_color = mix(base_color, color_caustic, 0.8);
    }

    // 9. Animated Shoreline Foam
    float foam_blend = clamp(water_depth / foam_distance, 0.0, 1.0);
    float tide = sin(TIME * 1.5 - foam_blend * 5.0) * 0.15;
    float foam_noise = noise(uv * 4.0 - vec2(0.0, TIME * 0.5)) * 0.2;
    if (foam_blend < 0.3 + tide + foam_noise) {
        base_color = color_foam;
    }

    // 10. Final Color Quantization
    base_color = floor(base_color * color_quantization) / color_quantization;

    ALBEDO = base_color;
    ROUGHNESS = 0.7;
    METALLIC = 0.0;
}