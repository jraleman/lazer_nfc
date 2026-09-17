shader_type canvas_item;

// The lab after hours: dark enough for the shell's fixed cream labels.
// The generic GameTheme clock multiplies every moving term; speed=0 is a still.
uniform vec4 top_color : source_color = vec4(0.082, 0.176, 0.224, 1.0);
uniform vec4 bottom_color : source_color = vec4(0.031, 0.075, 0.118, 1.0);
uniform vec4 glow_color : source_color = vec4(0.486, 0.902, 0.824, 1.0);
uniform vec2 aspect = vec2(1.0);
uniform float speed : hint_range(0.0, 1.0) = 0.07;

float capsule(vec2 p, vec2 center, vec2 direction, float reach, float radius) {
	vec2 relative = p - center;
	float along = clamp(dot(relative, direction), -reach, reach);
	return length(relative - direction * along) - radius;
}

void fragment() {
	vec2 p = (UV - vec2(0.5)) * aspect;
	float t = TIME * speed;
	vec3 colour = mix(top_color.rgb, bottom_color.rgb, smoothstep(0.0, 1.0, UV.y));
	float edge = smoothstep(0.16, 0.76, length(p * vec2(1.0, 0.72)));

	vec2 grid = abs(fract(p * 12.0 + 0.5) - 0.5);
	vec2 aa = max(fwidth(p * 12.0), vec2(0.001));
	vec2 lines = vec2(1.0) - smoothstep(vec2(0.006), aa * 1.1 + vec2(0.006), grid);
	colour += glow_color.rgb * max(lines.x, lines.y) * (0.018 + edge * 0.012);

	// Enamel sample capsules sit around, rather than behind, the reading column.
	for (int i = 0; i < 5; i++) {
		float index = float(i);
		float side = mod(index, 2.0) < 1.0 ? -1.0 : 1.0;
		vec2 center = vec2(side * (0.49 + mod(index, 3.0) * 0.09),
			-0.35 + index * 0.18);
		center.y += sin(t * 0.42 + index * 2.1) * 0.009;
		float angle = side * 0.51 + sin(t * 0.23 + index) * 0.015;
		vec2 direction = vec2(cos(angle), sin(angle));
		float distance = capsule(p, center, direction, 0.060, 0.028);
		float body = 1.0 - smoothstep(-0.001, 0.003, distance);
		float rim = (1.0 - smoothstep(0.002, 0.005, abs(distance))) * edge;
		vec3 paint = mod(index, 3.0) < 1.0 ? vec3(0.92, 0.57, 0.48)
			: (mod(index, 3.0) < 2.0 ? glow_color.rgb : vec3(0.90, 0.74, 0.43));
		colour = mix(colour, paint * 0.22, body * edge * 0.68);
		colour += paint * rim * 0.10;
		float slot = 1.0 - smoothstep(0.001, 0.003,
			abs(dot(p - center, direction)));
		colour += vec3(0.75, 0.89, 0.81) * slot * body * edge * 0.045;
	}

	vec2 lamp = p - vec2(0.37 + sin(t * 0.19) * 0.014, -0.23);
	colour += glow_color.rgb * exp(-dot(lamp, lamp) * 7.0) * 0.039;
	vec2 warmth = p - vec2(-0.45, 0.34);
	colour += vec3(0.92, 0.55, 0.40) * exp(-dot(warmth, warmth) * 15.0) * 0.028;
	float vignette = 1.0 - smoothstep(0.18, 1.05, length(p)) * 0.26;
	COLOR = vec4(colour * vignette, 1.0);
}
