shader_type spatial;

render_mode blend_mix, depth_prepass_alpha, cull_back;

uniform bool use_asphalt_texture = false;

uniform sampler2D asphalt_texture :
	source_color,
	repeat_enable,
	filter_linear_mipmap;

uniform vec4 asphalt_tint : source_color = vec4(
	0.18,
	0.17,
	0.16,
	1.0
);

uniform float edge_fade_width :
	hint_range(0.001, 0.2, 0.001) = 0.035;

uniform float roughness :
	hint_range(0.0, 1.0) = 0.92;

uniform float specular :
	hint_range(0.0, 1.0) = 0.15;


void fragment() {
	vec4 asphalt_color = asphalt_tint;

	if (use_asphalt_texture) {
		asphalt_color *= texture(
			asphalt_texture,
			UV
		);
	}

	// UV.x is 0 at one road edge and 1 at the other.
	float distance_from_edge = min(
		UV.x,
		1.0 - UV.x
	);

	// Only a narrow section at each edge fades.
	float edge_alpha = smoothstep(
		0.0,
		edge_fade_width,
		distance_from_edge
	);

	ALBEDO = asphalt_color.rgb;
	ROUGHNESS = roughness;
	SPECULAR = specular;
	ALPHA = asphalt_color.a * edge_alpha;
}