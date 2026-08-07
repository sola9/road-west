shader_type spatial;


uniform sampler2D terrain_texture :
	source_color,
	repeat_enable,
	filter_linear_mipmap;


uniform float biome_tint_strength :
	hint_range(0.0, 1.0, 0.01) = 0.75;


uniform float roughness :
	hint_range(0.0, 1.0, 0.01) = 0.92;


uniform float specular :
	hint_range(0.0, 1.0, 0.01) = 0.15;


void fragment() {
	vec3 texture_color = texture(
		terrain_texture,
		UV
	).rgb;

	/*
		Convert the original terrain texture to brightness
		information, then recolor that detail with the biome
		vertex color.
	*/
	float texture_brightness = dot(
		texture_color,
		vec3(
			0.299,
			0.587,
			0.114
		)
	);

	vec3 biome_colored_texture = (
		COLOR.rgb
		* mix(
			0.65,
			1.35,
			texture_brightness
		)
	);

	ALBEDO = mix(
		texture_color,
		biome_colored_texture,
		biome_tint_strength
	);

	ROUGHNESS = roughness;
	SPECULAR = specular;
}