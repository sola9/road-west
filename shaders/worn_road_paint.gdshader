shader_type spatial;

render_mode cull_back, depth_draw_opaque;

uniform vec4 paint_color : source_color = vec4(
	0.95,
	0.67,
	0.08,
	1.0
);

uniform float roughness :
	hint_range(0.0, 1.0, 0.01) = 0.82;

uniform float wear_amount :
	hint_range(0.0, 1.0, 0.01) = 0.22;

uniform float edge_wear :
	hint_range(0.0, 1.0, 0.01) = 0.25;

uniform float wear_softness :
	hint_range(0.001, 0.25, 0.001) = 0.035;

uniform float color_variation :
	hint_range(0.0, 0.5, 0.01) = 0.10;

uniform float marking_width = 0.14;
uniform float longitudinal_uv_length = 8.0;

uniform float wear_frequency :
	hint_range(0.1, 100.0, 0.1) = 10.0;

uniform float large_wear_frequency :
	hint_range(0.1, 20.0, 0.1) = 1.8;

/*
	Simple deterministic 2D value noise.

	This avoids requiring an external wear texture and remains stable
	because it is based on the marking UV coordinates.
*/
float random_value(vec2 coordinate) {
	return fract(
		sin(
			dot(
				coordinate,
				vec2(12.9898, 78.233)
			)
		) * 43758.5453
	);
}


float value_noise(vec2 coordinate) {
	vec2 cell = floor(coordinate);
	vec2 fraction = fract(coordinate);

	fraction = fraction * fraction * (
		3.0 - 2.0 * fraction
	);

	float bottom_left = random_value(cell);
	float bottom_right = random_value(
		cell + vec2(1.0, 0.0)
	);

	float top_left = random_value(
		cell + vec2(0.0, 1.0)
	);

	float top_right = random_value(
		cell + vec2(1.0, 1.0)
	);

	float bottom = mix(
		bottom_left,
		bottom_right,
		fraction.x
	);

	float top = mix(
		top_left,
		top_right,
		fraction.x
	);

	return mix(
		bottom,
		top,
		fraction.y
	);
}


float fractal_noise(vec2 coordinate) {
	float result = 0.0;
	float amplitude = 0.5;

	for (int octave = 0; octave < 4; octave++) {
		result += value_noise(coordinate) * amplitude;
		coordinate *= 2.03;
		amplitude *= 0.5;
	}

	return result;
}


void fragment() {
	// Convert the marking UV coordinates into approximate meters.
	vec2 physical_coordinates = vec2(
		UV.x * marking_width,
		UV.y * longitudinal_uv_length
	);

	// UV2 is constant across one strip but different for every line.
	vec2 pattern_coordinates = (
		physical_coordinates + UV2
	);

	// Slightly increase frequency across the narrow paint strip.
	vec2 fine_coordinates = vec2(
		pattern_coordinates.x
			* wear_frequency
			* 1.5,
		pattern_coordinates.y
			* wear_frequency
	);

	vec2 broad_coordinates = (
		pattern_coordinates
		* large_wear_frequency
	);

	float fine_wear = fractal_noise(
		fine_coordinates
	);

	float broad_wear = fractal_noise(
		broad_coordinates
	);

	float wear_pattern = mix(
		fine_wear,
		broad_wear,
		0.45
	);

	// Zero at either edge of the strip and one at its center.
	float edge_distance = (
		1.0
		- abs(UV.x * 2.0 - 1.0)
	);

	float edge_damage = (
		1.0
		- smoothstep(
			0.0,
			0.35,
			edge_distance
		)
	) * edge_wear;

	float adjusted_wear = (
		wear_pattern - edge_damage
	);

	float wear_threshold = mix(
		0.18,
		0.82,
		wear_amount
	);

	float coverage = smoothstep(
		wear_threshold - wear_softness,
		wear_threshold + wear_softness,
		adjusted_wear
	);

	ALPHA = coverage;
	ALPHA_SCISSOR_THRESHOLD = 0.5;

	// Use the per-line coordinates here too, so discoloration differs.
	float discoloration = value_noise(
		pattern_coordinates * vec2(
			5.0,
			2.0
		)
	);

	float brightness = mix(
		1.0 - color_variation,
		1.0,
		discoloration
	);

	ALBEDO = paint_color.rgb * brightness;
	ROUGHNESS = roughness;
	METALLIC = 0.0;
	SPECULAR = 0.15;
}