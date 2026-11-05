// Material fields of the magic dissolve. Put MAGIC_DISSOLVE_CBUFFER inside every pass's UnityPerMaterial
// block, then include MagicDissolve.hlsl after it.
#ifndef MAGIC_DISSOLVE_INPUT_INCLUDED
#define MAGIC_DISSOLVE_INPUT_INCLUDED

// Blender frame, set every frame by MagicDissolveDriver
float _MagicFrame;

// _MagicWorldToObject, _MagicMapOffset and _MagicGradientOffset are set per renderer by MagicDissolveDriver
#define MAGIC_DISSOLVE_CBUFFER \
    float4x4 _MagicWorldToObject; \
    float4 _MagicMapOffset; \
    float _MagicGradientOffset; \
    float4 _MagicMapLocation; \
    float4 _MagicMapRotation; \
    float4 _MagicMapScale; \
    float _MagicNoiseMix; \
    float _MagicNoiseScale; \
    float _MagicNoiseDetail; \
    float _MagicNoiseRoughness; \
    float _MagicNoiseW; \
    float _MagicNoiseWPerFrame; \
    float4 _MagicCut; \
    float4 _MagicEdge; \
    float4 _MagicGlowColorA; \
    float4 _MagicGlowColorB; \
    float4 _MagicGlowColorRamp; \
    float _MagicGlowNoiseScale; \
    float _MagicGlowNoiseDetail; \
    float _MagicSparkleScale; \
    float _MagicSparkleDetail; \
    float _MagicSparkleW; \
    float _MagicSparkleWPerFrame; \
    float4 _MagicSparkleRamp; \
    float _MagicGlowStrength;

#endif