Shader "bentoBAUX/URP Unlit"
{
    Properties
    {
        _BaseColor("Base Color", Color) = (1, 1, 1, 1)
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "Opaque" "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ShaderVariablesFunctions.hlsl"

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float3 positionWS : TEXCOORD0;
                float3 positionOS : TEXCOORD1;
                float3x3 TBN : TEXCOORD2;
                float2 uv : TEXCOORD5;

                float  fogFactor : TEXCOORD6;
            };

            // To make the Unity shader SRP Batcher compatible, declare all
            // properties related to a Material in a a single CBUFFER block with
            // the name UnityPerMaterial.
            CBUFFER_START(UnityPerMaterial)
                // The following line declares the _BaseColor variable, so that you
                // can use it in the fragment shader.
                half4 _BaseColor;
            CBUFFER_END

            // https://discussions.unity.com/t/how-to-compute-fog-in-hlsl-on-urp/943637
            void Applyfog(inout float4 color, float3 positionWS)
            {
                float4 inColor = color;

                #if defined(FOG_LINEAR) || defined(FOG_EXP) || defined(FOG_EXP2)
                    float viewZ = -TransformWorldToView(positionWS).z;
                    float nearZ0ToFarZ = max(viewZ - _ProjectionParams.y, 0);
                    float density = 1.0f - ComputeFogIntensity(ComputeFogFactorZ0ToFar(nearZ0ToFarZ));

                    color = lerp(color, unity_FogColor,  density);
                #else
                color = color;
                #endif
            }

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                VertexPositionInputs pos = GetVertexPositionInputs(IN.positionOS);
                OUT.positionOS = IN.positionOS;
                OUT.positionWS = pos.positionWS;
                OUT.positionHCS = pos.positionCS;
                OUT.uv = IN.uv;
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                float4 finalColor = _BaseColor;
                Applyfog(finalColor, IN.positionWS);
                return finalColor;
            }
            ENDHLSL
        }
    }
}
