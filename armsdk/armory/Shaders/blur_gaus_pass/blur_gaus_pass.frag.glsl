// Exclusive to bloom for now
#version 450

#include "compiled.inc"

uniform sampler2D tex;
uniform vec2 dir;
uniform vec2 screenSize;
uniform mat4 PPMComp2;

in vec2 texCoord;
out vec4 fragColor;

const float weight[10] = float[] (0.132572, 0.125472, 0.106373, 0.08078, 0.05495, 0.033482, 0.018275, 0.008934, 0.003912, 0.001535);

void main() {
	#ifdef _CPPM
		vec2 step = (dir / screenSize.xy) * PPMComp2[1].w;
	#else
		vec2 step = (dir / screenSize.xy) * bloomRadius;
	#endif

	fragColor.rgb = textureLod(tex, texCoord, 0.0).rgb * weight[0];
	for (int i = 1; i < 10; i++) {
		vec2 s = step * (float(i) + 0.5);
		fragColor.rgb += textureLod(tex, texCoord + s, 0.0).rgb * weight[i];
		fragColor.rgb += textureLod(tex, texCoord - s, 0.0).rgb * weight[i];
	}
	
	#ifdef _CPPM
		fragColor.rgb *= PPMComp2[1].z / 5;
	#else
		fragColor.rgb *= bloomStrength / 5;
	#endif
	fragColor.rgb = min(fragColor.rgb, 64.0);
}
