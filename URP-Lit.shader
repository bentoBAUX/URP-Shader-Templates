Shader "bentoBAUX/URP Lit"
{
    Properties
    {
        _BaseColor ("Base Color", Color) = (1,1,1,1)
        _BaseMap ("Base Map", 2D) = "white" {}
        [Normal]_NormalMap ("Normal Map", 2D) = "bump" {}
        _NormalStrength ("Normal Strength", Range(0,3)) = 1
    }

    SubShader
    {
        Tags
        {
            "RenderType"="Opaque" "RenderPipeline"="UniversalPipeline"
        }

        Pass
        {
            Name "ForwardLit"
            Tags
            {
                "LightMode"="UniversalForward"
            }

            HLSLPROGRAM
            // ===== Pragmas =====
            #pragma vertex   vert
            #pragma fragment frag
            #pragma target 3.0

            // Fog (we keep a simple per-object fog factor)
            #pragma multi_compile_fog

            // Lighting variants
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile_fragment _ _SHADOWS_SOFT
            #pragma multi_compile _ _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHTS_VERTEX
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS

            // Normal map keyword (optional)
            #pragma multi_compile _ _NORMALMAP

            // ===== Includes =====
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/ShaderVariablesFunctions.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Shadows.hlsl"
            // ===== Material params (SRP Batcher) =====
            CBUFFER_START(UnityPerMaterial)
                half4 _BaseColor;
                float4 _BaseMap_ST;
                half _NormalStrength;
            CBUFFER_END

            TEXTURE2D(_BaseMap);
            SAMPLER(sampler_BaseMap);
            TEXTURE2D(_NormalMap);
            SAMPLER(sampler_NormalMap);

            // ===== I/O structs =====
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
                float3 normalWS : TEXCOORD1;
                float3x3 TBN : TEXCOORD2; // STORED AS world->tangent
                float2 uv : TEXCOORD5;
                float4 shadowCoord : TEXCOORD6; // main light shadows
                float fogFactor : TEXCOORD7; // per-object fog (optional)
            };

            // ===== Helpers =====

            // Build world->tangent matrix (so transpose gives tangent->world)
            float3x3 BuildWorldToTangent(float3 normalWS, float4 tangentOS)
            {
                // Tangent/bitangent in world space
                float3x3 objectToWorld3x3 = (float3x3)GetObjectToWorldMatrix();
                float3 T = normalize(mul(objectToWorld3x3, tangentOS.xyz));
                float3 N = normalize(normalWS);
                float3 B = normalize(cross(N, T) * tangentOS.w);

                // Tangent-to-world (columns are world axes of tangent space)
                float3x3 tangentToWorld = float3x3(T, B, N);

                // Return world->tangent (inverse for orthonormal basis = transpose)
                return transpose(tangentToWorld);
            }

            // Your requested modular function: consumes v2f/Varyings and returns world-space normal
            half3 ProcessNormals(Varyings IN)
            {
                #if defined(_NORMALMAP)
                    // Tangent-space normal from normal map
                    half3 nTS = UnpackNormal(SAMPLE_TEXTURE2D(_NormalMap, sampler_NormalMap, IN.uv));
                    nTS.xy *= _NormalStrength;

                    // IN.TBN is world->tangent, so transpose(TBN) = tangent->world
                    return normalize(mul(transpose(IN.TBN), nTS));
                #else
                return normalize(IN.normalWS);
                #endif
            }

            // Simple per-object fog blend using URP camera params
            void ApplyFog(inout float3 rgb, float3 positionWS)
            {
                #if defined(FOG_LINEAR) || defined(FOG_EXP) || defined(FOG_EXP2)
                    float viewZ       = -TransformWorldToView(positionWS).z;
                    float nearZ0ToFar = max(viewZ - _ProjectionParams.y, 0);
                    float fogAmt      = 1.0 - ComputeFogIntensity(ComputeFogFactorZ0ToFar(nearZ0ToFar));
                    rgb = lerp(rgb, unity_FogColor.rgb, fogAmt);
                #endif
            }

            // Evaluate Lambert for a single light
            float3 Lambert(float3 N, float3 L, float3 lightColor, float atten)
            {
                float ndl = saturate(dot(N, L));
                return lightColor * (ndl * atten);
            }

            // ===== Vertex =====
            Varyings vert(Attributes IN)
            {
                Varyings OUT;

                VertexPositionInputs pos = GetVertexPositionInputs(IN.positionOS.xyz);
                VertexNormalInputs nrm = GetVertexNormalInputs(IN.normalOS, IN.tangentOS);

                OUT.positionHCS = pos.positionCS;
                OUT.positionWS = pos.positionWS;
                OUT.normalWS = nrm.normalWS;
                OUT.uv = TRANSFORM_TEX(IN.uv, _BaseMap);

                // Build world->tangent TBN and pass it along
                OUT.TBN = BuildWorldToTangent(nrm.normalWS, IN.tangentOS);

                // Shadow coord for main light
                OUT.shadowCoord = TransformWorldToShadowCoord(pos.positionWS);

                // Precompute fog factor (optional; we just store scalar intensity)
                #if defined(FOG_LINEAR) || defined(FOG_EXP) || defined(FOG_EXP2)
                    float viewZ       = -TransformWorldToView(pos.positionWS).z;
                    float nearZ0ToFar = max(viewZ - _ProjectionParams.y, 0);
                    OUT.fogFactor     = 1.0 - ComputeFogIntensity(ComputeFogFactorZ0ToFar(nearZ0ToFar));
                #else
                OUT.fogFactor = 0.0;
                #endif

                return OUT;
            }

            // ===== Fragment =====
            half4 frag(Varyings IN) : SV_Target
            {
                // Material inputs
                float4 baseSample = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv);
                float3 albedo = baseSample.rgb * _BaseColor.rgb;
                float alpha = baseSample.a * _BaseColor.a;

                // Normal in world space (via your modular function)
                float3 N = ProcessNormals(IN);

                // --- Indirect diffuse (SH / probes) ---
                float3 indirect = SampleSH(N) * albedo;

                // --- Main light ---
                Light mainL = GetMainLight(IN.shadowCoord);
                float3 Lm = normalize(mainL.direction);
                float3 directMain = Lambert(N, Lm, mainL.color.rgb, mainL.shadowAttenuation) * albedo;

                // --- Additional lights ---
                float3 directAdd = 0;
                #if defined(_ADDITIONAL_LIGHTS)
                {
                    uint count = GetAdditionalLightsCount();
                    for (uint i = 0u; i < count; i++)
                    {
                        Light l = GetAdditionalLight(i, IN.positionWS);
                        float3 L = normalize(l.direction);
                        float atten = l.distanceAttenuation * l.shadowAttenuation;
                        directAdd += EvalLambert(N, L, l.color.rgb, atten) * albedo;
                    }
                }
                #endif

                float3 color = indirect + directMain + directAdd;

                // Per-object fog (using precomputed scalar factor stored in varyings)
                #if defined(FOG_LINEAR) || defined(FOG_EXP) || defined(FOG_EXP2)
                    color = lerp(color, unity_FogColor.rgb, IN.fogFactor);
                #endif

                return half4(color, alpha);
            }
            ENDHLSL
        }
        Pass
        {
            Name "ShadowCaster"
            Tags
            {
                "LightMode" = "ShadowCaster"
            }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Off

            HLSLPROGRAM
            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment
            #pragma target 2.0

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }

    }
}