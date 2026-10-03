Shader "Custom/EyesRecolourToon"
{
    Properties
    {
        // =========================================================
        // TEXTURES
        // =========================================================

        _BaseMap ("Base Texture", 2D) = "white" {}
        _MaskMap ("RGB Mask", 2D) = "black" {}


        // =========================================================
        // CHARACTER COLORS
        // =========================================================

        _HairColor ("Hair Color", Color) = (1,1,1,1)
        _SkinColor ("Skin Color", Color) = (1,1,1,1)
        _EyeColor ("Eye Color", Color) = (1,1,1,1)

        _HairStrength ("Hair Strength", Range(0,1)) = 0.922
        _SkinStrength ("Skin Strength", Range(0,1)) = 0.925
        _EyeStrength ("Eye Strength", Range(0,1)) = 0.923


        // =========================================================
        // TOON LIGHTING
        // =========================================================

        _ShadowColor ("Shadow Color", Color) = (0.341,0.384,0.792,1)

        _ShadowThreshold ("Shadow Threshold", Range(0,1)) = 0.55

        _ShadowSoftness ("Shadow Softness", Range(0,0.5)) = 0.029

        _ShadowLightInfluence
        (
            "Shadow Light Color Influence",
            Range(0,1)
        ) = 0


        // =========================================================
        // LIGHTING STRENGTH
        // =========================================================

        _LightIntensity ("Light Intensity", Range(0,2)) = 0.8


        // =========================================================
        // RIM LIGHT
        // =========================================================

        _RimColor ("Rim Color", Color) = (1,0.651,0.627,1)

        _RimPower ("Rim Power", Range(0.5,8)) = 5.56

        _RimIntensity ("Rim Intensity", Range(0,3)) = 0.08

        _RimLightInfluence
        (
            "Rim Light Color Influence",
            Range(0,1)
        ) = 1
    }


    SubShader
    {
        // =========================================================
        // TRANSPARENCY
        // =========================================================

        Tags
        {
            "RenderType" = "Transparent"
            "Queue" = "Transparent"
            "RenderPipeline" = "UniversalPipeline"
        }


        // =========================================================
        // MAIN TOON LIGHTING PASS
        // =========================================================

        Pass
        {
            Name "ToonForward"

            Tags
            {
                "LightMode" = "UniversalForward"
            }

            // -----------------------------------------------------
            // ALPHA BLENDING
            // -----------------------------------------------------

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off


            HLSLPROGRAM

            #pragma vertex vert
            #pragma fragment frag


            // =====================================================
            // LIGHT KEYWORDS
            // =====================================================

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS_SCREEN

            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _FORWARD_PLUS


            // =====================================================
            // URP LIBRARIES
            // =====================================================

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"


            // =====================================================
            // STRUCTURES
            // =====================================================

            struct Attributes
            {
                float4 positionOS : POSITION;

                float3 normalOS : NORMAL;

                float2 uv : TEXCOORD0;
            };


            struct Varyings
            {
                float4 positionCS : SV_POSITION;

                float3 positionWS : TEXCOORD1;

                float3 normalWS : TEXCOORD2;

                float2 uv : TEXCOORD3;

                float3 viewDirectionWS : TEXCOORD4;

                float4 shadowCoord : TEXCOORD5;
            };


            // =====================================================
            // TEXTURES
            // =====================================================

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);

            TEXTURE2D(_MaskMap);
            SAMPLER(sampler_MaskMap);


            // =====================================================
            // MATERIAL VARIABLES
            // =====================================================

            CBUFFER_START(UnityPerMaterial)

                float4 _BaseMap_ST;

                float4 _HairColor;
                float4 _SkinColor;
                float4 _EyeColor;

                float _HairStrength;
                float _SkinStrength;
                float _EyeStrength;

                float4 _ShadowColor;

                float _ShadowThreshold;
                float _ShadowSoftness;

                float _ShadowLightInfluence;

                float _LightIntensity;

                float4 _RimColor;

                float _RimPower;
                float _RimIntensity;

                float _RimLightInfluence;

            CBUFFER_END


            // =====================================================
            // VERTEX
            // =====================================================

            Varyings vert(Attributes IN)
            {
                Varyings OUT;


                // -------------------------------------------------
                // World position
                // -------------------------------------------------

                VertexPositionInputs positionInputs =
                    GetVertexPositionInputs(IN.positionOS.xyz);

                OUT.positionCS = positionInputs.positionCS;

                OUT.positionWS = positionInputs.positionWS;


                // -------------------------------------------------
                // World normal
                // -------------------------------------------------

                VertexNormalInputs normalInputs =
                    GetVertexNormalInputs(IN.normalOS);

                OUT.normalWS =
                    normalize(normalInputs.normalWS);


                // -------------------------------------------------
                // UV
                // -------------------------------------------------

                OUT.uv =
                    TRANSFORM_TEX(IN.uv, _BaseMap);


                // -------------------------------------------------
                // Camera direction
                // -------------------------------------------------

                OUT.viewDirectionWS =
                    GetWorldSpaceNormalizeViewDir(
                        OUT.positionWS
                    );


                // -------------------------------------------------
                // Shadow coordinates
                // -------------------------------------------------

                OUT.shadowCoord =
                    GetShadowCoord(positionInputs);


                return OUT;
            }


            // =====================================================
            // RECOLOR FUNCTION
            // =====================================================

            half3 ApplyRecolor(
                half3 original,
                half3 mask,
                half3 result
            )
            {
                half hairMask = mask.r;
                half skinMask = mask.g;
                half eyeMask  = mask.b;


                // -------------------------------------------------
                // Hair
                // -------------------------------------------------

                result = lerp(
                    result,
                    original * _HairColor.rgb,
                    hairMask * _HairStrength
                );


                // -------------------------------------------------
                // Skin
                // -------------------------------------------------

                result = lerp(
                    result,
                    original * _SkinColor.rgb,
                    skinMask * _SkinStrength
                );


                // -------------------------------------------------
                // Eyes
                // -------------------------------------------------

                result = lerp(
                    result,
                    original * _EyeColor.rgb,
                    eyeMask * _EyeStrength
                );


                return result;
            }


            // =====================================================
            // TOON LIGHT FUNCTION
            // =====================================================

            half3 ToonLight(
                half3 baseColor,
                half3 normalWS,
                half3 lightDirection,
                half3 lightColor,
                half lightAttenuation
            )
            {
                // -------------------------------------------------
                // N dot L
                // -------------------------------------------------

                half NdotL =
                    saturate(
                        dot(
                            normalWS,
                            lightDirection
                        )
                    );


                // -------------------------------------------------
                // Apply light/shadow attenuation
                // -------------------------------------------------

                half lighting =
                    NdotL * lightAttenuation;


                // -------------------------------------------------
                // Toon threshold
                // -------------------------------------------------

                half toonBand =
                    smoothstep(
                        _ShadowThreshold - _ShadowSoftness,
                        _ShadowThreshold + _ShadowSoftness,
                        lighting
                    );


                // -------------------------------------------------
                // Shadow colour influenced by light colour
                // -------------------------------------------------

                half3 lightInfluencedShadow =
                    lerp(
                        _ShadowColor.rgb,
                        _ShadowColor.rgb * lightColor,
                        _ShadowLightInfluence
                    );


                // -------------------------------------------------
                // Blend shadow → light
                // -------------------------------------------------

                half3 toonColor =
                    lerp(
                        baseColor * lightInfluencedShadow,
                        baseColor * lightColor * _LightIntensity,
                        toonBand
                    );


                return toonColor;
            }


            // =====================================================
            // FRAGMENT
            // =====================================================

            half4 frag(Varyings IN) : SV_Target
            {
                // =================================================
                // TEXTURES
                // =================================================

                half4 baseTexture =
                    SAMPLE_TEXTURE2D(
                        _BaseMap,
                        sampler_BaseMap,
                        IN.uv
                    );


                half4 mask =
                    SAMPLE_TEXTURE2D(
                        _MaskMap,
                        sampler_BaseMap,
                        IN.uv
                    );


                // =================================================
                // RECOLOR CHARACTER
                // =================================================

                half3 baseColor =
                    ApplyRecolor(
                        baseTexture.rgb,
                        mask.rgb,
                        baseTexture.rgb
                    );


                // =================================================
                // NORMAL
                // =================================================

                half3 normalWS =
                    normalize(IN.normalWS);


                // =================================================
                // MAIN LIGHT
                // =================================================

                Light mainLight =
                    GetMainLight(IN.shadowCoord);


                // -------------------------------------------------
                // Main light direction
                // -------------------------------------------------

                half3 mainLightDirection =
                    normalize(mainLight.direction);


                // -------------------------------------------------
                // Main light attenuation
                // -------------------------------------------------

                half mainAttenuation =
                    mainLight.shadowAttenuation *
                    mainLight.distanceAttenuation;


                // -------------------------------------------------
                // Toon main lighting
                // -------------------------------------------------

                half3 finalColor =
                    ToonLight(
                        baseColor,
                        normalWS,
                        mainLightDirection,
                        mainLight.color,
                        mainAttenuation
                    );


                // =================================================
                // ADDITIONAL LIGHTS
                // =================================================

                #if defined(_ADDITIONAL_LIGHTS)

                    // -------------------------------------------------
                    // Forward+ directional lights
                    // -------------------------------------------------

                    #if USE_FORWARD_PLUS

                    UNITY_LOOP

                    for (
                        uint lightIndex = 0;

                        lightIndex <
                        min(
                            URP_FP_DIRECTIONAL_LIGHTS_COUNT,
                            MAX_VISIBLE_LIGHTS
                        );

                        lightIndex++
                    )
                    {
                        Light light =
                            GetAdditionalLight(
                                lightIndex,
                                IN.positionWS,
                                half4(1,1,1,1)
                            );


                        finalColor +=
                            ToonLight(
                                baseColor,
                                normalWS,
                                normalize(light.direction),
                                light.color,
                                light.distanceAttenuation *
                                light.shadowAttenuation
                            );
                    }

                    #endif


                    // -------------------------------------------------
                    // Regular additional lights
                    // -------------------------------------------------

                    uint pixelLightCount =
                        GetAdditionalLightsCount();


                    LIGHT_LOOP_BEGIN(pixelLightCount)

                        Light light =
                            GetAdditionalLight(
                                lightIndex,
                                IN.positionWS,
                                half4(1,1,1,1)
                            );


                        finalColor +=
                            ToonLight(
                                baseColor,
                                normalWS,
                                normalize(light.direction),
                                light.color,
                                light.distanceAttenuation *
                                light.shadowAttenuation
                            );

                    LIGHT_LOOP_END

                #endif


                // =================================================
                // RIM LIGHT
                // =================================================

                half3 viewDirection =
                    normalize(IN.viewDirectionWS);


                // -------------------------------------------------
                // View-angle rim
                // -------------------------------------------------

                half rim =
                    1.0 -
                    saturate(
                        dot(
                            normalWS,
                            viewDirection
                        )
                    );


                // -------------------------------------------------
                // Make rim sharper/softer
                // -------------------------------------------------

                rim =
                    pow(
                        rim,
                        _RimPower
                    );


                // -------------------------------------------------
                // Main light influence
                // -------------------------------------------------

                half rimLightFacing =
                    saturate(
                        dot(
                            normalWS,
                            mainLightDirection
                        )
                    );


                // More rim on the darker/back-facing side
                half rimFromLight =
                    1.0 -
                    rimLightFacing;


                rim *= rimFromLight;


                // -------------------------------------------------
                // Rim colour
                // -------------------------------------------------

                half3 finalRimColor =
                    lerp(
                        _RimColor.rgb,
                        _RimColor.rgb * mainLight.color,
                        _RimLightInfluence
                    );


                finalColor +=
                    finalRimColor *
                    rim *
                    _RimIntensity;


                // =================================================
                // OUTPUT
                // =================================================

                // IMPORTANT:
                // The original texture alpha is preserved here.
                // Pixels with alpha 0 become invisible because
                // the pass uses SrcAlpha blending above.

                return half4(
                    finalColor,
                    baseTexture.a
                );
            }

            ENDHLSL
        }


        // =========================================================
        // SHADOW CASTING
        // =========================================================

        UsePass "Universal Render Pipeline/Lit/ShadowCaster"
    }
}