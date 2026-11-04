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
        float4 SampleLeaf(float2 uv0, float2 uv1)
        {
            float2 uv = lerp(uv0, uv1, _UseUV2) * _UVScale;
            float s, c;
            sincos(_UVRotation, s, c);
            uv = float2(uv.x * c - uv.y * s, uv.x * s + uv.y * c) + _UVLocation.xy;
            float4 tex = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, uv);
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
        float3 LeafColor(float3 leafRGB, float3 positionOS)
        {
            float3 gen = (float3(-positionOS.x, positionOS.y, positionOS.z) - _GenMin.xyz) / _GenSize.xyz;
            float3 q = gen * _NoiseScale;
            float fac = LeafPerlin(q) + _NoiseRoughness * LeafPerlin(q * 2);
            float3 rampHSV = RgbToHsv(LeafRamp(fac));
            return HsvToRgb(float3(rampHSV.xy, max(leafRGB.r, max(leafRGB.g, leafRGB.b))));
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
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _CLUSTER_LIGHT_LOOP
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

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
                float4 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float3 normalWS : TEXCOORD2;
                float3 positionOS : TEXCOORD3;
                float fogCoord : TEXCOORD4;
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
                o.positionOS = v.positionOS.xyz;
                o.uv = float4(v.uv0, v.uv1);
                o.fogCoord = ComputeFogFactor(o.positionCS.z);
                return o;
            }

            half4 frag(Varyings i, FRONT_FACE_TYPE frontFace : FRONT_FACE_SEMANTIC) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                float4 leaf = SampleLeaf(i.uv.xy, i.uv.zw);
                clip(leaf.a - _Cutoff);
                float3 baseColor = LeafColor(leaf.rgb, i.positionOS);
                float3 n = normalize(IS_FRONT_VFACE(frontFace, i.normalWS, -i.normalWS));

                InputData inputData = (InputData)0;
                inputData.positionWS = i.positionWS;
                inputData.normalWS = n;
                inputData.viewDirectionWS = SafeNormalize(GetWorldSpaceViewDir(i.positionWS));
                inputData.shadowCoord = TransformWorldToShadowCoord(i.positionWS);
                inputData.fogCoord = i.fogCoord;
                inputData.bakedGI = SampleSH(n);
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(i.positionCS);
                inputData.shadowMask = half4(1, 1, 1, 1);

                SurfaceData surface = (SurfaceData)0;
                surface.albedo = baseColor;
                surface.smoothness = 1 - _Roughness;
                surface.occlusion = 1;
                surface.alpha = 1;
                float3 principled = UniversalFragmentPBR(inputData, surface).rgb;

                // Translucent BSDF: light arriving from the other side of the leaf
                Light mainLight = GetMainLight(inputData.shadowCoord);
                float3 through = mainLight.color * mainLight.distanceAttenuation * mainLight.shadowAttenuation * saturate(dot(-n, mainLight.direction));
                #if defined(_ADDITIONAL_LIGHTS)
                uint lightCount = GetAdditionalLightsCount();
                LIGHT_LOOP_BEGIN(lightCount)
                    Light light = GetAdditionalLight(lightIndex, i.positionWS);
                    through += light.color * light.distanceAttenuation * light.shadowAttenuation * saturate(dot(-n, light.direction));
                LIGHT_LOOP_END
                #endif
                float3 translucent = baseColor * _TranslucentValue * (through + SampleSH(-n));

                float3 surfaceColor = lerp(principled, translucent, _TranslucentMix);
                float3 color = lerp(baseColor * _EmissionStrength, surfaceColor, _SurfaceMix);
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
            struct Varyings { float4 positionCS : SV_POSITION; float4 uv : TEXCOORD0; };

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
                o.uv = float4(v.uv0, v.uv1);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                clip(SampleLeaf(i.uv.xy, i.uv.zw).a - _Cutoff);
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
            struct Varyings { float4 positionCS : SV_POSITION; float4 uv : TEXCOORD0; UNITY_VERTEX_OUTPUT_STEREO };

            Varyings vert(Attributes v)
            {
                Varyings o;
                UNITY_SETUP_INSTANCE_ID(v);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);
                o.positionCS = TransformObjectToHClip(v.positionOS.xyz);
                o.uv = float4(v.uv0, v.uv1);
                return o;
            }

            half4 frag(Varyings i) : SV_Target
            {
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);
                clip(SampleLeaf(i.uv.xy, i.uv.zw).a - _Cutoff);
                return 0;
            }
            ENDHLSL
        }
    }
}
