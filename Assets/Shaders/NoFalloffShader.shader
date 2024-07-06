Shader "Binx/Experiments/No Falloff Light Receiver"
{
    Properties
    {
        _MainTex("Texture", 2D) = "white" {}
        _Threshold("Attenuation Threshold", Float) = 1
    }

    SubShader
    {
        Tags
        {
            "RenderType" = "AlphaTest" "RenderPipeline" = "UniversalPipeline"
        }

        Pass
        {
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag

            #pragma enable_d3d11_debug_symbols

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            struct VertData
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 uv : TEXCOORD0;
            };

            struct FragData
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD0;
                float3 normalWS : TEXCOORD1;
                float3 positionWS : TEXCOORD2;
                float4 shadowCoords : TEXCOORD3;
            };

            sampler2D _MainTex;
            float4 _MainTex_ST;

            float4 _BaseColor;

            FragData vert(VertData vertData)
            {
                const VertexPositionInputs positionInputs = GetVertexPositionInputs(vertData.positionOS.xyz);

                const VertexNormalInputs normalInputs = GetVertexNormalInputs(vertData.normalOS, vertData.tangentOS);

                FragData fragData;
                fragData.positionCS = positionInputs.positionCS;

                fragData.uv = TRANSFORM_TEX(vertData.uv, _MainTex);

                fragData.normalWS = normalInputs.normalWS;
                fragData.positionWS = TransformObjectToWorld(vertData.positionOS.xyz);

                fragData.shadowCoords = GetShadowCoord(positionInputs);

                return fragData;
            }

            float _Threshold;

            half4 frag(FragData fragData) : SV_Target
            {
                const float4 black = float4(0, 0, 0, 1);

                // if lit by anyone, return albedo
                half totalAdditionalLightContribution = 0;

                uint pixelLightCount = GetAdditionalLightsCount();

                LIGHT_LOOP_BEGIN(pixelLightCount)
                    {
                        const Light additionalLight = GetAdditionalLight(lightIndex, fragData.positionWS);

                        half attenuation = additionalLight.distanceAttenuation;

                        attenuation -= _Threshold;

                        // attenuation range is [0, inf].
                        // clamp to [0, 1] first
                        half attenuation01 = saturate(attenuation);

                        // then elevate to 1 if > 0, but < 1
                        attenuation01 = ceil(attenuation01);

                        half isInLight = AdditionalLightRealtimeShadow(lightIndex, fragData.positionWS,
                            additionalLight.direction);

                        const half additionalLightContribution = isInLight * attenuation01;

                        totalAdditionalLightContribution += additionalLightContribution;
                    }
                LIGHT_LOOP_END

                // despite saturating and ceiling, totalAdditionalLightContribution might still be
                // > 1. clamp to [0, 1] range for lerping.
                totalAdditionalLightContribution = saturate(totalAdditionalLightContribution);

                float4 sampledColor = tex2D(_MainTex, fragData.uv);
                float4 lerpedColor = lerp(black, sampledColor, totalAdditionalLightContribution);
                return lerpedColor;
            }
            ENDHLSL
        }
    }
}