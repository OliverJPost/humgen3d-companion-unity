// Hair cards for the Universal Render Pipeline, shaded as hair.
// A cut-out card lit as a flat surface reads as a ribbon: its highlight is a sheet across the
// card and it mirrors the sky. Hair reflects along its strands instead. This shader is a
// Kajiya-Kay strand model with the two highlights of Marschner (a white one and one tinted
// by the hair color, shifted apart along the strands), fed by the flow map the export bakes
// for the cards: the direction of the strands in the UV space of the card (RG) and a noise
// per strand (B) that breaks the highlights up and varies the color between strands. The
// cards are two-sided and alpha tested like the Hair Cutout URP shader, and keep its
// property set so the Companion sets both up the same way.
Shader "Human Generator 3D/Hair URP"
{
    Properties
    {
        // The property set of URP/Lit, so LitInput.hlsl and the depth and shadow passes work unchanged
        _WorkflowMode("WorkflowMode", Float) = 1.0

        [MainTexture] _BaseMap("Albedo", 2D) = "white" {}
        [MainColor] _BaseColor("Color", Color) = (1,1,1,1)

        _Cutoff("Alpha Cutoff", Range(0.0, 1.0)) = 0.5

        _Smoothness("Smoothness", Range(0.0, 1.0)) = 0.5
        _SmoothnessTextureChannel("Smoothness texture channel", Float) = 0

        _Metallic("Metallic", Range(0.0, 1.0)) = 0.0
        _MetallicGlossMap("Metallic", 2D) = "white" {}

        _SpecColor("Specular", Color) = (0.2, 0.2, 0.2)
        _SpecGlossMap("Specular", 2D) = "white" {}

        [ToggleOff] _SpecularHighlights("Specular Highlights", Float) = 1.0
        [ToggleOff] _EnvironmentReflections("Environment Reflections", Float) = 1.0

        _BumpScale("Scale", Float) = 1.0
        _BumpMap("Normal Map", 2D) = "bump" {}

        _Parallax("Scale", Range(0.005, 0.08)) = 0.005
        _ParallaxMap("Height Map", 2D) = "black" {}

        _OcclusionStrength("Strength", Range(0.0, 1.0)) = 1.0
        _OcclusionMap("Occlusion", 2D) = "white" {}

        [HDR] _EmissionColor("Color", Color) = (0,0,0)
        _EmissionMap("Emission", 2D) = "white" {}

        _DetailMask("Detail Mask", 2D) = "white" {}
        _DetailAlbedoMapScale("Scale", Range(0.0, 2.0)) = 1.0
        _DetailAlbedoMap("Detail Albedo x2", 2D) = "linearGrey" {}
        _DetailNormalMapScale("Scale", Range(0.0, 2.0)) = 1.0
        [Normal] _DetailNormalMap("Normal Map", 2D) = "bump" {}

        _ClearCoatMask("_ClearCoatMask", Float) = 0.0
        _ClearCoatSmoothness("_ClearCoatSmoothness", Float) = 0.0

        // Hair: the flow map of the export and the strand shading
        [NoScaleOffset] _FlowMap("Hair Flow (RG direction, B strand noise)", 2D) = "grey" {}
        _DiffuseWrap("Diffuse Wrap", Range(0.0, 1.0)) = 0.35
        _PrimaryStrength("Primary Highlight", Range(0.0, 2.0)) = 0.08
        _PrimaryShift("Primary Highlight Shift", Range(-1.0, 1.0)) = -0.15
        _PrimaryExponent("Primary Highlight Exponent", Range(1.0, 256.0)) = 80.0
        _SecondaryStrength("Secondary Highlight", Range(0.0, 2.0)) = 0.2
        _SecondaryShift("Secondary Highlight Shift", Range(-1.0, 1.0)) = 0.15
        _SecondaryExponent("Secondary Highlight Exponent", Range(1.0, 256.0)) = 24.0
        _ShiftNoise("Highlight Shift Noise", Range(0.0, 1.0)) = 0.6
        _StrandVariation("Strand Color Variation", Range(0.0, 1.0)) = 0.2
        // A card is faded out below this value of how much it faces the camera (0 from its
        // side, 1 from the front); 0 turns the fade off
        _EdgeFade("Edge Fade", Range(0.0, 1.0)) = 0.25
        // How much of the alpha a card keeps from its side: faded out completely, a lock
        // whose card turns its side to the camera halfway down is cut in two and its tip
        // floats in the air. At this value the solid strands stay above the cutoff.
        _EdgeFadeFloor("Edge Fade Floor", Range(0.0, 1.0)) = 0.7

        // Blending state: the Companion sets alpha clip, both faces and alpha to mask
        _Surface("__surface", Float) = 0.0
        _Blend("__blend", Float) = 0.0
        _Cull("__cull", Float) = 0.0
        [ToggleUI] _AlphaClip("__clip", Float) = 1.0
        [HideInInspector] _BlendOp("__blendop", Float) = 0.0
        [HideInInspector] _SrcBlend("__src", Float) = 1.0
        [HideInInspector] _DstBlend("__dst", Float) = 0.0
        [HideInInspector] _SrcBlendAlpha("__srcA", Float) = 1.0
        [HideInInspector] _DstBlendAlpha("__dstA", Float) = 0.0
        [HideInInspector] _ZWrite("__zw", Float) = 1.0
        [HideInInspector] _BlendModePreserveSpecular("_BlendModePreserveSpecular", Float) = 1.0
        [HideInInspector] _AlphaToMask("__alphaToMask", Float) = 1.0
        [HideInInspector] _AddPrecomputedVelocity("_AddPrecomputedVelocity", Float) = 0.0
        [HideInInspector] _XRMotionVectorsPass("_XRMotionVectorsPass", Float) = 1.0

        [ToggleUI] _ReceiveShadows("Receive Shadows", Float) = 1.0
        _QueueOffset("Queue offset", Float) = 0.0

        // Legacy names of the Lit inspector
        [HideInInspector] _MainTex("BaseMap", 2D) = "white" {}
        [HideInInspector] _Color("Base Color", Color) = (1, 1, 1, 1)
        [HideInInspector] _GlossMapScale("Smoothness", Float) = 0.0
        [HideInInspector] _Glossiness("Smoothness", Float) = 0.0
        [HideInInspector] _GlossyReflections("EnvironmentReflections", Float) = 0.0

        [HideInInspector][NoScaleOffset] unity_Lightmaps("unity_Lightmaps", 2DArray) = "" {}
        [HideInInspector][NoScaleOffset] unity_LightmapsInd("unity_LightmapsInd", 2DArray) = "" {}
        [HideInInspector][NoScaleOffset] unity_ShadowMasks("unity_ShadowMasks", 2DArray) = "" {}
    }

    SubShader
    {
        // Skipped in a project without URP, so the includes below do not
        // fail to compile there; the Built-in pipeline uses its own shaders
        PackageRequirements
        {
            "com.unity.render-pipelines.universal": "14.0"
        }
        Tags
        {
            "RenderType" = "TransparentCutout"
            "RenderPipeline" = "UniversalPipeline"
            "UniversalMaterialType" = "Lit"
            "Queue" = "AlphaTest"
            "IgnoreProjector" = "True"
        }
        LOD 300

        HLSLINCLUDE
        float _EdgeFade;
        float _EdgeFadeFloor;

        // A card seen from its side is a line with all its strands pressed into it. The
        // card is faded out before that; the cards around it, or the card across it that
        // loose strands get, show the hair instead. From the normal of the card itself:
        // the normals of the mesh follow the shape of the head.
        float HairEdgeFade(float3 positionWS, float3 viewDirWS)
        {
            float3 cardNormal = normalize(cross(ddx(positionWS), ddy(positionWS)));
            float facing = abs(dot(cardNormal, viewDirWS));
            return lerp(_EdgeFadeFloor, 1.0, smoothstep(_EdgeFade * 0.3, max(_EdgeFade, 0.0001), facing));
        }
        ENDHLSL

        Pass
        {
            // Forward only: the strand model has no GBuffer layout, so the cards render
            // forward in both paths
            Name "ForwardLit"
            Tags
            {
                "LightMode" = "UniversalForwardOnly"
            }

            Blend[_SrcBlend][_DstBlend], [_SrcBlendAlpha][_DstBlendAlpha]
            ZWrite[_ZWrite]
            Cull[_Cull]
            AlphaToMask[_AlphaToMask]

            HLSLPROGRAM
            #pragma target 3.0

            #pragma vertex HairPassVertex
            #pragma fragment HairPassFragment

            // Material keywords, those of Lit that the inputs read
            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local _RECEIVE_SHADOWS_OFF
            #pragma shader_feature_local_fragment _ALPHATEST_ON
            #pragma shader_feature_local_fragment _METALLICSPECGLOSSMAP
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A
            #pragma shader_feature_local_fragment _SPECULAR_SETUP

            // Universal Pipeline keywords, those of URP 14 to 17; a keyword a version
            // doesn't know is a plain unset define
            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE _MAIN_LIGHT_SHADOWS_SCREEN
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ EVALUATE_SH_MIXED EVALUATE_SH_VERTEX
            #pragma multi_compile_fragment _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile_fragment _ _SHADOWS_SOFT _SHADOWS_SOFT_LOW _SHADOWS_SOFT_MEDIUM _SHADOWS_SOFT_HIGH
            #pragma multi_compile_fragment _ _SCREEN_SPACE_OCCLUSION
            #pragma multi_compile_fragment _ _LIGHT_COOKIES
            #pragma multi_compile _ _LIGHT_LAYERS
            #pragma multi_compile _ _FORWARD_PLUS
            #pragma multi_compile _ _CLUSTER_LIGHT_LOOP

            // Unity defined keywords
            #pragma multi_compile _ LIGHTMAP_SHADOW_MIXING
            #pragma multi_compile _ SHADOWS_SHADOWMASK
            #pragma multi_compile _ DIRLIGHTMAP_COMBINED
            #pragma multi_compile _ LIGHTMAP_ON
            #pragma multi_compile _ LOD_FADE_CROSSFADE
            #pragma multi_compile_fog

            #pragma multi_compile_instancing
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            TEXTURE2D(_FlowMap);
            SAMPLER(sampler_FlowMap);

            // Outside UnityPerMaterial (LitInput.hlsl owns that buffer), so the material is
            // not SRP Batcher compatible; a character has one or two hair materials
            CBUFFER_START(HumGenHair)
                half _DiffuseWrap;
                half _PrimaryStrength;
                half _PrimaryShift;
                half _PrimaryExponent;
                half _SecondaryStrength;
                half _SecondaryShift;
                half _SecondaryExponent;
                half _ShiftNoise;
                half _StrandVariation;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS : NORMAL;
                float4 tangentOS : TANGENT;
                float2 texcoord : TEXCOORD0;
                float2 staticLightmapUV : TEXCOORD1;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                half3 normalWS : TEXCOORD2;
                half4 tangentWS : TEXCOORD3; // w is the sign of the bitangent
                half fogFactor : TEXCOORD4;
#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                float4 shadowCoord : TEXCOORD5;
#endif
                DECLARE_LIGHTMAP_OR_SH(staticLightmapUV, vertexSH, 6);
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings HairPassVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);

                VertexPositionInputs vertexInput = GetVertexPositionInputs(input.positionOS.xyz);
                VertexNormalInputs normalInput = GetVertexNormalInputs(input.normalOS, input.tangentOS);
                output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
                output.positionWS = vertexInput.positionWS;
                output.positionCS = vertexInput.positionCS;
                output.normalWS = normalInput.normalWS;
                real sign = input.tangentOS.w * GetOddNegativeScale();
                output.tangentWS = half4(normalInput.tangentWS.xyz, sign);
                output.fogFactor = ComputeFogFactor(vertexInput.positionCS.z);
                OUTPUT_LIGHTMAP_UV(input.staticLightmapUV, unity_LightmapST, output.staticLightmapUV);
                OUTPUT_SH(output.normalWS.xyz, output.vertexSH);
#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                output.shadowCoord = GetShadowCoord(vertexInput);
#endif
                return output;
            }

            // Kajiya-Kay: the highlight of a strand depends on the angle between the strand
            // and the half vector, not on a normal
            half StrandSpecular(half3 strand, half3 halfVector, half exponent)
            {
                half dotTH = dot(strand, halfVector);
                half sinTH = sqrt(saturate(1.0h - dotTH * dotTH));
                half attenuation = smoothstep(-1.0h, 0.0h, dotTH);
                return attenuation * pow(sinTH, exponent);
            }

            half3 HairLighting(Light light, half3 albedo, half3 normalWS, half3 strandWS, half3 viewDirWS, half smoothness, half noise)
            {
                half3 lightDir = light.direction;
                half attenuation = light.distanceAttenuation * light.shadowAttenuation;
                half NdotL = dot(normalWS, lightDir);
                // A card is a flat stand-in for a round bundle: wrap the diffuse so it does not
                // go black where the bundle would still catch light
                half diffuse = saturate((NdotL + _DiffuseWrap) / (1.0h + _DiffuseWrap));
                half3 halfVector = normalize(lightDir + viewDirWS);
                half shift = (noise - 0.5h) * _ShiftNoise;
                half3 primaryStrand = normalize(strandWS + (_PrimaryShift + shift) * normalWS);
                half3 secondaryStrand = normalize(strandWS + (_SecondaryShift + shift) * normalWS);
                half exponentScale = 0.5h + smoothness;
                half primary = StrandSpecular(primaryStrand, halfVector, _PrimaryExponent * exponentScale);
                half secondary = StrandSpecular(secondaryStrand, halfVector, _SecondaryExponent * exponentScale);
                // The white highlight reflects off the surface of the hair, the colored one has
                // passed through it; the noise breaks the colored one up between strands
                half3 specular = _PrimaryStrength * primary + _SecondaryStrength * secondary * albedo * (0.5h + noise);
                // No highlight on the unlit side of a card
                specular *= smoothstep(-0.3h, 0.3h, NdotL);
                return light.color * attenuation * (albedo * diffuse + specular);
            }

            void HairPassFragment(
                Varyings input,
                FRONT_FACE_TYPE cullFace : FRONT_FACE_SEMANTIC,
                out half4 outColor : SV_Target0)
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);

                half4 albedoAlpha = SampleAlbedoAlpha(input.uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap));
                half fade = HairEdgeFade(input.positionWS, GetWorldSpaceNormalizeViewDir(input.positionWS));
                half alpha = Alpha(albedoAlpha.a * fade, _BaseColor, _Cutoff);
                half3 albedo = albedoAlpha.rgb * _BaseColor.rgb;
                half4 specGloss = SampleMetallicSpecGloss(input.uv, albedoAlpha.a);
                half smoothness = specGloss.a;
                half4 flow = SAMPLE_TEXTURE2D(_FlowMap, sampler_FlowMap, input.uv);
                half noise = flow.b;
                albedo *= 1.0h + (noise - 0.5h) * 2.0h * _StrandVariation;

                float3 viewDirWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
                // The normals follow the shape of the head, not the card, so which face of a
                // card is seen says little about them: a card across the hair has both faces
                // along its normal. Both sides of a card are lit, by turning the normal
                // towards the camera by its own direction instead of by the face, or such a
                // card is lit triangle by triangle.
                half3 normalWS = normalize(input.normalWS);
                half3 meshTangentWS = normalize(input.tangentWS.xyz);
                half3 meshBitangentWS = cross(normalWS, meshTangentWS) * input.tangentWS.w;
                if (dot(normalWS, viewDirWS) < 0.0)
                    normalWS = -normalWS;

                // The U and V axes of the card. The tangents of the mesh are made
                // perpendicular to the normals, which lie in the plane of a card that stands
                // on the head or crosses another one: there the axes come from how the
                // position and the UV change over the screen instead, which is exact but
                // constant over a triangle.
                float3 positionDx = ddx(input.positionWS);
                float3 positionDy = ddy(input.positionWS);
                float2 uvDx = ddx(input.uv);
                float2 uvDy = ddy(input.uv);
                float3 cardNormal = normalize(cross(positionDx, positionDy));
                float3 perpendicularDx = cross(cardNormal, positionDx);
                float3 perpendicularDy = cross(positionDy, cardNormal);
                half3 cardU = normalize(perpendicularDy * uvDx.x + perpendicularDx * uvDy.x);
                half3 cardV = normalize(perpendicularDy * uvDx.y + perpendicularDx * uvDy.y);
                half meshFrame = smoothstep(0.2h, 0.5h, abs(dot(cardNormal, normalWS)));
                cardU = normalize(lerp(cardU, meshTangentWS, meshFrame));
                cardV = normalize(lerp(cardV, meshBitangentWS, meshFrame));

                // The frame of the normal map: the axes of the card, made perpendicular to
                // the normal from the one that is the least along it
                half3 across = cardU - normalWS * dot(normalWS, cardU);
                half3 down = cardV - normalWS * dot(normalWS, cardV);
                half3 tangentWS;
                half3 bitangentWS;
                if (dot(across, across) >= dot(down, down))
                {
                    tangentWS = normalize(across);
                    bitangentWS = cross(normalWS, tangentWS);
                    bitangentWS *= dot(bitangentWS, cardV) < 0.0 ? -1.0 : 1.0;
                }
                else
                {
                    bitangentWS = normalize(down);
                    tangentWS = cross(bitangentWS, normalWS);
                    tangentWS *= dot(tangentWS, cardU) < 0.0 ? -1.0 : 1.0;
                }
#if defined(_NORMALMAP)
                half3 normalTS = SampleNormal(input.uv, TEXTURE2D_ARGS(_BumpMap, sampler_BumpMap), _BumpScale);
                half3x3 tangentToWorld = half3x3(tangentWS, bitangentWS, normalWS);
                half3 shadingNormalWS = normalize(TransformTangentToWorld(normalTS, tangentToWorld));
#else
                half3 shadingNormalWS = normalWS;
#endif
                // The strand direction from the flow map; straight down the card (its V axis,
                // root to tip) when the map is missing or empty
                half2 direction = flow.rg * 2.0h - 1.0h;
                half3 strandWS = direction.x * cardU + direction.y * cardV;
                strandWS = dot(direction, direction) < 0.01h ? -cardV : normalize(strandWS);

                InputData inputData = (InputData)0;
                inputData.positionWS = input.positionWS;
                inputData.normalWS = shadingNormalWS;
                inputData.viewDirectionWS = GetWorldSpaceNormalizeViewDir(input.positionWS);
#if defined(REQUIRES_VERTEX_SHADOW_COORD_INTERPOLATOR)
                inputData.shadowCoord = input.shadowCoord;
#elif defined(MAIN_LIGHT_CALCULATE_SHADOWS)
                inputData.shadowCoord = TransformWorldToShadowCoord(inputData.positionWS);
#else
                inputData.shadowCoord = float4(0, 0, 0, 0);
#endif
                inputData.fogCoord = input.fogFactor;
                inputData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(input.positionCS);
                inputData.shadowMask = SAMPLE_SHADOWMASK(input.staticLightmapUV);
                inputData.bakedGI = SAMPLE_GI(input.staticLightmapUV, input.vertexSH, inputData.normalWS);

                half4 shadowMask = CalculateShadowMask(inputData);
                AmbientOcclusionFactor aoFactor = CreateAmbientOcclusionFactor(inputData.normalizedScreenSpaceUV, 1.0h);
                Light mainLight = GetMainLight(inputData, shadowMask, aoFactor);
                MixRealtimeAndBakedGI(mainLight, inputData.normalWS, inputData.bakedGI);

                half3 color = inputData.bakedGI * albedo * aoFactor.indirectAmbientOcclusion;
                color += HairLighting(mainLight, albedo, inputData.normalWS, strandWS, inputData.viewDirectionWS, smoothness, noise);

#if defined(_ADDITIONAL_LIGHTS)
                uint pixelLightCount = GetAdditionalLightsCount();
#if USE_FORWARD_PLUS
                for (uint lightIndex = 0; lightIndex < min(URP_FP_DIRECTIONAL_LIGHTS_COUNT, MAX_VISIBLE_LIGHTS); lightIndex++)
                {
                    Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);
                    color += HairLighting(light, albedo, inputData.normalWS, strandWS, inputData.viewDirectionWS, smoothness, noise);
                }
#endif
                LIGHT_LOOP_BEGIN(pixelLightCount)
                    Light light = GetAdditionalLight(lightIndex, inputData, shadowMask, aoFactor);
                    color += HairLighting(light, albedo, inputData.normalWS, strandWS, inputData.viewDirectionWS, smoothness, noise);
                LIGHT_LOOP_END
#endif

                color = MixFog(color, inputData.fogCoord);
                // The coverage for alpha to mask
                outColor = half4(color, alpha);
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
            Cull[_Cull]

            HLSLPROGRAM
            #pragma target 2.0

            #pragma vertex ShadowPassVertex
            #pragma fragment ShadowPassFragment

            #pragma shader_feature_local _ALPHATEST_ON
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            #pragma multi_compile_instancing
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            #pragma multi_compile _ LOD_FADE_CROSSFADE
            #pragma multi_compile_vertex _ _CASTING_PUNCTUAL_LIGHT_SHADOW

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/Shaders/ShadowCasterPass.hlsl"
            ENDHLSL
        }

        Pass
        {
            Name "DepthOnly"
            Tags
            {
                "LightMode" = "DepthOnly"
            }

            ZWrite On
            ColorMask R
            Cull[_Cull]

            HLSLPROGRAM
            #pragma target 2.0

            #pragma vertex DepthOnlyVertex
            #pragma fragment DepthOnlyFragment

            #pragma shader_feature_local _ALPHATEST_ON
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            #pragma multi_compile _ LOD_FADE_CROSSFADE

            #pragma multi_compile_instancing
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #if defined(LOD_FADE_CROSSFADE)
                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/LODCrossFade.hlsl"
            #endif

            // The depth pass of Lit with the edge fade of the forward pass, so both cut
            // the same pixels out
            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 texcoord : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float2 uv : TEXCOORD0;
                float3 positionWS : TEXCOORD1;
                float4 positionCS : SV_POSITION;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings DepthOnlyVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
                output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
                output.positionCS = TransformWorldToHClip(output.positionWS);
                return output;
            }

            half DepthOnlyFragment(Varyings input) : SV_TARGET
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                #if defined(_ALPHATEST_ON)
                    half fade = HairEdgeFade(input.positionWS, GetWorldSpaceNormalizeViewDir(input.positionWS));
                    Alpha(SampleAlbedoAlpha(input.uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap)).a * fade, _BaseColor, _Cutoff);
                #endif
                #if defined(LOD_FADE_CROSSFADE)
                    LODFadeCrossFade(input.positionCS);
                #endif
                return input.positionCS.z;
            }
            ENDHLSL
        }

        Pass
        {
            // Depth and normals of a forward-only material, for ambient occlusion and decals
            Name "DepthNormalsOnly"
            Tags
            {
                "LightMode" = "DepthNormalsOnly"
            }

            ZWrite On
            Cull[_Cull]

            HLSLPROGRAM
            #pragma target 2.0

            #pragma vertex DepthNormalsVertex
            #pragma fragment DepthNormalsFragment

            #pragma shader_feature_local _NORMALMAP
            #pragma shader_feature_local _ALPHATEST_ON
            #pragma shader_feature_local_fragment _SMOOTHNESS_TEXTURE_ALBEDO_CHANNEL_A

            #pragma multi_compile_fragment _ _GBUFFER_NORMALS_OCT
            #pragma multi_compile _ LOD_FADE_CROSSFADE

            #pragma multi_compile_instancing
            #include_with_pragmas "Packages/com.unity.render-pipelines.universal/ShaderLibrary/DOTS.hlsl"

            #include "Packages/com.unity.render-pipelines.universal/Shaders/LitInput.hlsl"
            #if defined(LOD_FADE_CROSSFADE)
                #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/LODCrossFade.hlsl"
            #endif

            // The depth and normals pass of Lit with the edge fade of the forward pass
            struct Attributes
            {
                float4 positionOS : POSITION;
                float2 texcoord : TEXCOORD0;
                float3 normalOS : NORMAL;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionCS : SV_POSITION;
                float2 uv : TEXCOORD1;
                half3 normalWS : TEXCOORD2;
                float3 positionWS : TEXCOORD3;
                UNITY_VERTEX_INPUT_INSTANCE_ID
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings DepthNormalsVertex(Attributes input)
            {
                Varyings output = (Varyings)0;
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_TRANSFER_INSTANCE_ID(input, output);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(output);
                output.uv = TRANSFORM_TEX(input.texcoord, _BaseMap);
                output.positionWS = TransformObjectToWorld(input.positionOS.xyz);
                output.positionCS = TransformWorldToHClip(output.positionWS);
                output.normalWS = half3(TransformObjectToWorldNormal(input.normalOS));
                return output;
            }

            void DepthNormalsFragment(Varyings input, out half4 outNormalWS : SV_Target0)
            {
                UNITY_SETUP_INSTANCE_ID(input);
                UNITY_SETUP_STEREO_EYE_INDEX_POST_VERTEX(input);
                #if defined(_ALPHATEST_ON)
                    half fade = HairEdgeFade(input.positionWS, GetWorldSpaceNormalizeViewDir(input.positionWS));
                    Alpha(SampleAlbedoAlpha(input.uv, TEXTURE2D_ARGS(_BaseMap, sampler_BaseMap)).a * fade, _BaseColor, _Cutoff);
                #endif
                #if defined(LOD_FADE_CROSSFADE)
                    LODFadeCrossFade(input.positionCS);
                #endif

                // The normal of the mesh, the shape of the head: the detail of the normal map
                // is for the lighting of the strands
                float3 normalWS = NormalizeNormalPerPixel(input.normalWS);
                #if defined(_GBUFFER_NORMALS_OCT)
                    float2 octNormalWS = PackNormalOctQuadEncode(normalWS);
                    float2 remappedOctNormalWS = saturate(octNormalWS * 0.5 + 0.5);
                    outNormalWS = half4(PackFloat2To888(remappedOctNormalWS), 0.0);
                #else
                    outNormalWS = half4(normalWS, 0.0);
                #endif
            }
            ENDHLSL
        }
    }

    // The error shader of every project, the URP one does not exist without URP
    FallBack "Hidden/InternalErrorShader"
}
