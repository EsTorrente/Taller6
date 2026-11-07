// Kid Magic LITE (Quest / standalone VR): Character Recolor Toon without the recolour + the Blender "Kid_Magic" dissolve.
// Both kids can share one material; the cut follows the KidChange empty through MagicDissolveDriver (unchanged API:
// MAGIC_DISSOLVE_CBUFFER, MagicPoint, MagicDissolveP, MagicDissolveCheap, MagicClip from the existing Magic*.hlsl files).
//
// What was removed / changed compared to ESCENA67/KidMagic:
//  - Character recolour gone: no mask texture, no hair/skin/eye colours -> ONE texture fetch instead of two, lighter CBUFFER.
//  - Rim type, custom rim light, foot mask / foot shadow and rim shadow-mask are COMPILE-TIME features (keywords), so unused
//    code and interpolators don't exist in the shader at all (no runtime branches, lower register pressure).
//  - View vector computed only where the rim needs it (no interpolator), no GetVertexPositionInputs overhead.
//  - Toon maths factored (lighting term computed once, multiplied by the albedo once).
//  - _MAGICDISSOLVE_SKIP (runtime keyword, same as LightFigureMagic): enable it from script while a kid is fully visible
//    and the whole dissolve (noise + discard + interpolator) is compiled out of every pass.
//  - Variant count cut (fragment-only keywords, Forward+ line optional).
Shader "ESCENA67/KidMagicLite"
{
    Properties
    {
        [Header(Texture)]
        _BaseMap ("Base Texture", 2D) = "white" {}

        [Header(Lighting)]
        _LightIntensity ("Light Intensity", Range(0,2)) = 0.8
        _ShadowColor ("Shadow Color", Color) = (0.341,0.384,0.792,1)
        _ShadowThreshold ("Shadow Threshold", Range(0,1)) = 0.55
        _ShadowSoftness ("Shadow Softness", Range(0,0.5)) = 0.029
        _ShadowLightInfluence ("Shadow Light Color Influence", Range(0,1)) = 0

        [Header(Rim Light)]
        [KeywordEnum(LitEdge, ViewEdgeDark, LightBand, Off)] _RimType ("Rim Type (Off removes the rim code entirely)", Float) = 0
        [Toggle(_RIM_CUSTOM_LIGHT)] _RimCustomLight ("Use Custom Rim Light (PainterlyRimLight.cs)", Float) = 0
        _RimColor ("Rim Color", Color) = (1,0.651,0.627,1)
        _RimIntensity ("Rim Intensity", Range(0,3)) = 0.08
        _RimPower ("Rim Width (Power)", Range(0.5,8)) = 5.56
        _RimThreshold ("Rim Threshold", Range(0,1)) = 0.194
        _RimSoftness ("Rim Softness", Range(0,0.5)) = 0
        _RimLightOffset ("Light Edge Position", Range(-1,1)) = 0
        _RimLightInfluence ("Rim Light Color Influence", Range(0,1)) = 1

        [Header(Rim Shadows)]
        _RimShadowMask ("Hidden By Cast Shadows", Range(0,1)) = 1
        _RimShadowBias ("Cast Shadow Bias", Range(0,0.2)) = 0.03

        [Header(Foot Mask and Foot Shadow)]
        [Toggle(_FOOT_MASK_OFF)] _FootMaskOff ("Disable foot mask + foot shadow (faster)", Float) = 0
        _FootRimMask ("Rim Hidden In Foot Zone", Range(0,1)) = 1
        _FootShadowStrength ("Foot Shadow Strength (0 = off)", Range(0,1)) = 0
        _FootShadowColor ("Foot Shadow Color", Color) = (0,0,0,1)
        _FootShadowStart ("Start Height (fully dark)", Float) = 0
        _FootShadowEnd ("End Height (no effect)", Float) = 0.5
        [Enum(Object Space, 0, World Space, 1)] _FootShadowSpace ("Height Space", Float) = 0

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
        // AlphaTest queue: the dissolve uses discard, so draw after the opaque geometry
        Tags { "RenderType"="TransparentCutout" "RenderPipeline"="UniversalPipeline" "Queue"="AlphaTest" }

        HLSLINCLUDE
        #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
        #include "MagicDissolveInput.hlsl"

        TEXTURE2D(_BaseMap);
        SAMPLER(sampler_BaseMap);

        // Set globally by PainterlyRimLight.cs (not per material); only read when _RIM_CUSTOM_LIGHT is on
        float4 _PainterlyRimLightPos;
        float4 _PainterlyRimLightColor;

        // Identical in every pass => SRP Batcher compatible.
        CBUFFER_START(UnityPerMaterial)
            float4 _BaseMap_ST;

            half4 _ShadowColor;
            half _ShadowThreshold;
            half _ShadowSoftness;
            half _ShadowLightInfluence;
            half _LightIntensity;

            half4 _RimColor;
            half _RimPower;
            half _RimIntensity;
            half _RimLightInfluence;
            half _RimShadowMask;
            half _RimThreshold;
            half _RimSoftness;
            half _RimLightOffset;
            half _RimShadowBias;

            half _FootRimMask;
            half _FootShadowSpace;
            half4 _FootShadowColor;
            half _FootShadowStrength;
            float _FootShadowStart;
            float _FootShadowEnd;
            MAGIC_DISSOLVE_CBUFFER
        CBUFFER_END

        // Noise octave cap for the CUT noise. Kids have Noise->Gradient Mix ~0.92, so the noise is only ~8% of the cut
        // and the 3rd octave moves it by < 1%: invisible, one third less noise work. Delete this line for the full 3 octaves.
        #define MAGIC_CUT_DETAIL 1
        // More savings, all optional (see the header of MagicDissolve.hlsl):
        // #define MAGIC_FAST_NOISE        // 3D instead of 4D noise (~2x cheaper, different pattern than Blender)
        // #define MAGIC_SPARKLE_DETAIL 1  // fewer sparkle octaves
        #include "MagicDissolve.hlsl"
        ENDHLSL

        // =========================================================
        // MAIN TOON LIGHTING PASS
        // =========================================================
        Pass
        {
            Name "ToonForward"
            Tags { "LightMode"="UniversalForward" }

            HLSLPROGRAM
            #pragma target 3.5
            #pragma vertex vert
            #pragma fragment frag

            #pragma multi_compile_instancing
            // Runtime-toggled by script: compiles the whole dissolve out while the kid is fully visible.
            #pragma multi_compile_local _ _MAGICDISSOLVE_SKIP

            // Only the fragment stage reads these keywords.
            #pragma multi_compile_fragment _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHTS
            // Forward+ only: uncomment ONE of these (Unity 6.0: _FORWARD_PLUS, Unity 6.1+: _CLUSTER_LIGHT_LOOP).
            // #pragma multi_compile_fragment _ _FORWARD_PLUS
            // #pragma multi_compile_fragment _ _CLUSTER_LIGHT_LOOP

            // Material features: shader_feature_local = only the combinations your materials use are built.
            // Lit Edge is the default whenever none of the rim keywords is set.
            #pragma shader_feature_local_fragment _RIMTYPE_LITEDGE _RIMTYPE_VIEWEDGEDARK _RIMTYPE_LIGHTBAND _RIMTYPE_OFF
            #pragma shader_feature_local_fragment _RIM_CUSTOM_LIGHT
            #pragma shader_feature_local _FOOT_MASK_OFF

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv         : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                half3  normalWS   : TEXCOORD2;
                #if !defined(_FOOT_MASK_OFF)
                float  footHeight : TEXCOORD3;
                #endif
                #if !defined(_MAGICDISSOLVE_SKIP)
                float3 magicP     : TEXCOORD4; // noise-space position, interpolated
                #endif
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

                float3 positionWS = TransformObjectToWorld(IN.positionOS.xyz);
                OUT.positionCS = TransformWorldToHClip(positionWS);
                OUT.positionWS = positionWS;
                OUT.normalWS = (half3)TransformObjectToWorldNormal(IN.normalOS);
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);
                #if !defined(_FOOT_MASK_OFF)
                OUT.footHeight = _FootShadowSpace > 0.5h ? positionWS.y : IN.positionOS.y;
                #endif
                #if !defined(_MAGICDISSOLVE_SKIP)
                OUT.magicP = MagicPoint(positionWS);
                #endif
                return OUT;
            }

            // Toon light term WITHOUT albedo: sum these over all lights, multiply by the albedo once at the end.
            // (identical result to the original per-light baseColor * lerp(...) because the albedo factors out)
            half3 ToonTerm(half3 N, half3 L, half3 lightColor, half attenuation)
            {
                half lighting = saturate(dot(N, L)) * attenuation;
                half toonBand = smoothstep(_ShadowThreshold - _ShadowSoftness,
                                           _ShadowThreshold + _ShadowSoftness,
                                           lighting);
                half3 shadowTint = lerp(_ShadowColor.rgb, _ShadowColor.rgb * lightColor, _ShadowLightInfluence);
                return lerp(shadowTint, lightColor * _LightIntensity, toonBand);
            }

            half4 frag(Varyings IN) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(IN);

                // Dissolve FIRST: discarded pixels never pay for texture / lighting.
                half3 glow = 0;
                #if !defined(_MAGICDISSOLVE_SKIP)
                {
                    MagicDissolveData magic = MagicDissolveP(IN.magicP);
                    MagicClip(magic, IN.positionCS.xy);
                    glow = (half3)magic.glow;
                }
                #endif

                half4 baseTex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                half3 N = NormalizeNormalPerPixel(IN.normalWS);

                // ---- main light
                Light mainLight = GetMainLight(TransformWorldToShadowCoord(IN.positionWS));
                half3 L = mainLight.direction;
                half3 lightSum = ToonTerm(N, L, mainLight.color,
                                          (half)(mainLight.shadowAttenuation * mainLight.distanceAttenuation));

                // ---- additional lights (no per-light shadows)
                #if defined(_ADDITIONAL_LIGHTS)
                {
                    InputData inputData = (InputData)0;
                    inputData.positionWS = IN.positionWS;
                    inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(IN.positionCS);
                    uint pixelLightCount = GetAdditionalLightsCount();

                    #if USE_FORWARD_PLUS || USE_CLUSTER_LIGHT_LOOP
                    [loop] for (uint fpIndex = 0; fpIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); fpIndex++)
                    {
                        Light light = GetAdditionalLight(fpIndex, IN.positionWS);
                        lightSum += ToonTerm(N, light.direction, light.color, (half)light.distanceAttenuation);
                    }
                    #endif

                    LIGHT_LOOP_BEGIN(pixelLightCount)
                        Light light = GetAdditionalLight(lightIndex, IN.positionWS);
                        lightSum += ToonTerm(N, light.direction, light.color, (half)light.distanceAttenuation);
                    LIGHT_LOOP_END
                }
                #endif

                half3 finalColor = baseTex.rgb * lightSum;

                // ---- foot mask: 1 at/below Start, 0 at/above End (shadow colour + hides the rim)
                #if !defined(_FOOT_MASK_OFF)
                half footMask = (half)(1.0 - smoothstep(_FootShadowStart,
                                                        max(_FootShadowEnd, _FootShadowStart + 1e-4),
                                                        IN.footHeight));
                #endif

                // ---- rim light (compiled out entirely when Rim Type = Off)
                #if !defined(_RIMTYPE_OFF)
                if (_RimIntensity > 0.001h)
                {
                    half3 Lr = L;
                    half3 Cr = mainLight.color;
                    #if defined(_RIM_CUSTOM_LIGHT)
                    {
                        // w = 0: directional (xyz = direction toward the light), w = 1: point/spot (xyz = position)
                        float3 toLight = _PainterlyRimLightPos.xyz - IN.positionWS * _PainterlyRimLightPos.w;
                        Lr = half3(normalize(toLight + 1e-5));
                        Cr = _PainterlyRimLightColor.rgb;
                    }
                    #endif

                    half NoLr = dot(N, Lr);
                    half rimRaw;
                    #if defined(_RIMTYPE_LIGHTBAND)
                    {
                        // Light Edge: band where the surface turns away from the light
                        half band = saturate(1.0h - abs(NoLr - _RimLightOffset));
                        rimRaw = pow(max(band, 1e-4h), _RimPower);
                    }
                    #elif defined(_RIMTYPE_VIEWEDGEDARK)
                    {
                        // View Edge Dark Side
                        half3 V = half3(GetWorldSpaceNormalizeViewDir(IN.positionWS));
                        half fres = 1.0h - saturate(dot(N, V));
                        rimRaw = pow(max(fres, 1e-4h), _RimPower) * (1.0h - saturate(NoLr));
                    }
                    #else
                    {
                        // Lit Edge (default): outline glow only on the side facing the light
                        half3 V = half3(GetWorldSpaceNormalizeViewDir(IN.positionWS));
                        half fres = 1.0h - saturate(dot(N, V));
                        half litSide = smoothstep(_RimLightOffset - 0.1h, _RimLightOffset + 0.3h, NoLr);
                        rimRaw = pow(max(fres, 1e-4h), _RimPower) * litSide;
                    }
                    #endif

                    half rimSoft = max(_RimSoftness, 0.001h);
                    half rim = smoothstep(_RimThreshold - rimSoft, _RimThreshold + rimSoft, rimRaw);
                    #if !defined(_FOOT_MASK_OFF)
                    rim *= 1.0h - footMask * _FootRimMask;
                    #endif

                    // Hide the rim inside shadows cast by other objects. The extra shadow lookup only runs on pixels
                    // that actually have rim, and not at all when the main light has no realtime shadows.
                    #if defined(_MAIN_LIGHT_SHADOWS) || defined(_MAIN_LIGHT_SHADOWS_CASCADE)
                    if (rim > 0.001h && _RimShadowMask > 0.001h)
                    {
                        half rimShadowWeight = smoothstep(-0.15h, 0.1h, dot(N, L)) * _RimShadowMask;
                        if (rimShadowWeight > 0.001h)
                        {
                            half rimShadow = MainLightRealtimeShadow(
                                TransformWorldToShadowCoord(IN.positionWS + N * _RimShadowBias));
                            rimShadow = smoothstep(0.15h, 0.85h, rimShadow);
                            rim *= lerp(1.0h, rimShadow, rimShadowWeight);
                        }
                    }
                    #endif

                    half3 rimColor = lerp(_RimColor.rgb, _RimColor.rgb * Cr, _RimLightInfluence);
                    finalColor += rimColor * (rim * _RimIntensity);
                }
                #endif

                // ---- foot shadow
                #if !defined(_FOOT_MASK_OFF)
                finalColor = lerp(finalColor, _FootShadowColor.rgb, footMask * _FootShadowStrength);
                #endif

                // ---- magic glow band at the cut (emissive, on top of the toon result)
                finalColor += glow;

                return half4(finalColor, baseTex.a);
            }
            ENDHLSL
        }

        // =========================================================
        // SHADOW CASTING (own pass: UsePass of URP/Lit breaks SRP Batcher compatibility)
        // =========================================================
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
            #pragma multi_compile_local _ _MAGICDISSOLVE_SKIP
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
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                #if !defined(_MAGICDISSOLVE_SKIP)
                float3 magicP : TEXCOORD0;
                #endif
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                #if !defined(_MAGICDISSOLVE_SKIP)
                o.magicP = MagicPoint(positionWS); // before the shadow bias moves positionWS
                #endif
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

            half4 frag(Varyings i) : SV_Target
            {
                #if !defined(_MAGICDISSOLVE_SKIP)
                // Cheap: gradient only, no noise (shadows don't need the ragged edge)
                MagicClip(MagicDissolveCheap(i.magicP), i.positionCS.xy);
                #endif
                return 0;
            }
            ENDHLSL
        }

        // =========================================================
        // DEPTH ONLY (depth prepass / depth priming / camera depth texture)
        // Delete this pass if the project uses none of those.
        // =========================================================
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
            #pragma multi_compile_local _ _MAGICDISSOLVE_SKIP

            struct Attributes
            {
                float4 positionOS : POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };
            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                #if !defined(_MAGICDISSOLVE_SKIP)
                float3 magicP : TEXCOORD0;
                #endif
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
                o.positionCS = TransformWorldToHClip(positionWS);
                #if !defined(_MAGICDISSOLVE_SKIP)
                o.magicP = MagicPoint(positionWS);
                #endif
                return o;
            }

            half frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                #if !defined(_MAGICDISSOLVE_SKIP)
                // Full dissolve (same as Forward), or pixels discarded in Forward would still write depth
                MagicClip(MagicDissolveOpacityP(i.magicP), i.positionCS.xy);
                #endif
                return i.positionCS.z;
            }
            ENDHLSL
        }
    }

    FallBack Off
}
