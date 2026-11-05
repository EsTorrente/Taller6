// Autumn leaves (Tree_LOD_3): a port of the Blender "leaf autumn" material.
// Leaf image -> Color blend with an orange/gold ramp driven by Blender's own noise on the tree's
// Generated coordinates, then the same emission / principled / translucent mix as the node tree.
// Property defaults are the Blender values, so they can be compared 1:1 with the .blend.
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
        [HideInInspector] _Roughness ("Roughness", Range(0, 1)) = 0.5528
    }
    SubShader
    {
        Tags { "RenderType"="TransparentCutout" "Queue"="AlphaTest" "RenderPipeline"="UniversalPipeline" }
        Cull Off

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "Packages/com.unity.render-pipelines.core/ShaderLibrary/Color.hlsl"

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

        // Cycles' perlin noise (hash, gradients and scale copied from Blender), so the pattern matches
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

        float3 LeafRamp(float f)
        {
            float4 p = _RampPositions;
            if (f <= p.x) return _Ramp0.rgb;
            if (f <= p.y) return lerp(_Ramp0.rgb, _Ramp1.rgb, (f - p.x) / max(p.y - p.x, 1e-5));
            if (f <= p.z) return lerp(_Ramp1.rgb, _Ramp2.rgb, (f - p.y) / max(p.z - p.y, 1e-5));
            if (f <= p.w) return lerp(_Ramp2.rgb, _Ramp3.rgb, (f - p.z) / max(p.w - p.z, 1e-5));
            return _Ramp3.rgb;
        }

        // Blender noise (FBM, detail 1, not normalized) on Generated coordinates -> ramp -> Color blend
        float2 LeafHS(float3 positionOS)
        {
            float3 gen = (float3(-positionOS.x, positionOS.y, positionOS.z) - _GenMin.xyz) / _GenSize.xyz;
            float3 q = gen * _NoiseScale;
            float fac = LeafPerlin(q) + _NoiseRoughness * LeafPerlin(q * 2);
            return RgbToHsv(LeafRamp(fac)).xy;
        }

        half3 LeafColor(float2 hs, half3 leafRGB)
        {
            return HsvToRgb(float3(hs, max(leafRGB.r, max(leafRGB.g, leafRGB.b))));
        }
        ENDHLSL

        Pass
        {
            Name "Forward"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma multi_compile_fog
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _CLUSTER_LIGHT_LOOP
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // Enabled: computes the autumn colour (noise + ramp) per vertex instead of per pixel: much cheaper. Comment the define out for exact per-pixel colour.
            // Note:
            // but the colour variation is then interpolated between vertices (fine for small leaf cards, coarse for big meshes)
            #define LEAF_COLOR_PER_VERTEX

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
                float3 positionWS : TEXCOORD1;
                half3 normalWS : TEXCOORD2;
                #if defined(LEAF_COLOR_PER_VERTEX)
                float2 hs : TEXCOORD3;
                #else
                float3 positionOS : TEXCOORD3;
                #endif
                half fogCoord : TEXCOORD4;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                o.positionWS = TransformObjectToWorld(v.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(o.positionWS);
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                #if defined(LEAF_COLOR_PER_VERTEX)
                o.hs = LeafHS(v.positionOS.xyz);
                #else
                o.positionOS = v.positionOS.xyz;
                #endif
                o.uv = LeafUV(v.uv0, v.uv1);
                o.fogCoord = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            half4 frag(Varyings i, FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                half4 leaf = LeafSample(i.uv);
                clip(leaf.a - _Cutoff);
                #if defined(LEAF_COLOR_PER_VERTEX)
                half3 baseColor = LeafColor(i.hs, leaf.rgb);
                #else
                half3 baseColor = LeafColor(LeafHS(i.positionOS), leaf.rgb);
                #endif
                half3 n = normalize(IS_FRONT_VFACE(frontFace, i.normalWS, -i.normalWS));

                // Lambert front (principled) and back (translucent) light in one pass over the lights.
                // The emission term dominates this material, so full PBR specular isn't worth its cost on Quest.
                Light mainLight = GetMainLight(TransformWorldToShadowCoord(i.positionWS));
                half3 lightMain = mainLight.color * (mainLight.distanceAttenuation * mainLight.shadowAttenuation);
                half nl = dot(n, mainLight.direction);
                half3 front = SampleSH(n) + lightMain * saturate(nl);
                half3 back = SampleSH(-n) + lightMain * saturate(-nl);
                #if defined(_ADDITIONAL_LIGHTS)
                {
                    InputData inputData = (InputData)0;
                    inputData.positionWS = i.positionWS;
                    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(i.positionCS);
                    uint lightCount = GetAdditionalLightsCount();
                    LIGHT_LOOP_BEGIN(lightCount)
                        Light l = GetAdditionalLight(lightIndex, i.positionWS);
                        half3 lc = l.color * l.distanceAttenuation;
                        half ln = dot(n, l.direction);
                        front += lc * saturate(ln);
                        back += lc * saturate(-ln);
                    LIGHT_LOOP_END
                }
                #endif

                half3 diffuse = lerp(front, back * _TranslucentValue, _TranslucentMix);
                half3 color = baseColor * lerp((half)_EmissionStrength, diffuse, (half)_SurfaceMix);
                return half4(MixFog(color, i.fogCoord), 1);
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

            struct Attributes { float4 positionOS : POSITION; float2 uv0 : TEXCOORD0; float2 uv1 : TEXCOORD1; UNITY_VERTEX_INPUT_INSTANCE_ID };
            struct Varyings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; UNITY_VERTEX_OUTPUT_STEREO };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
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
