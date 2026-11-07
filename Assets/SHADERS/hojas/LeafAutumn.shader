// Autumn leaves (Tree_LOD_3): a port of the Blender "leaf autumn" material.
// Leaf image -> Color blend with an orange/gold ramp driven by Blender's own noise on the tree's
// Generated coordinates, then the same emission / principled / translucent mix as the node tree.
// Property defaults are the Blender values, so they can be compared 1:1 with the .blend.
//
// Standalone-VR (Quest) optimised version:
//  - Wind sway/flutter in the vertex shader (2-3 sin per vertex, uniform-branched off when amplitudes are 0).
//  - Autumn colour (noise + ramp + HSV) fully evaluated per vertex; the fragment only multiplies by the leaf's max channel.
//  - Lighting (SH ambient, main light, additional lights, translucency, emission mix) evaluated per vertex and
//    folded into two colours (front face / back face). The fragment picks one by facing.
//    Main-light shadows (if enabled in the pipeline) are the only per-pixel lighting work left.
//  - Branchless colour ramp, half precision interpolants, optional alpha-to-coverage instead of discard.
Shader "ESCENA67/LeafAutumn"
{
    Properties
    {
        [Header(Leaf)] _BaseMap ("Leaf Texture", 2D) = "white" {}
        [HideInInspector] [ToggleUI] _UseUV2 ("Use Second UV Map (UVMap.001)", Float) = 1
        [HideInInspector] _UVLocation ("UV Location", Vector) = (0.46, -0.34, 0, 0)
        [HideInInspector] _UVRotation ("UV Rotation Z (radians)", Float) = 0.7208
        [HideInInspector] _UVScale ("UV Scale", Float) = 1.27
        [HideInInspector] _Cutoff ("Alpha Cutoff", Range(0, 1)) = 0.5
        [Toggle(_ALPHA_TO_COVERAGE)] _AlphaToCoverage ("Alpha To Coverage (needs MSAA, avoids discard)", Float) = 0

        [HideInInspector] _NoiseScale ("Noise Scale", Float) = 20
        [HideInInspector] _NoiseRoughness ("Noise Roughness", Range(0, 1)) = 0.25
        [HideInInspector] _GenMin ("Tree Bounds Min (Blender axes)", Vector) = (-3.349, -2.675, 0, 0)
        [HideInInspector] _GenSize ("Tree Bounds Size (Blender axes)", Vector) = (8.284, 5.682, 9.544, 0)
        [Header(Autumn Colours)] _Ramp0 ("Ramp Color 1", Color) = (1, 0.5667, 0, 1)
        _Ramp1 ("Ramp Color 2", Color) = (1, 0.6106, 0, 1)
        _Ramp2 ("Ramp Color 3", Color) = (1, 0.9177, 0.3895, 1)
        _Ramp3 ("Ramp Color 4", Color) = (1, 0.9482, 0.1572, 1)
        [HideInInspector] _RampPositions ("Ramp Positions", Vector) = (0, 0.0643, 0.4056, 1)

        _EmissionStrength ("Emission Strength", Float) = 11.027
        [HideInInspector] _SurfaceMix ("Emission -> Surface Mix", Range(0, 1)) = 0.5333
        [HideInInspector] _TranslucentMix ("Principled -> Translucent Mix", Range(0, 1)) = 0.2583
        [HideInInspector] _TranslucentValue ("Translucent Brightness", Float) = 2
        [HideInInspector] _Roughness ("Roughness (unused, kept for compatibility)", Range(0, 1)) = 0.5528

        [Header(Wind)] _SwayAmount ("Sway Amplitude (m, 0 = wind off)", Float) = 0.05
        _SwaySpeed ("Sway Speed", Float) = 1.2
        _SwayScale ("Sway Wave Scale", Float) = 0.4
        _FlutterAmount ("Flutter Amplitude (m)", Float) = 0.015
        _FlutterSpeed ("Flutter Speed", Float) = 4
        _WindDir ("Wind Direction (world XYZ)", Vector) = (1, 0.15, 0.3, 0)
    }
    SubShader
    {
        Tags { "RenderType"="TransparentCutout" "Queue"="AlphaTest" "RenderPipeline"="UniversalPipeline" }
        Cull Off

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"

        // Uncomment to skip the second noise octave (roughness term): saves half of the per-vertex noise cost,
        // colour pattern becomes slightly smoother than Blender's.
        // #define LEAF_NOISE_SINGLE_OCTAVE

        TEXTURE2D(_BaseMap);
        SAMPLER(sampler_BaseMap);

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            float _UseUV2;
            float4 _UVLocation;
            float _UVRotation;
            float _UVScale;
            float _Cutoff;
            float _NoiseScale;
            float _NoiseRoughness;
            float4 _GenMin;
            float4 _GenSize;
            float4 _Ramp0, _Ramp1, _Ramp2, _Ramp3;
            float4 _RampPositions;
            float _EmissionStrength;
            float _SurfaceMix;
            float _TranslucentMix;
            float _TranslucentValue;
            float _Roughness;
            float _SwayAmount;
            float _SwaySpeed;
            float _SwayScale;
            float _FlutterAmount;
            float _FlutterSpeed;
            float4 _WindDir;
        CBUFFER_END

        // Blender Mapping node (Point): scale, rotate around Z, then move. The image uses Clip extension,
        // so anything outside 0..1 is fully transparent.
        float2 LeafUV(float2 uv0, float2 uv1)
        {
            float2 uv = lerp(uv0, uv1, _UseUV2) * _UVScale;
            float s, c;
            sincos(_UVRotation, s, c);
            return float2(uv.x * c - uv.y * s, uv.x * s + uv.y * c) + _UVLocation.xy;
        }

        // uv comes from LeafUV in the vertex shader (affine, so interpolating it is exact)
        half4 LeafSample(float2 uv)
        {
            half4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv);
            return all(uv == saturate(uv)) ? tex : 0;
        }

        // ---------------------------------------------------------------------------------------------
        // Wind. Returns a world-space offset. Height weight reuses the tree bounds, so upper leaves move
        // more and the trunk-side ones stay put (no extra mesh data needed). Evaluated in world space,
        // so object scale / rotation / static batching don't matter.
        // ---------------------------------------------------------------------------------------------
        float3 LeafSway(float3 posOS, float3 posWS, float3 nWS)
        {
            // Uniform branch: whole material skips the wind maths when both amplitudes are 0.
            if (_SwayAmount + _FlutterAmount <= 0.0) return 0;

            float h = saturate((posOS.z - _GenMin.z) / _GenSize.z);
            h *= h;

            float t = _Time.y;
            float phase = dot(posWS.xz, float2(1.0, 0.7)) * _SwayScale;
            float ts = t * _SwaySpeed + phase;
            float sway = sin(ts) + 0.5 * sin(ts * 2.3 + phase * 0.7);
            float flutter = sin(t * _FlutterSpeed + dot(posOS, float3(12.9, 78.2, 37.7)));

            return _WindDir.xyz * (sway * _SwayAmount * h)
                 + nWS * (flutter * _FlutterAmount * h);
        }

        // ---------------------------------------------------------------------------------------------
        // Cycles' perlin noise (hash, gradients and scale copied from Blender), so the pattern matches
        // ---------------------------------------------------------------------------------------------
        uint LeafRot(uint x, uint k) { return (x << k) | (x >> (32u - k)); }

        uint LeafHash(uint kx, uint ky, uint kz)
        {
            uint a, b, c;
            a = b = c = 0xdeadbeefu + (3u << 2u) + 13u;
            c += kz; b += ky; a += kx;
            c ^= b; c -= LeafRot(b, 14u);
            a ^= c; a -= LeafRot(c, 11u);
            b ^= a; b -= LeafRot(a, 25u);
            c ^= b; c -= LeafRot(b, 16u);
            a ^= c; a -= LeafRot(c, 4u);
            b ^= a; b -= LeafRot(a, 14u);
            c ^= b; c -= LeafRot(b, 24u);
            return c;
        }

        float LeafGrad(uint h, float3 f)
        {
            h &= 15u;
            float u = h < 8u ? f.x : f.y;
            float vt = (h == 12u || h == 14u) ? f.x : f.z;
            float v = h < 4u ? f.y : vt;
            return ((h & 1u) != 0u ? -u : u) + ((h & 2u) != 0u ? -v : v);
        }

        float LeafPerlin(float3 p)
        {
            float3 i = floor(p);
            float3 f = p - i;
            uint3 n = (uint3)(int3)i;
            float3 w = f * f * f * (f * (f * 6 - 15) + 10);
            float v000 = LeafGrad(LeafHash(n.x, n.y, n.z), f);
            float v100 = LeafGrad(LeafHash(n.x + 1u, n.y, n.z), f - float3(1, 0, 0));
            float v010 = LeafGrad(LeafHash(n.x, n.y + 1u, n.z), f - float3(0, 1, 0));
            float v110 = LeafGrad(LeafHash(n.x + 1u, n.y + 1u, n.z), f - float3(1, 1, 0));
            float v001 = LeafGrad(LeafHash(n.x, n.y, n.z + 1u), f - float3(0, 0, 1));
            float v101 = LeafGrad(LeafHash(n.x + 1u, n.y, n.z + 1u), f - float3(1, 0, 1));
            float v011 = LeafGrad(LeafHash(n.x, n.y + 1u, n.z + 1u), f - float3(0, 1, 1));
            float v111 = LeafGrad(LeafHash(n.x + 1u, n.y + 1u, n.z + 1u), f - float3(1, 1, 1));
            return 0.982 * lerp(lerp(lerp(v000, v100, w.x), lerp(v010, v110, w.x), w.y),
                                lerp(lerp(v001, v101, w.x), lerp(v011, v111, w.x), w.y), w.z);
        }

        // Branchless 4-stop colour ramp (identical result to the if/else chain: each lerp saturates
        // to 0 before its segment and to 1 after it).
        float3 LeafRamp(float f)
        {
            float4 p = _RampPositions;
            float3 c = lerp(_Ramp0.rgb, _Ramp1.rgb, saturate((f - p.x) / max(p.y - p.x, 1e-5)));
            c = lerp(c, _Ramp2.rgb, saturate((f - p.y) / max(p.z - p.y, 1e-5)));
            c = lerp(c, _Ramp3.rgb, saturate((f - p.z) / max(p.w - p.z, 1e-5)));
            return c;
        }

        // Blender noise (FBM, detail 1, not normalized) on Generated coordinates -> ramp -> hue/saturation.
        // Returned as RGB with V = 1: HsvToRgb is linear in V, so the fragment only has to multiply this by
        // the leaf texture's max channel to get exactly HsvToRgb(h, s, max(leaf.rgb)).
        // Always called with the UNDISPLACED object-space position, so the colours never swim with the wind.
        half3 LeafTint(float3 positionOS)
        {
            float3 gen = (float3(-positionOS.x, positionOS.y, positionOS.z) - _GenMin.xyz) / _GenSize.xyz;
            float3 q = gen * _NoiseScale;
            float fac = LeafPerlin(q);
            #if !defined(LEAF_NOISE_SINGLE_OCTAVE)
            fac += _NoiseRoughness * LeafPerlin(q * 2);
            #endif
            float2 hs = RgbToHsv(LeafRamp(fac)).xy;
            return (half3)HsvToRgb(float3(hs, 1));
        }
        ENDHLSL

        Pass
        {
            Name "Forward"
            Tags { "LightMode"="UniversalForward" }
            AlphaToMask [_AlphaToCoverage]

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma multi_compile_fog
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma shader_feature_local_fragment _ALPHA_TO_COVERAGE
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // The main-light shadow is the only lighting term that must stay per pixel.
            #if defined(_MAIN_LIGHT_SHADOWS) || defined(_MAIN_LIGHT_SHADOWS_CASCADE)
            #define LEAF_FRAG_SHADOW
            #endif

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float2 uv0 : TEXCOORD0;
                float2 uv1 : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                half3 lightFront : TEXCOORD1;   // tint * (emission + ambient + lights), front-facing pixels
                half3 lightBack : TEXCOORD2;    // same for back-facing pixels
                half fogCoord : TEXCOORD3;
                #if defined(LEAF_FRAG_SHADOW)
                half3 mainFront : TEXCOORD4;    // main-light part only (needs shadow attenuation per pixel)
                half3 mainBack : TEXCOORD5;
                float3 positionWS : TEXCOORD6;
                #endif
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                float3 nWS = TransformObjectToWorldNormal(v.normalOS);
                float3 posWS = TransformObjectToWorld(v.positionOS.xyz);
                posWS += LeafSway(v.positionOS.xyz, posWS, nWS);
                o.positionCS = TransformWorldToHClip(posWS);
                o.uv = LeafUV(v.uv0, v.uv1);
                o.fogCoord = ComputeFogFactor(o.positionCS.z);

                half3 tint = LeafTint(v.positionOS.xyz);
                half3 N = (half3)nWS;

                // Lambert front (principled) and back (translucent) light. Emission dominates this material,
                // so full PBR specular isn't worth its cost on Quest.
                Light mainLight = GetMainLight();
                half nl = dot(N, mainLight.direction);
                half3 mainF = mainLight.color * saturate(nl);
                half3 mainB = mainLight.color * saturate(-nl);

                half3 ambF = SampleSH(N);
                half3 ambB = SampleSH(-N);
                #if defined(_ADDITIONAL_LIGHTS) || defined(_ADDITIONAL_LIGHTS_VERTEX)
                {
                    uint lightCount = GetAdditionalLightsCount();
                    for (uint li = 0u; li < lightCount; ++li)
                    {
                        Light l = GetAdditionalLight(li, posWS);
                        half3 lc = l.color * l.distanceAttenuation;
                        half ln = dot(N, l.direction);
                        ambF += lc * saturate(ln);
                        ambB += lc * saturate(-ln);
                    }
                }
                #endif

                // lerp(Emission, lerp(front, back * T, translucentMix), surfaceMix), written out per face:
                // a back-facing pixel sees the flipped normal, so its "front" is our back and vice versa.
                half mix = (half)_SurfaceMix;
                half tm = (half)_TranslucentMix;
                half tv = (half)_TranslucentValue;
                half emis = (half)_EmissionStrength * (1.0h - mix);

                half3 aF = lerp(ambF, ambB * tv, tm) * mix + emis;
                half3 aB = lerp(ambB, ambF * tv, tm) * mix + emis;
                half3 mF = lerp(mainF, mainB * tv, tm) * mix;
                half3 mB = lerp(mainB, mainF * tv, tm) * mix;

                #if defined(LEAF_FRAG_SHADOW)
                o.lightFront = tint * aF;
                o.lightBack = tint * aB;
                o.mainFront = tint * mF;
                o.mainBack = tint * mB;
                o.positionWS = posWS;
                #else
                o.lightFront = tint * (aF + mF);
                o.lightBack = tint * (aB + mB);
                #endif
                return o;
            }

            half4 frag(Varyings i, FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                half4 leaf = LeafSample(i.uv);

                half alpha = 1.0h;
                #if defined(_ALPHA_TO_COVERAGE)
                alpha = saturate((leaf.a - (half)_Cutoff) / max(fwidth(leaf.a), 1e-4h) + 0.5h);
                #else
                clip(leaf.a - _Cutoff);
                #endif

                half3 light = IS_FRONT_VFACE(frontFace, i.lightFront, i.lightBack);
                #if defined(LEAF_FRAG_SHADOW)
                half shadow = GetMainLight(TransformWorldToShadowCoord(i.positionWS)).shadowAttenuation;
                light += IS_FRONT_VFACE(frontFace, i.mainFront, i.mainBack) * shadow;
                #endif

                half3 color = light * max(leaf.r, max(leaf.g, leaf.b));
                return half4(MixFog(color, i.fogCoord), alpha);
            }
            ENDHLSL
        }

        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ColorMask 0

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv0 : TEXCOORD0; float2 uv1 : TEXCOORD1; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                float3 posWS = TransformObjectToWorld(v.positionOS.xyz);
                float3 nWS = TransformObjectToWorldNormal(v.normalOS);
                posWS += LeafSway(v.positionOS.xyz, posWS, nWS);   // keep shadows in sync with the wind
                #if defined(_CASTING_PUNCTUAL_LIGHT_SHADOW)
                float3 lightDir = normalize(_LightPosition - posWS);
                #else
                float3 lightDir = _LightDirection;
                #endif
                o.positionCS = TransformWorldToHClip(ApplyShadowBias(posWS, nWS, lightDir));
                #if UNITY_REVERSED_Z
                o.positionCS.z = min(o.positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                o.positionCS.z = max(o.positionCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif
                o.uv = LeafUV(v.uv0, v.uv1);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                clip(LeafSample(i.uv).a - _Cutoff);
                return 0;
            }
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ColorMask R

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            struct Attributes { float4 positionOS : POSITION; float3 normalOS : NORMAL; float2 uv0 : TEXCOORD0; float2 uv1 : TEXCOORD1; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; UNITY_VERTEX_OUTPUT_STEREO };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                float3 posWS = TransformObjectToWorld(v.positionOS.xyz);
                posWS += LeafSway(v.positionOS.xyz, posWS, TransformObjectToWorldNormal(v.normalOS));
                o.positionCS = TransformWorldToHClip(posWS);
                o.uv = LeafUV(v.uv0, v.uv1);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                clip(LeafSample(i.uv).a - _Cutoff);
                return 0;
            }
            ENDHLSL
        }
    }
}
