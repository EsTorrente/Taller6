// Kids (Body_child, Clothes, Hair, Eyes...): toddler texture with the Blender "Kid_Magic" appear / disappear.
// Both kids share one material; the cut follows the KidChange empty through MagicDissolveDriver, which also gives
// each kid its own Mapping Location X. Defaults are the Blender values.
Shader "ESCENA67/KidMagic"
{
    Properties
    {
        [Header(Surface)] _BaseMap ("Texture", 2D) = "white" {}
        [HideInInspector] _Cutoff ("Texture Alpha Cutoff", Range(0, 1)) = 0.5
        [HideInInspector] _Roughness ("Roughness", Range(0, 1)) = 0.5
        _Brightness ("Brightness", Range(0, 3)) = 1
        _Unlit ("Unlit Amount", Range(0, 1)) = 0.6

        [HideInInspector] _MagicMapLocation ("Mapping Location (X is set per kid by MagicDissolveDriver)", Vector) = (0, 0, 0, 0)
        [HideInInspector] _MagicMapRotation ("Mapping Rotation (radians)", Vector) = (0, 1.5708, 0, 0)
        [HideInInspector] _MagicMapScale ("Mapping Scale", Vector) = (1, 1, 0.9524, 0)
        [HideInInspector] _MagicNoiseMix ("Noise -> Gradient Mix", Range(0, 1)) = 0.9167
        [HideInInspector] _MagicNoiseScale ("Noise Scale", Float) = 10
        [HideInInspector] _MagicNoiseDetail ("Noise Detail (Blender uses 15)", Range(0, 15)) = 4
        [HideInInspector] _MagicNoiseRoughness ("Noise Roughness", Range(0, 1)) = 0.5
        [HideInInspector] _MagicNoiseW ("Noise W", Float) = 0
        [HideInInspector] _MagicNoiseWPerFrame ("Noise W per Frame", Float) = 0.0208333
        [HideInInspector] _MagicCut ("Cut Ramp (visible at, hidden at)", Vector) = (0.5, 0.536, 0, 0)
        [HideInInspector] _MagicEdge ("Glow Ramp (start, peak, end)", Vector) = (0.4, 0.515, 0.6, 0)
        [Header(Magic Glow)] _MagicGlowColorA ("Glow Color 1", Color) = (0.8227, 0, 1, 1)
        _MagicGlowColorB ("Glow Color 2", Color) = (1, 0.8063, 0.1231, 1)
        [HideInInspector] _MagicGlowColorRamp ("Glow Color Ramp Positions", Vector) = (0.3, 0.7, 0, 0)
        [HideInInspector] _MagicGlowNoiseScale ("Glow Color Noise Scale", Float) = 4
        [HideInInspector] _MagicGlowNoiseDetail ("Glow Color Noise Detail", Range(0, 15)) = 2
        [HideInInspector] _MagicSparkleScale ("Sparkle Scale", Float) = 60
        [HideInInspector] _MagicSparkleDetail ("Sparkle Detail", Range(0, 15)) = 2
        [HideInInspector] _MagicSparkleW ("Sparkle W", Float) = 0
        [HideInInspector] _MagicSparkleWPerFrame ("Sparkle W per Frame", Float) = 0.0833333
        [HideInInspector] _MagicSparkleRamp ("Sparkle Ramp (pos 1, pos 2, value 1, value 2)", Vector) = (0.45, 0.75, 0.35, 3)
        _MagicGlowStrength ("Glow Strength", Float) = 10
    }
    SubShader
    {
        Tags { "RenderType"="TransparentCutout" "Queue"="AlphaTest" "RenderPipeline"="UniversalPipeline" }
        Cull Off

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "MagicDissolveInput.hlsl"

        TEXTURE2D(_BaseMap);
        SAMPLER(sampler_BaseMap);

        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            float _Cutoff;
            float _Roughness;
            float _Brightness;
            float _Unlit;
            MAGIC_DISSOLVE_CBUFFER
        CBUFFER_END

        #include "MagicDissolve.hlsl"

        struct Attributes
        {
            float4 positionOS : POSITION;
            float3 normalOS : NORMAL;
            float2 uv : TEXCOORD0;
            UNITY_VERTEX_INPUT_INSTANCE_ID
        };
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

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float3 magicP : TEXCOORD3; // noise-space position, interpolated
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
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                o.magicP = MagicPoint(o.positionWS);
                o.fogCoord = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            half4 frag(Varyings i, FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                half4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv);
                clip(tex.a - _Cutoff);
                MagicDissolveData magic = MagicDissolveP(i.magicP);
                MagicClip(magic, i.positionCS.xy);

                // Lambert instead of full PBR: the result is blended 60% towards the unlit texture anyway
                half3 n = normalize(IS_FRONT_VFACE(frontFace, i.normalWS, -i.normalWS));
                float4 shadowCoord = TransformWorldToShadowCoord(i.positionWS);
                Light mainLight = GetMainLight(shadowCoord);
                half3 light = SampleSH(n) + mainLight.color * (saturate(dot(n, mainLight.direction)) * mainLight.shadowAttenuation);
                #if defined(_ADDITIONAL_LIGHTS)
                {
                    InputData inputData = (InputData)0;
                    inputData.positionWS = i.positionWS;
                    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(i.positionCS);
                    uint pixelLightCount = GetAdditionalLightsCount();
                    LIGHT_LOOP_BEGIN(pixelLightCount)
                        Light l = GetAdditionalLight(lightIndex, i.positionWS);
                        light += l.color * (saturate(dot(n, l.direction)) * l.distanceAttenuation);
                    LIGHT_LOOP_END
                }
                #endif
                half3 lit = tex.rgb * light;
                // the scene lights are dim and orange; blend towards the painted texture so it reads as painted
                half3 color = lerp(lit, tex.rgb, _Unlit) * _Brightness + magic.glow;
                return half4(MixFog(color, i.fogCoord), 1);
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

            struct Varyings { float4 positionCS : SV_POSITION; float2 uv : TEXCOORD0; float3 magicP : TEXCOORD1; UNITY_VERTEX_OUTPUT_STEREO };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(positionWS);
                o.magicP = MagicPoint(positionWS);
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                clip(SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).a - _Cutoff);
                MagicClip(MagicDissolveP(i.magicP), i.positionCS.xy);
                return 0;
            }
            ENDHLSL
        }
    }
}
