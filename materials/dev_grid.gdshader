shader_type spatial;

uniform vec3 color_dark : source_color = vec3(0.24, 0.25, 0.27);
uniform vec3 color_light : source_color = vec3(0.32, 0.33, 0.35);
uniform vec3 line_color : source_color = vec3(0.55, 0.58, 0.62);
uniform float cell_size = 1.0;
uniform float line_px = 1.5;

varying vec3 world_pos;
varying vec3 world_normal;

void vertex() {
	world_pos = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
	world_normal = normalize(mat3(MODEL_MATRIX) * NORMAL);
}

void fragment() {
	vec3 n = abs(world_normal);
	vec2 uv;
	if (n.y >= n.x && n.y >= n.z) {
		uv = world_pos.xz;
	} else if (n.x >= n.z) {
		uv = world_pos.zy;
	} else {
		uv = world_pos.xy;
	}

	vec2 cell = uv / cell_size;

	vec2 id = floor(cell);
	float checker = mod(id.x + id.y, 2.0);
	vec3 base = mix(color_dark, color_light, checker);

	vec2 g = abs(fract(cell - 0.5) - 0.5) / (fwidth(cell) * line_px);
	float line = 1.0 - min(min(g.x, g.y), 1.0);

	ALBEDO = mix(base, line_color, line);
	ROUGHNESS = 0.85;
	SPECULAR = 0.2;
}