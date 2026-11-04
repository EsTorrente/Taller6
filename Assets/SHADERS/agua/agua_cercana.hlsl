// Geometry for the agua_cercana graph: rippled sky and scene reflection, grazing amount, distance haze and edge fade
#ifndef AGUA_CERCANA_INCLUDED
#define AGUA_CERCANA_INCLUDED

#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareDepthTexture.hlsl"
#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DeclareOpaqueTexture.hlsl"

float3 aguaHash(float3 p)
{
    p = frac(p * float3(0.1031, 0.1030, 0.0973));
    p += dot(p, p.yxz + 33.33);
    return frac((p.xxy + p.yxx) * p.zyx) * 2 - 1;
}

float aguaNoise(float3 p)
{
    float3 i = floor(p);
    float3 f = frac(p);
    float3 u = f * f * (3 - 2 * f);
    return lerp(lerp(lerp(dot(aguaHash(i), f), dot(aguaHash(i + float3(1, 0, 0)), f - float3(1, 0, 0)), u.x),
                     lerp(dot(aguaHash(i + float3(0, 1, 0)), f - float3(0, 1, 0)), dot(aguaHash(i + float3(1, 1, 0)), f - float3(1, 1, 0)), u.x), u.y),
                lerp(lerp(dot(aguaHash(i + float3(0, 0, 1)), f - float3(0, 0, 1)), dot(aguaHash(i + float3(1, 0, 1)), f - float3(1, 0, 1)), u.x),
                     lerp(dot(aguaHash(i + float3(0, 1, 1)), f - float3(0, 1, 1)), dot(aguaHash(i + float3(1, 1, 1)), f - float3(1, 1, 1)), u.x), u.y), u.z) * 0.5 + 0.5;
}

void AguaCercana_float(float3 PositionWS, float3 NormalWS, float4 SkyFallback, float RippleScale, float RippleStrength,
                       float FadeStart, float FadeEnd, float RippleSpeed, float SceneReflection,
                       float SceneReflectionDistance, out float3 Sky, out float Grazing, out float Haze, out float Edge)
{
    float3 toCam = _WorldSpaceCameraPos - PositionWS;
    float dist = length(toCam);
    float3 V = toCam / max(dist, 1e-4);
    float3 N = normalize(NormalWS);

    // ripples: two layers drifting in different directions while their shape changes over time (noise y = time)
    float t = _TimeParameters.x * RippleSpeed;
    float3 p = float3(PositionWS.x, 0, PositionWS.z) * RippleScale;
    float3 a = p + float3(t * 0.6, t * 0.5, t * 0.3);
    float3 b = p * 1.7 + float3(-t * 0.4, -t * 0.5, -t * 0.7);
    float h = aguaNoise(a) + aguaNoise(b) * 0.5;
    float hx = aguaNoise(a + float3(0.15, 0, 0)) + aguaNoise(b + float3(0.255, 0, 0)) * 0.5;
    float hz = aguaNoise(a + float3(0, 0, 0.15)) + aguaNoise(b + float3(0, 0, 0.255)) * 0.5;
    float2 grad = float2(hx - h, hz - h) / (0.15 * 1.5);
    float3 Nb = normalize(N - RippleStrength * float3(grad.x, 0, grad.y));

    // sky: read the reflected direction straight off the screen, where the skybox (video included) was just drawn,
    // so the water always mirrors the sky as it is right now. Where that bit of sky is off screen or hidden behind
    // something, use Sky Fallback Color instead.
    float3 R = reflect(-V, Nb);
    Sky = SkyFallback.rgb;
    float4 skyClip = TransformWorldToHClip(_WorldSpaceCameraPos + R * 1000);
    if (skyClip.w > 0)
    {
        float4 skyScreen = ComputeScreenPos(skyClip);
        float2 skyUV = skyScreen.xy / skyScreen.w;
        if (all(skyUV >= 0) && all(skyUV <= 1))
        {
            float raw = SAMPLE_TEXTURE2D_X_LOD(_CameraDepthTexture, sampler_CameraDepthTexture, UnityStereoTransformScreenSpaceTex(skyUV), 0).r;
            #if UNITY_REVERSED_Z
            bool open = raw < 1e-5;
            #else
            bool open = raw > 1 - 1e-5;
            #endif
            if (open)
            {
                float2 border = min(skyUV, 1 - skyUV);
                float3 seen = SAMPLE_TEXTURE2D_X_LOD(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, UnityStereoTransformScreenSpaceTex(skyUV), 0).rgb;
                Sky = lerp(SkyFallback.rgb, seen, saturate(min(border.x, border.y) * 8));
            }
        }
    }

    // what's around the water: follow the reflected ray a few steps through the depth texture and, where it goes
    // behind something, take that pixel's colour. Uses textures URP already makes, so no extra camera or pass.
    if (SceneReflection > 0)
    {
        const int steps = 10;
        float hit = 0;
        float2 hitUV = 0;
        [loop] for (int i = 1; i <= steps; i++)
        {
            float along = SceneReflectionDistance * (i * i) / (float)(steps * steps);
            float4 hcs = TransformWorldToHClip(PositionWS + R * along);
            if (hcs.w <= 0) break;
            float4 screen = ComputeScreenPos(hcs);
            float2 suv = screen.xy / screen.w;
            if (any(suv < 0) || any(suv > 1)) break;
            float raw = SAMPLE_TEXTURE2D_X_LOD(_CameraDepthTexture, sampler_CameraDepthTexture, UnityStereoTransformScreenSpaceTex(suv), 0).r;
            float sceneEye = LinearEyeDepth(raw, _ZBufferParams);
            float thickness = max(0.3, SceneReflectionDistance * (2 * i + 1) / (float)(steps * steps));
            if (hcs.w > sceneEye && hcs.w - sceneEye < thickness)
            {
                float2 border = min(suv, 1 - suv);
                hit = saturate(min(border.x, border.y) * 10) * (1 - 0.5 * along / SceneReflectionDistance);
                hitUV = suv;
                break;
            }
        }
        float3 scene = SAMPLE_TEXTURE2D_X_LOD(_CameraOpaqueTexture, sampler_CameraOpaqueTexture, UnityStereoTransformScreenSpaceTex(hitUV), 0).rgb;
        Sky = lerp(Sky, scene, hit * SceneReflection);
    }

    // Blender Layer Weight > Facing with blend 0.7
    Grazing = 1 - pow(abs(dot(N, V)), 1.667);

    // haze from 20 m on
    Haze = 1 - exp(-max(dist - 20, 0) / 160);

    // noisy fade at the edge of the water
    float3 c = UNITY_MATRIX_M._m03_m13_m23;
    float r = length(PositionWS.xz - c.xz) + aguaNoise(PositionWS * 0.06) * 12 - 6;
    Edge = 1 - smoothstep(FadeStart, FadeEnd, r);
}

// Rings from WaterRipples.cs: each grows from its centre to the ripple size over its life and fades out
#define WATER_MAX_RIPPLES 32
float4 _WaterRipples[WATER_MAX_RIPPLES]; // xy: centre (world XZ), z: age 0..1, w: random seed
float _WaterRippleCount;
float _WaterRippleSize;
float _WaterRippleWidth;

// Rings on the surface where something goes through the water, drawn as crisp lines in the contact colour.
// Each ring is wobbly, uneven and broken in places, so none of them are perfect circles.
void AguaContacto_float(float3 PositionWS, float3 ColorIn, float AlphaIn, float4 ContactColor, float ContactAmount,
                        out float3 Color, out float Alpha)
{
    float rings = 0;
    float width = max(_WaterRippleWidth, 1e-3);
    [loop] for (int i = 0; i < min((int)_WaterRippleCount, WATER_MAX_RIPPLES); i++)
    {
        float4 r = _WaterRipples[i];
        float2 offset = PositionWS.xz - r.xy;
        float d = length(offset);
        if (d > _WaterRippleSize * 1.3 + width) continue;
        // noise around the ring (on the unit circle, so there is no seam)
        float2 around = offset / max(d, 1e-4);
        float shape = aguaNoise(float3(around * 2.3, r.w));
        float thick = aguaNoise(float3(around * 3.1, r.w + 7.3 + r.z));
        float gaps = aguaNoise(float3(around * 3.0, r.w + 13.1));
        float radius = r.z * _WaterRippleSize * (0.7 + 0.6 * shape);
        float w = width * (0.2 + 1.6 * thick) * (1 - 0.5 * r.z);
        float ring = 1 - smoothstep(0.6 * w, w, abs(d - radius));
        ring *= smoothstep(0.34, 0.46, gaps);
        rings = max(rings, ring * (1 - r.z * r.z));
    }
    float crest = rings * ContactAmount;

    Color = lerp(ColorIn, ContactColor.rgb, crest);
    Alpha = lerp(AlphaIn, 1, crest);
}

#endif
