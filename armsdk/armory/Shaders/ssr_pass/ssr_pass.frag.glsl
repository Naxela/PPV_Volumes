#version 450

#include "compiled.inc"
#include "std/math.glsl"
#include "std/gbuffer.glsl"

uniform sampler2D tex;
uniform sampler2D gbufferD;
uniform sampler2D gbuffer0; // Normal, roughness
uniform sampler2D gbuffer1; // basecol, spec
uniform mat4 P;
uniform mat3 V3;
uniform vec2 cameraProj;

uniform mat4 PPMComp2;

in vec3 viewRay;
in vec2 texCoord;
out vec4 fragColor;

vec3 hitCoord;
float depth;

const int numBinarySearchSteps = 7;
const int maxSteps = 18;

vec2 getProjectedCoord(const vec3 hit) {
	vec4 projectedCoord = P * vec4(hit, 1.0);
	projectedCoord.xy /= projectedCoord.w;
	projectedCoord.xy = projectedCoord.xy * 0.5 + 0.5;
	#ifdef HLSL
	projectedCoord.y = 1.0 - projectedCoord.y;
	#endif
	return projectedCoord.xy;
}

float getDeltaDepth(const vec3 hit) {	
	depth = textureLod(gbufferD, getProjectedCoord(hit), 0.0).r * 2.0 - 1.0;
	vec3 viewPos = getPosView(viewRay, depth, cameraProj);
	return viewPos.z - hit.z;
}

vec4 binarySearch(vec3 dir) {
	float ddepth;
	vec3 start = hitCoord;
	for (int i = 0; i < numBinarySearchSteps; i++) {
		dir *= 0.5;
		hitCoord -= dir;
		ddepth = getDeltaDepth(hitCoord);
		if (ddepth < 0.0) hitCoord += dir;
	}
	// Ugly discard of hits too far away
	#ifdef _CPPM
		if (abs(ddepth) > PPMComp2[0].z / 500) return vec4(0.0);
	#else
		if (abs(ddepth) > ssrSearchDist / 500) return vec4(0.0);
	#endif
	return vec4(getProjectedCoord(hitCoord), 0.0, 1.0);
}

vec4 rayCast(vec3 dir) {
	#ifdef _CPPM
		dir *= PPMComp2[0].x;
	#else
		dir *= ssrRayStep;
	#endif
	for (int i = 0; i < maxSteps; i++) {
		hitCoord += dir;
		if (getDeltaDepth(hitCoord) > 0.0) return binarySearch(dir);
	}
	return vec4(0.0);
}

void main() {
	vec4 g0 = textureLod(gbuffer0, texCoord, 0.0);
	float roughness = unpackFloat(g0.b).y;
	if (roughness == 1.0) { fragColor.rgb = vec3(0.0); return; }

	float spec = fract(textureLod(gbuffer1, texCoord, 0.0).a);
	if (spec == 0.0) { fragColor.rgb = vec3(0.0); return; }
	
	float d = textureLod(gbufferD, texCoord, 0.0).r * 2.0 - 1.0;
	if (d == 1.0) { fragColor.rgb = vec3(0.0); return; }

	vec2 enc = g0.rg;
	vec3 n;
	n.z = 1.0 - abs(enc.x) - abs(enc.y);
	n.xy = n.z >= 0.0 ? enc.xy : octahedronWrap(enc.xy);
	n = normalize(n);
	
	vec3 viewNormal = V3 * n;
	vec3 viewPos = getPosView(viewRay, d, cameraProj);
	vec3 reflected = normalize(reflect(viewPos, viewNormal));
	hitCoord = viewPos;
	
	#ifdef _CPPM 
		vec3 dir = reflected * (1.0 - rand(texCoord) * PPMComp2[1].x * roughness) * 2.0;
	#else
		vec3 dir = reflected * (1.0 - rand(texCoord) * ssrJitter * roughness) * 2.0;
	#endif
	
	// * max(ssrMinRayStep, -viewPos.z)
	vec4 coords = rayCast(dir);

	vec2 deltaCoords = abs(vec2(0.5, 0.5) - coords.xy);
	float screenEdgeFactor = clamp(1.0 - (deltaCoords.x + deltaCoords.y), 0.0, 1.0);

	float reflectivity = 1.0 - roughness;
	#ifdef _CPPM
		float intensity = pow(reflectivity, PPMComp2[0].w) * screenEdgeFactor * clamp(-reflected.z, 0.0, 1.0) * clamp((PPMComp2[0].z - length(viewPos - hitCoord)) * (1.0 / PPMComp2[0].z), 0.0, 1.0) * coords.w;
	#else
		float intensity = pow(reflectivity, ssrFalloffExp) * screenEdgeFactor * clamp(-reflected.z, 0.0, 1.0) * clamp((ssrSearchDist - length(viewPos - hitCoord)) * (1.0 / ssrSearchDist), 0.0, 1.0) * coords.w;
	#endif

	intensity = clamp(intensity, 0.0, 1.0);
	vec3 reflCol = textureLod(tex, coords.xy, 0.0).rgb;
	reflCol = clamp(reflCol, 0.0, 1.0);
	fragColor.rgb = reflCol * intensity * 0.5;
	
}
