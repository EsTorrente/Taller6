// ESCENA67/LightFigureMagic  --  Quest 2 / Quest 3 optimized
// -----------------------------------------------------------------------------
// Original: Vefects URP Galaxy + Blender "LightFigure_Magic" dissolve (MagicDissolve.hlsl).
// The output was 100% emission, so the full URP PBR lighting path was replaced by an
// unlit path. See the notes at the bottom of this file for what changed / keywords.
//
// Visual output is identical to the old shader as long as Metallic / Smoothness /
// Galaxy Base Color Intensity were left at 0 (the defaults).
// -----------------------------------------------------------------------------
Shader "ESCENA67/LightFigureMagic"
{
	Properties
	{
		[Space(33)][Header(Galaxy Background)][Space(13)]_GalaxyTexture("Galaxy Texture", CUBE) = "white" {}
		_GalaxyEmissionIntensity("Galaxy Emission Intensity", Float) = 1
		_GalaxyTint("Galaxy Tint", Color) = (1,1,1,0)
		_GalaxyHueShift("Galaxy Hue Shift", Float) = 0
		_GalaxySaturationShift("Galaxy Saturation Shift", Float) = 0
		[Space(33)][Header(Stars)][Space(13)]_StarsTexture("Stars Texture", 2D) = "white" {}
		_StarsTile("Stars Tile", Vector) = (1,1,0,0)
		_StarsTileOverall("Stars Tile Overall", Float) = 1
		_StarsSpeed("Stars Speed", Vector) = (-0.05,-0.1,0,0)
		_StarsColor01("Stars Color 01", Color) = (0,0.9407032,1,0)
		_StarsColor02("Stars Color 02", Color) = (0.7019608,0,1,0)
		_StarsHueShift("Stars Hue Shift", Float) = 0
		_StarsEmissionIntensity("Stars Emission Intensity", Float) = 333
		[Toggle(_STARS_DISTORTION_ON)] _StarsDistortionEnable("Enable Stars Distortion (costs a dependent texture read)", Float) = 0
		_StarsDistortion("Stars Distortion", Float) = 0
		[Space(33)][Header(Stars Noise)][Space(13)]_StarsNoiseTexture("Stars Noise Texture", 2D) = "black" {}
		_StarsNoiseTile("Stars Noise Tile", Vector) = (1,1,0,0)
		_StarsNoiseTileOverall("Stars Noise Tile Overall", Float) = 1
		_StarsNoiseSpeed("Stars Noise Speed", Vector) = (0.1,-0.05,0,0)
		[Space(33)][Header(Fresnel)][Space(13)]_FresnelColor("Fresnel Color", Color) = (0,0.6859784,1,0)
		_FresnelHueShift("Fresnel Hue Shift", Float) = 0
		_FresnelEmissionIntensity("Fresnel Emission Intensity", Float) = 13
		_FresnelBias("Fresnel Bias", Float) = 0
		_FresnelScale("Fresnel Scale", Float) = 1
		_FresnelPower("Fresnel Power", Float) = 5
		[Toggle(_FRESNELINVERT_ON)] _FresnelInvert("Fresnel Invert", Float) = 0
		[Toggle(_FRESNEL_PER_PIXEL)] _FresnelPerPixel("Per-Pixel Fresnel (slower, smoother on low-poly)", Float) = 0
		[Toggle(_NO_HUE_SHIFT)] _NoHueShift("Strip hue/saturation shifts (faster; pick the colours directly instead)", Float) = 0
		[Space(33)][Header(Reflection)][Space(13)][Toggle(_USEREFLECTIONVECTOR_ON)] _UseReflectionVector("Use Reflection Vector", Float) = 0

		// ---- Magic dissolve (values are read by MagicDissolveInput.hlsl / MagicDissolve.hlsl) ----
		[HideInInspector] _MagicMapLocation("Mapping Location", Vector) = (0.3, 0, 0, 0)
		[HideInInspector] _MagicMapRotation("Mapping Rotation (radians)", Vector) = (0, 1.5708, 0, 0)
		[HideInInspector] _MagicMapScale("Mapping Scale", Vector) = (1, 1, 1, 0)
		[HideInInspector] _MagicNoiseMix("Noise -> Gradient Mix", Range(0, 1)) = 0.45
		[HideInInspector] _MagicNoiseScale("Noise Scale", Float) = 10
		[HideInInspector] _MagicNoiseDetail("Noise Detail (Blender uses 15)", Range(0, 15)) = 4
		[HideInInspector] _MagicNoiseRoughness("Noise Roughness", Range(0, 1)) = 0.5
		[HideInInspector] _MagicNoiseW("Noise W", Float) = 19.7083
		[HideInInspector] _MagicNoiseWPerFrame("Noise W per Frame", Float) = 0
		[HideInInspector] _MagicCut("Cut Ramp (visible at, hidden at)", Vector) = (0.5, 0.536, 0, 0)
		[HideInInspector] _MagicEdge("Glow Ramp (start, peak, end)", Vector) = (0.4, 0.515, 0.6, 0)
		[Header(Magic Glow)] _MagicGlowColorA("Glow Color 1", Color) = (0.8227, 0, 1, 1)
		_MagicGlowColorB("Glow Color 2", Color) = (1, 0.8063, 0.1231, 1)
		[HideInInspector] _MagicGlowColorRamp("Glow Color Ramp Positions", Vector) = (0.3, 0.7, 0, 0)
		[HideInInspector] _MagicGlowNoiseScale("Glow Color Noise Scale", Float) = 4
		[HideInInspector] _MagicGlowNoiseDetail("Glow Color Noise Detail", Range(0, 15)) = 2
		[HideInInspector] _MagicSparkleScale("Sparkle Scale", Float) = 60
		[HideInInspector] _MagicSparkleDetail("Sparkle Detail", Range(0, 15)) = 2
		[HideInInspector] _MagicSparkleW("Sparkle W", Float) = 0
		[HideInInspector] _MagicSparkleWPerFrame("Sparkle W per Frame", Float) = 0
		[HideInInspector] _MagicSparkleRamp("Sparkle Ramp (pos 1, pos 2, value 1, value 2)", Vector) = (0.45, 0.75, 0.35, 3)
		_MagicGlowStrength("Glow Strength", Float) = 14
	}

	SubShader
	{
		LOD 0
		Tags { "RenderPipeline"="UniversalPipeline" "RenderType"="Opaque" "Queue"="Geometry" }

		Cull Back
		ZWrite On
		ZTest LEqual

		// Shared by every pass: identical UnityPerMaterial CBUFFER (keeps SRP Batcher happy).
		HLSLINCLUDE
		#pragma target 3.5

		#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

		#include "MagicDissolveInput.hlsl"
		CBUFFER_START(UnityPerMaterial)
			float4 _StarsColor02;
			float4 _GalaxyTint;
			float4 _FresnelColor;
			float4 _StarsNoiseTexture_ST;
			float4 _StarsColor01;
			float4 _StarsTexture_ST;
			float2 _StarsNoiseTile;
			float2 _StarsNoiseSpeed;
			float2 _StarsTile;
			float2 _StarsSpeed;
			float _StarsEmissionIntensity;
			float _StarsHueShift;
			float _StarsNoiseTileOverall;
			float _StarsDistortion;
			float _StarsTileOverall;
			float _GalaxyHueShift;
			float _FresnelEmissionIntensity;
			float _FresnelHueShift;
			float _FresnelPower;
			float _FresnelScale;
			float _FresnelBias;
			float _GalaxyEmissionIntensity;
			float _GalaxySaturationShift;
			MAGIC_DISSOLVE_CBUFFER
		CBUFFER_END
		// Optional quality knobs of the dissolve noise (see the header of MagicDissolve.hlsl). Defaults = exact Blender noise.
		// #define MAGIC_CUT_DETAIL 1      // fewer octaves for the cut (this figure has Noise Mix 0.45, so it is more visible than on the kids)
		// #define MAGIC_SPARKLE_DETAIL 1
		// #define MAGIC_FAST_NOISE        // 3D instead of 4D noise (~2x cheaper, different pattern than Blender)
		#include "MagicDissolve.hlsl"
		ENDHLSL

		// =====================================================================
		// FORWARD  (unlit: emission only)
		// =====================================================================
		Pass
		{
			Name "Forward"
			Tags { "LightMode"="UniversalForward" }

			HLSLPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			#pragma multi_compile_instancing
			#pragma multi_compile_fog
			// Runtime-toggled by script: skips the whole magic dissolve (noise + discard) when the figure is fully visible.
			#pragma multi_compile_local _ _MAGICDISSOLVE_SKIP
			#pragma shader_feature_local _USEREFLECTIONVECTOR_ON
			#pragma shader_feature_local _FRESNELINVERT_ON
			#pragma shader_feature_local _FRESNEL_PER_PIXEL
			#pragma shader_feature_local_fragment _STARS_DISTORTION_ON
			#pragma shader_feature_local_fragment _NO_HUE_SHIFT
			// FoveatedRenderingKeywords.hlsl / FoveatedRendering.hlsl are no longer included: nothing in this shader (or in
			// MagicClip) reads screen-space coordinates through the foveated remap, so they only doubled the variants.
			// Add them back if you ever sample screen-space UVs here.

			#if defined(_USEREFLECTIONVECTOR_ON) || defined(_FRESNEL_PER_PIXEL)
				#define LF_NEEDS_NORMAL 1
			#endif

			TEXTURECUBE(_GalaxyTexture);       SAMPLER(sampler_GalaxyTexture);
			TEXTURE2D(_StarsTexture);          SAMPLER(sampler_StarsTexture);
			TEXTURE2D(_StarsNoiseTexture);     SAMPLER(sampler_StarsNoiseTexture);

			struct Attributes
			{
				float4 positionOS : POSITION;
				float3 normalOS   : NORMAL;
				float2 uv         : TEXCOORD0;
				UNITY_VERTEX_INPUT_INSTANCE_ID
			};

			struct Varyings
			{
				float4 positionCS         : SV_POSITION;
				float4 uvStarsNoise       : TEXCOORD0; // xy = stars uv (already panned), zw = noise uv (already panned)
				float4 viewVec_fresnel    : TEXCOORD1; // xyz = camera - world pos (affine: exact when interpolated), w = 1 - N.V (per-vertex)
				half   fogFactor          : TEXCOORD2;
				#if defined(LF_NEEDS_NORMAL)
					half3 normalWS        : TEXCOORD3;
				#endif
				#if !defined(_MAGICDISSOLVE_SKIP)
					float3 magicP         : TEXCOORD4; // dissolve noise-space position, mapped per vertex (was per pixel)
				#endif
				UNITY_VERTEX_INPUT_INSTANCE_ID
				UNITY_VERTEX_OUTPUT_STEREO
			};

			#if !defined(_NO_HUE_SHIFT)
			// ---- HSV helpers (only executed when a shift is actually non-zero) ----
			float3 LF_RGBToHSV(float3 c)
			{
				float4 K = float4(0.0, -1.0 / 3.0, 2.0 / 3.0, -1.0);
				float4 p = lerp(float4(c.bg, K.wz), float4(c.gb, K.xy), step(c.b, c.g));
				float4 q = lerp(float4(p.xyw, c.r), float4(c.r, p.yzx), step(p.x, c.r));
				float d = q.x - min(q.w, q.y);
				float e = 1.0e-10;
				return float3(abs(q.z + (q.w - q.y) / (6.0 * d + e)), d / (q.x + e), q.x);
			}

			float3 LF_HSVToRGB(float3 c)
			{
				float4 K = float4(1.0, 2.0 / 3.0, 1.0 / 3.0, 3.0);
				float3 p = abs(frac(c.xxx + K.xyz) * 6.0 - K.www);
				return c.z * lerp(K.xxx, saturate(p - K.xxx), c.y);
			}

			float3 LF_HueSatShift(float3 rgb, float hue, float sat)
			{
				float3 hsv = LF_RGBToHSV(rgb);
				return LF_HSVToRGB(float3(hsv.x + hue, hsv.y + sat, hsv.z));
			}
			#endif

			Varyings vert(Attributes v)
			{
				Varyings o = (Varyings)0;
				UNITY_SETUP_INSTANCE_ID(v);
				UNITY_TRANSFER_INSTANCE_ID(v, o);
				UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(o);

				float3 positionWS = TransformObjectToWorld(v.positionOS.xyz);
				o.positionCS = TransformWorldToHClip(positionWS);

				// UV transform + scrolling moved from the pixel shader to the vertex shader.
				// (affine -> interpolates exactly, and pixel shader samples straight from the varying)
				float2 starsUV = (v.uv * _StarsTexture_ST.xy + _StarsTexture_ST.zw) * _StarsTile * _StarsTileOverall + _Time.y * _StarsSpeed;
				float2 noiseUV = (v.uv * _StarsNoiseTexture_ST.xy + _StarsNoiseTexture_ST.zw) * _StarsNoiseTile * _StarsNoiseTileOverall + _Time.y * _StarsNoiseSpeed;
				o.uvStarsNoise = float4(starsUV, noiseUV);

				float3 normalWS = TransformObjectToWorldNormal(v.normalOS);
				float3 viewVec = _WorldSpaceCameraPos.xyz - positionWS; // un-normalized: fine for cubemap lookup
				#if !defined(_FRESNEL_PER_PIXEL)
					o.viewVec_fresnel = float4(viewVec, 1.0 - dot(normalWS, normalize(viewVec)));
				#else
					o.viewVec_fresnel = float4(viewVec, 0);
				#endif
				#if defined(LF_NEEDS_NORMAL)
					o.normalWS = half3(normalWS);
				#endif
				#if !defined(_MAGICDISSOLVE_SKIP)
					o.magicP = MagicPoint(positionWS);
				#endif

				o.fogFactor = ComputeFogFactor(o.positionCS.z);
				return o;
			}

			half4 frag(Varyings i) : SV_Target
			{
				UNITY_SETUP_INSTANCE_ID(i);
				UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(i);

				// 1) Dissolve FIRST: discarded pixels never pay for textures / emission math.
				float3 glow = 0;
				#if !defined(_MAGICDISSOLVE_SKIP)
					MagicDissolveData magic = MagicDissolveP(i.magicP);
					MagicClip(magic, i.positionCS.xy);
					glow += magic.glow;
				#endif

				float3 viewVec = i.viewVec_fresnel.xyz;

				// 2) Galaxy cubemap
				#if defined(_USEREFLECTIONVECTOR_ON)
					float3 galaxyDir = reflect(-normalize(viewVec), normalize((float3)i.normalWS));
				#else
					float3 galaxyDir = viewVec;
				#endif
				float3 galaxy = SAMPLE_TEXTURECUBE(_GalaxyTexture, sampler_GalaxyTexture, galaxyDir).rgb;
				#if !defined(_NO_HUE_SHIFT)
					UNITY_BRANCH
					if (_GalaxyHueShift != 0.0 || _GalaxySaturationShift != 0.0)
						galaxy = LF_HueSatShift(galaxy, _GalaxyHueShift, _GalaxySaturationShift);
				#endif
				half3 galaxyEmission = (half3)(saturate(galaxy) * (_GalaxyTint.rgb * _GalaxyEmissionIntensity));

				// 3) Fresnel
				#if defined(_FRESNEL_PER_PIXEL)
					float oneMinusNdotV = 1.0 - dot(normalize((float3)i.normalWS), normalize(viewVec));
				#else
					float oneMinusNdotV = i.viewVec_fresnel.w;
				#endif
				float fres = saturate(_FresnelBias + _FresnelScale * pow(max(oneMinusNdotV, 0.0001), _FresnelPower));
				#if defined(_FRESNELINVERT_ON)
					fres = saturate(1.0 - fres);
				#endif
				// hue-shift(color * f) == f * hue-shift(color)  ->  the HSV work depends only on uniforms
				float3 fresnelColor = _FresnelColor.rgb;
				#if !defined(_NO_HUE_SHIFT)
					UNITY_BRANCH
					if (_FresnelHueShift != 0.0)
						fresnelColor = LF_HueSatShift(fresnelColor, _FresnelHueShift, 0.0);
				#endif
				half3 fresnelEmission = (half3)(saturate(fresnelColor * fres) * _FresnelEmissionIntensity);

				// 4) Stars
				half noiseG = SAMPLE_TEXTURE2D(_StarsNoiseTexture, sampler_StarsNoiseTexture, i.uvStarsNoise.zw).g;
				float2 starsUV = i.uvStarsNoise.xy;
				#if defined(_STARS_DISTORTION_ON)
					starsUV += _StarsDistortion * noiseG; // dependent read, only when enabled
				#endif
				half starsG = SAMPLE_TEXTURE2D(_StarsTexture, sampler_StarsTexture, starsUV).g;
				half3 starsCol = lerp((half3)_StarsColor01.rgb, (half3)_StarsColor02.rgb, saturate(starsG * noiseG * 30.0h)) * starsG;
				#if !defined(_NO_HUE_SHIFT)
					UNITY_BRANCH
					if (_StarsHueShift != 0.0)
						starsCol = (half3)LF_HueSatShift((float3)starsCol, _StarsHueShift, 0.0);
				#endif
				half3 starsEmission = saturate(starsCol) * (half)_StarsEmissionIntensity;

				// 5) Combine (same sum as the original graph) + glow + fog
				half3 color = fresnelEmission + (galaxyEmission + starsEmission) + (half3)glow;
				color = MixFog(color, i.fogFactor);
				return half4(color, 1.0h);
			}
			ENDHLSL
		}

		// =====================================================================
		// SHADOW CASTER  (lean; remove this pass or set renderer Cast Shadows = Off if not needed)
		// =====================================================================
		Pass
		{
			Name "ShadowCaster"
			Tags { "LightMode"="ShadowCaster" }

			ZWrite On
			ZTest LEqual
			ColorMask 0

			HLSLPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			#pragma multi_compile_instancing
			#pragma multi_compile_local _ _MAGICDISSOLVE_SKIP
			#pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

			float3 _LightDirection;
			float3 _LightPosition;

			struct Attributes
			{
				float4 positionOS : POSITION;
				float3 normalOS   : NORMAL;
				UNITY_VERTEX_INPUT_INSTANCE_ID
			};

			struct Varyings
			{
				float4 positionCS : SV_POSITION;
				#if !defined(_MAGICDISSOLVE_SKIP)
					float3 magicP : TEXCOORD0;
				#endif
				UNITY_VERTEX_INPUT_INSTANCE_ID
				UNITY_VERTEX_OUTPUT_STEREO
			};

			Varyings vert(Attributes input)
			{
				Varyings output = (Varyings)0;
				UNITY_SETUP_INSTANCE_ID(input);
				UNITY_TRANSFER_INSTANCE_ID(input, output);
				UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

				float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
				float3 normalWS = TransformObjectToWorldDir(input.normalOS);
				#if !defined(_MAGICDISSOLVE_SKIP)
					output.magicP = MagicPoint(positionWS); // before the shadow bias moves positionWS
				#endif

				#if _CASTING_PUNCTUAL_LIGHT_SHADOW
					float3 lightDirectionWS = normalize(_LightPosition - positionWS);
				#else
					float3 lightDirectionWS = _LightDirection;
				#endif

				float4 positionCS = TransformWorldToHClip(ApplyShadowBias(positionWS, normalWS, lightDirectionWS));
				output.positionCS = ApplyShadowClamping(positionCS);
				return output;
			}

			half4 frag(Varyings input) : SV_TARGET
			{
				UNITY_SETUP_INSTANCE_ID(input);
				UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
				#if !defined(_MAGICDISSOLVE_SKIP)
					// Gradient only, no noise: shadows don't need the ragged edge (same as the kids)
					MagicClip(MagicDissolveCheap(input.magicP), input.positionCS.xy);
				#endif
				return 0;
			}
			ENDHLSL
		}

		// =====================================================================
		// DEPTH ONLY  (depth texture / depth priming; delete this pass if the project uses neither)
		// =====================================================================
		Pass
		{
			Name "DepthOnly"
			Tags { "LightMode"="DepthOnly" }

			ZWrite On
			ColorMask R

			HLSLPROGRAM
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
				UNITY_VERTEX_INPUT_INSTANCE_ID
				UNITY_VERTEX_OUTPUT_STEREO
			};

			Varyings vert(Attributes input)
			{
				Varyings output = (Varyings)0;
				UNITY_SETUP_INSTANCE_ID(input);
				UNITY_TRANSFER_INSTANCE_ID(input, output);
				UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

				float3 positionWS = TransformObjectToWorld(input.positionOS.xyz);
				output.positionCS = TransformWorldToHClip(positionWS);
				#if !defined(_MAGICDISSOLVE_SKIP)
					output.magicP = MagicPoint(positionWS);
				#endif
				return output;
			}

			half4 frag(Varyings input) : SV_TARGET
			{
				UNITY_SETUP_INSTANCE_ID(input);
				UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
				#if !defined(_MAGICDISSOLVE_SKIP)
					// Same cut as Forward (noise included) but no glow work
					MagicClip(MagicDissolveOpacityP(input.magicP), input.positionCS.xy);
				#endif
				return 0;
			}
			ENDHLSL
		}

		// =====================================================================
		// MOTION VECTORS  (only used by Application SpaceWarp; delete this pass if you don't use ASW)
		// Now clips with the same dissolve as Forward, so dissolved pixels no longer write motion (no ghosting).
		// =====================================================================
		Pass
		{
			Name "MotionVectors"
			Tags { "LightMode"="MotionVectors" }

			ColorMask RG

			HLSLPROGRAM
			#pragma vertex vert
			#pragma fragment frag

			#pragma multi_compile_instancing
			#pragma multi_compile_local _ _MAGICDISSOLVE_SKIP

			#define SHADERPASS SHADERPASS_MOTION_VECTORS
			#include "Packages/com.unity.render-pipelines.universal/Editor/ShaderGraph/Includes/ShaderPass.hlsl"
			#include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/MotionVectorsCommon.hlsl"

			struct Attributes
			{
				float4 positionOS  : POSITION;
				float3 positionOld : TEXCOORD4;
				UNITY_VERTEX_INPUT_INSTANCE_ID
			};

			struct Varyings
			{
				float4 positionCS               : SV_POSITION;
				float4 positionCSNoJitter       : TEXCOORD0;
				float4 previousPositionCSNoJitter : TEXCOORD1;
				#if !defined(_MAGICDISSOLVE_SKIP)
					float3 magicP               : TEXCOORD2;
				#endif
				UNITY_VERTEX_INPUT_INSTANCE_ID
				UNITY_VERTEX_OUTPUT_STEREO
			};

			Varyings vert(Attributes input)
			{
				Varyings output = (Varyings)0;
				UNITY_SETUP_INSTANCE_ID(input);
				UNITY_TRANSFER_INSTANCE_ID(input, output);
				UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

				VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);

				#if defined(APLICATION_SPACE_WARP_MOTION)
					output.positionCSNoJitter = mul(_NonJitteredViewProjMatrix, mul(UNITY_MATRIX_M, input.positionOS));
					output.positionCS = output.positionCSNoJitter;
				#else
					output.positionCS = vertexInput.positionCS;
					output.positionCSNoJitter = mul(_NonJitteredViewProjMatrix, mul(UNITY_MATRIX_M, input.positionOS));
				#endif

				float4 prevPos = (unity_MotionVectorsParams.x == 1) ? float4(input.positionOld, 1) : input.positionOS;
				output.previousPositionCSNoJitter = mul(_PrevViewProjMatrix, mul(UNITY_PREV_MATRIX_M, prevPos));
				#if !defined(_MAGICDISSOLVE_SKIP)
					output.magicP = MagicPoint(vertexInput.positionWS);
				#endif
				return output;
			}

			half4 frag(Varyings input) : SV_Target
			{
				UNITY_SETUP_INSTANCE_ID(input);
				UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
				#if !defined(_MAGICDISSOLVE_SKIP)
					MagicClip(MagicDissolveOpacityP(input.magicP), input.positionCS.xy);
				#endif
				#if defined(APLICATION_SPACE_WARP_MOTION)
					return float4(CalcAswNdcMotionVectorFromCsPositions(input.positionCSNoJitter, input.previousPositionCSNoJitter), 1);
				#else
					return float4(CalcNdcMotionVectorFromCsPositions(input.positionCSNoJitter, input.previousPositionCSNoJitter), 0, 0);
				#endif
			}
			ENDHLSL
		}
	}

	Fallback Off
}

/* ---------------------------------------------------------------------------
   CHANGE NOTES
   - Forward pass: URP Lit/PBR -> unlit (emission only).
   - Removed passes: GBuffer, DepthNormals, Meta, Universal2D, SceneSelection, ScenePicking.
   - Removed keywords: lights, shadows, SSAO, Forward+, lightmaps, probe volumes, decals, light layers/cookies,
     LOD crossfade, DOTS, _ALPHATEST_ON, debug display.
   - New keyword (runtime): _MAGICDISSOLVE_SKIP  -> compiles the dissolve out of Forward/Depth/Shadow.
   - New toggles: _FRESNEL_PER_PIXEL, _STARS_DISTORTION_ON.
   - Removed properties: Metallic, Smoothness, Galaxy Base Color Intensity (no lighting any more).
   - Dissolve mapping (MagicPoint) now runs per vertex in every pass; passes call MagicDissolveP / Cheap / OpacityP.
   - Shadow pass uses the gradient-only dissolve; depth / motion-vector passes skip the glow work.
   - Motion-vector pass now clips dissolved pixels.
   - Foveated-rendering keyword include removed (halves Forward variants).
   - New toggle: _NO_HUE_SHIFT strips all hue/saturation shift code.
--------------------------------------------------------------------------- */