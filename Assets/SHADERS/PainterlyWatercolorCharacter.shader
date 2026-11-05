// Painterly Watercolor Environment - minimal VR version (Unity 6 / URP 17)
// Base color + optional normal map, watercolor shadow wash,
// optional metallic/roughness, foot shadow.
//
// Removed: noise, brush strokes, colour-bleed edges, rim light, rim shadows.
// Optional per-material compile-outs: "Disable Normal Map" and "Disable Specular + Reflections".
Shader "Custom/Painterly/WatercolorEnvironmentLow"
{
    Properties
    {
        [Header(Textures)]
        [MainTexture] _BaseMap("Base Texture", 2D) = "white" {}
        [MainColor] _BaseColor("Tint", Color) = (1,1,1,1)
        [Normal] _BumpMap("Normal Map", 2D) = "bump" {}
        _BumpScale("Normal Strength", Range(0, 3)) = 1

        [Header(Fast Paths)]
        [Toggle(_NO_NORMALMAP)] _NoNormalMap("Disable Normal Map", Float) = 0
        [Toggle(_NO_SPECULAR)] _NoSpecular("Disable Specular + Reflections", Float) = 0

        [Header(Surface)]
        _Metallic("Metallic", Range(0, 1)) = 0
        _Roughness("Roughness", Range(0, 1)) = 1

        [Header(Lighting)]
        _LightIntensity("Light Intensity", Range(0, 2)) = 1
        _ShadowThreshold("Shadow Threshold", Range(0, 1)) = 0.5
        _ShadowSoftness("Wash Softness", Range(0, 0.5)) = 0.052
        _NormalInfluence("Normal Map Affects Shadow Shape", Range(0, 1)) = 0.5
        _DetailLight("Normal Detail Lighting", Range(0, 2)) = 0.8

        [Header(Watercolor Shadows)]
        _ShadowColor("Shadow Pigment A (near wash edge)", Color) = (0.62, 0.6, 0.86, 1)
        _ShadowColorB("Shadow Pigment B (deep shadow)", Color) = (0.8, 0.61, 0.76, 1)
        _ShadowStrength("Pigment Strength", Range(0, 1)) = 0.6
        _ShadowDarkness("Shadow Darkness", Range(0, 0.8)) = 0.15
        _ShadowLightInfluence("Shadow Light Color Influence", Range(0, 1)) = 0.747
        _EdgePooling("Pigment Pooling At Wash Edge", Range(0, 1)) = 1
        _AmbientInfluence("Ambient Influence", Range(0, 1)) = 0.416

        [Header(Foot Shadow)]
        _FootShadowStrength("Strength (0 = off)", Range(0, 1)) = 0
        _FootShadowColor("Color", Color) = (0, 0, 0, 1)
        _FootShadowStart("Start Height (fully dark)", Float) = 0
        _FootShadowEnd("End Height (no effect)", Float) = 0.5
        [Enum(Object Space, 0, World Space, 1)] _FootShadowSpace("Height Space", Float) = 0
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline" "Queue"="Geometry" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

        TEXTURE2D(_BaseMap); SAMPLER(sampler_BaseMap);
        TEXTURE2D(_BumpMap); SAMPLER(sampler_BumpMap);

        // Identical in every pass => SRP Batcher compatible.
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;
            half4 _BaseColor;
            half _BumpScale;

            half _LightIntensity;
            half _ShadowThreshold;
            half _ShadowSoftness;
            half _NormalInfluence;
            half _DetailLight;
            half _Metallic;
            half _Roughness;

            half4 _ShadowColor;
            half4 _ShadowColorB;
            half _ShadowStrength;
            half _ShadowDarkness;
            half _ShadowLightInfluence;
            half _EdgePooling;
            half _AmbientInfluence;

            half _FootShadowStrength;
            half4 _FootShadowColor;
            float _FootShadowStart;
            float _FootShadowEnd;
            half _FootShadowSpace;
        CBUFFER_END
        ENDHLSL

        // ------------------------------------------------------------ Forward
        Pass
        {
            Name "ForwardLit"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile_instancing
            #pragma shader_feature_local _NO_NORMALMAP
            #pragma shader_feature_local _NO_SPECULAR

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            // Soft shadows removed on purpose (hard shadow = one hardware-filtered tap).
            // To bring them back, add:  #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            // Forward+ keyword: _FORWARD_PLUS on Unity 6.0, _CLUSTER_LIGHT_LOOP on 6.1+.
            // Delete the one you don't need to halve the variant count.
            #pragma multi_compile _ _FORWARD_PLUS _CLUSTER_LIGHT_LOOP
            #pragma multi_compile_fragment _ _REFLECTION_PROBE_ATLAS
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                #if !defined(_NO_NORMALMAP)
                float4 tangentOS  : TANGENT;
                #endif
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                half3  normalWS   : TEXCOORD2;
                #if !defined(_NO_NORMALMAP)
                half4  tangentWS  : TEXCOORD3;
                #endif
                half3  ambient    : TEXCOORD4;   // SH ambient, evaluated per vertex
                half   fogFactor  : TEXCOORD5;
                float  footHeight : TEXCOORD6;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            // Extra lights use the same wash threshold so they feel painted too.
            half3 AddLight(Light l, half3 N, half3 albedo)
            {
                half hl = dot(N, l.direction) * 0.5h + 0.5h;
                half soft = max(_ShadowSoftness, 0.001h);
                half w = smoothstep(_ShadowThreshold - soft, _ShadowThreshold + soft, hl);
                return albedo * l.color * ((half)l.distanceAttenuation * w * _LightIntensity);
            }

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_TRANSFER_INSTANCE_ID(v, o);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

                VertexPositionInputs vp = GetVertexPositionInputs(v.positionOS.xyz);
                o.positionCS = vp.positionCS;
                o.positionWS = vp.positionWS;
                o.uv = TRANSFORM_TEX(v.uv, _BaseMap);

                #if defined(_NO_NORMALMAP)
                    half3 nWS = TransformObjectToWorldNormal(v.normalOS);
                    o.normalWS = nWS;
                #else
                    VertexNormalInputs vn = GetVertexNormalInputs(v.normalOS, v.tangentOS);
                    half3 nWS = vn.normalWS;
                    o.normalWS = nWS;
                    o.tangentWS = half4(vn.tangentWS, v.tangentOS.w * GetOddNegativeScale());
                #endif

                o.ambient = SampleSH(nWS);
                o.fogFactor = ComputeFogFactor(vp.positionCS.z);
                o.footHeight = _FootShadowSpace > 0.5h ? vp.positionWS.y : v.positionOS.y;
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(i);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

                half3 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, i.uv).rgb * _BaseColor.rgb;
                #if defined(_NO_SPECULAR)
                    half3 diffAlbedo = albedo;
                #else
                    half3 diffAlbedo = albedo * (1.0h - _Metallic * 0.85h);   // metals keep a little diffuse
                #endif

                half3 Ng = NormalizeNormalPerPixel(i.normalWS);
                #if defined(_NO_NORMALMAP)
                    half3 Nm = Ng;
                    half3 Nshape = Ng;
                #else
                    half3 nTS = UnpackNormalScale(SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, i.uv), _BumpScale);
                    half3 B = cross(Ng, i.tangentWS.xyz) * i.tangentWS.w;
                    half3 Nm = NormalizeNormalPerPixel(mul(nTS, half3x3(i.tangentWS.xyz, B, Ng)));
                    half3 Nshape = NormalizeNormalPerPixel(lerp(Ng, Nm, _NormalInfluence));
                #endif

                // ---- main light
                Light ml = GetMainLight(TransformWorldToShadowCoord(i.positionWS));
                half3 L = ml.direction;

                half hl = dot(Nshape, L) * 0.5h + 0.5h;
                half soft = max(_ShadowSoftness, 0.001h);

                half lightWash = smoothstep(_ShadowThreshold - soft, _ShadowThreshold + soft, hl);
                half castWash = smoothstep(0.15h, 0.85h, (half)ml.shadowAttenuation);
                half wash = min(lightWash, castWash);   // 1 = lit, 0 = shadow
                half s = 1.0h - wash;
                half edge = 1.0h - abs(wash * 2.0h - 1.0h);   // peaks along the wash boundary

                // ---- watercolor shadow pigment (multiplies albedo, never replaces it)
                half depth = saturate((_ShadowThreshold - hl) / max(_ShadowThreshold, 0.05h));
                half3 pigment = lerp(_ShadowColor.rgb, _ShadowColorB.rgb, depth);
                pigment *= lerp(1.0h, ml.color, _ShadowLightInfluence);
                half3 sm = lerp(1.0h, pigment, _ShadowStrength);
                sm *= (1.0h - _ShadowDarkness) * (1.0h - edge * _EdgePooling * 0.3h);
                sm *= lerp(1.0h, saturate(i.ambient * 2.0h + 0.25h), _AmbientInfluence);

                half3 col = lerp(diffAlbedo * ml.color * _LightIntensity, diffAlbedo * sm, s);

                // ---- additional lights (no per-light shadows)
                #if defined(_ADDITIONAL_LIGHTS)
                {
                    InputData inputData = (InputData)0;
                    inputData.positionWS = i.positionWS;
                    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(i.positionCS);
                    uint pixelLightCount = GetAdditionalLightsCount();

                    #if USE_FORWARD_PLUS || USE_CLUSTER_LIGHT_LOOP
                    [loop] for (uint fpIndex = 0; fpIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); fpIndex++)
                    {
                        Light l = GetAdditionalLight(fpIndex, i.positionWS);
                        col += AddLight(l, Nshape, diffAlbedo);
                    }
                    #endif

                    LIGHT_LOOP_BEGIN(pixelLightCount)
                        Light l = GetAdditionalLight(lightIndex, i.positionWS);
                        col += AddLight(l, Nshape, diffAlbedo);
                    LIGHT_LOOP_END
                }
                #endif

                // ---- normal-map detail in both lit and shadow areas (anti-plastic)
                #if !defined(_NO_NORMALMAP)
                {
                    half detail = dot(Nm, L) - dot(Ng, L);
                    col *= clamp(1.0h + detail * _DetailLight * 0.5h * lerp(1.0h, 0.5h, s), 0.0h, 2.0h);
                }
                #endif

                // ---- metallic / roughness (compiled out with "Disable Specular + Reflections")
                #if !defined(_NO_SPECULAR)
                {
                    half3 V = half3(GetWorldSpaceNormalizeViewDir(i.positionWS));
                    half pr = max(_Roughness, 0.05h);
                    half3 specTint = lerp(half3(0.3h, 0.3h, 0.3h), albedo, _Metallic);

                    if (pr < 0.99h)
                    {
                        float rough = pr * pr;
                        float rough2 = max(rough * rough, 6.1e-5);
                        float3 Hv = SafeNormalize(float3(L) + float3(V));
                        float NoH = saturate(dot(float3(Nm), Hv));
                        float LoH = saturate(dot(float3(L), Hv));
                        float dd = NoH * NoH * (rough2 - 1.0) + 1.0001;
                        float spec = rough2 / (dd * dd * max(0.1, LoH * LoH) * (rough * 4.0 + 2.0));
                        spec *= saturate(dot(Nm, L)) * ml.shadowAttenuation * (1.0 - pr);
                        spec = 1.0 - exp(-spec * 0.6);
                        col += specTint * ml.color * (smoothstep(0.35h, 0.55h, (half)spec) * wash);
                    }

                    half f = 1.0h - saturate(dot(Nm, V));
                    f *= f;
                    half envAmt = _Metallic + (1.0h - _Metallic) * f * f * 0.15h * (1.0h - pr);
                    if (envAmt > 0.003h)
                    {
                        half3 R = reflect(-V, Nm);
                        half3 env = GlossyEnvironmentReflection(R, i.positionWS, pr, 1.0h, GetNormalizedScreenSpaceUV(i.positionCS));
                        col += env * specTint * envAmt;
                    }
                }
                #endif

                // ---- foot shadow: fade the bottom to a chosen color (skipped when Strength = 0)
                if (_FootShadowStrength > 0.001h)
                {
                    half foot = (half)(1.0 - smoothstep(_FootShadowStart,
                                                        max(_FootShadowEnd, _FootShadowStart + 1e-4),
                                                        i.footHeight));
                    col = lerp(col, _FootShadowColor.rgb, foot * _FootShadowStrength);
                }

                col = MixFog(col, i.fogFactor);
                return half4(col, 1.0h);
            }
            ENDHLSL
        }

        // ------------------------------------------------------- ShadowCaster
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode"="ShadowCaster" }
            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"

            float3 _LightDirection;
            float3 _LightPosition;

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            struct Varyings { float4 positionCS : SV_POSITION; };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
                #if _CASTING_PUNCTUAL_LIGHT_SHADOW
                    float3 lightDir = normalize(_LightPosition - positionWS);
                #else
                    float3 lightDir = _LightDirection;
                #endif
                float4 posCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDir));
                #if UNITY_REVERSED_Z
                    posCS.z = min(posCS.z, UNITY_NEAR_CLIP_VALUE);
                #else
                    posCS.z = max(posCS.z, UNITY_NEAR_CLIP_VALUE);
                #endif
                o.positionCS = posCS;
                return o;
            }

            half4 frag(Varyings i) : SV_Target { return 0; }
            ENDHLSL
        }

        // ---------------------------------------------------------- DepthOnly
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode"="DepthOnly" }
            ZWrite On
            ColorMask R
            Cull Back

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing

            struct Attributes
            {
                float4 positionOS : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                return o;
            }

            half frag(Varyings i) : SV_Target { return i.positionCS.z; }
            ENDHLSL
        }

        // ------------------------------------------------------- DepthNormals
        Pass
        {
            Name "DepthNormals"
            Tags { "LightMode"="DepthNormals" }
            ZWrite On
            Cull Back

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_instancing
            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                half3 normalWS : TEXCOORD0;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.normalWS = TransformObjectToWorldNormal(v.normalOS);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                #if defined(_GBUFFER_NORMALS_OCT)
                    float3 n = normalize(i.normalWS);
                    float2 oct = PackNormalOctQuadEncode(n);
                    float2 r = saturate(oct * 0.5 + 0.5);
                    return half4(PackFloat2To888(r), 0.0);
                #else
                    return half4(NormalizeNormalPerPixel(i.normalWS), 0.0);
                #endif
            }
            ENDHLSL
        }
    }

    FallBack Off
}
