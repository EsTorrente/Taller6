Shader "Custom/TwoSidedTexture_URP"
{
    Properties
    {
        [MainTexture] _FrontTex ("Front Texture", 2D) = "white" {}
        _BackTex ("Back Texture", 2D) = "white" {}
        [MainColor] _FrontColor ("Front Tint", Color) = (1,1,1,1)
        _BackColor ("Back Tint", Color) = (1,1,1,1)
    }

    SubShader
    {
        Tags { "RenderType"="Opaque" "Queue"="Geometry" "RenderPipeline"="UniversalPipeline" }

        Pass
        {
            Name "Unlit"
            Tags { "LightMode"="UniversalForward" }
            Cull Off

            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog
            #pragma multi_compile_instancing

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            TEXTURE2D(_FrontTex); SAMPLER(sampler_FrontTex);
            TEXTURE2D(_BackTex);  SAMPLER(sampler_BackTex);

            // SRP Batcher compatible: everything in one CBUFFER
            CBUFFER_START(UnityPerMaterial)
                float4 _FrontTex_ST;
                float4 _BackTex_ST;
                half4  _FrontColor;
                half4  _BackColor;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float4 uv         : TEXCOORD0; // xy = front, zw = back
                half   fogFactor  : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            Varyings vert (Attributes IN)
            {
                Varyings OUT;
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_TRANSFER_INSTANCE_ID(IN, OUT);

                OUT.positionCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.uv.xy = IN.uv * _FrontTex_ST.xy + _FrontTex_ST.zw;
                OUT.uv.zw = IN.uv * _BackTex_ST.xy  + _BackTex_ST.zw;
                OUT.fogFactor = ComputeFogFactor(OUT.positionCS.z);
                return OUT;
            }

            half4 frag (Varyings IN, FRONT_FACE_TYPE face : FRONT_FACE_SEMANTIC) : SV_Target
            {
                UNITY_SETUP_INSTANCE_ID(IN);

                // One texture fetch per pixel; branch is coherent per triangle
                half4 col = IS_FRONT_VFACE(face, true, false)
                    ? SAMPLE_TEXTURE2D(_FrontTex, sampler_FrontTex, IN.uv.xy) * _FrontColor
                    : SAMPLE_TEXTURE2D(_BackTex,  sampler_BackTex,  IN.uv.zw) * _BackColor;

                col.rgb = MixFog(col.rgb, IN.fogFactor);
                return col;
            }
            ENDHLSL
        }
    }
}
