// Two-sided alpha-tested hair cards for the Built-in render pipeline.
// The Standard shader has no two-sided option, so the Human Generator 3D Companion
// assigns this one to the *Cards materials of an export when the project uses Built-in.
// A back face is lit with its normal flipped, as Blender renders a two-sided plane.
Shader "Human Generator 3D/Hair Cutout"
{
    Properties
    {
        _Color ("Color", Color) = (1, 1, 1, 1)
        _MainTex ("Albedo (RGB) Alpha (A)", 2D) = "white" {}
        _Cutoff ("Alpha Cutoff", Range(0, 1)) = 0.5
        [Normal] _BumpMap ("Normal Map", 2D) = "bump" {}
        _BumpScale ("Normal Scale", Float) = 1.0
        _MetallicGlossMap ("Metallic (R) Smoothness (A)", 2D) = "white" {}
        _Metallic ("Metallic", Range(0, 1)) = 0.0
        _GlossMapScale ("Smoothness", Range(0, 1)) = 0.5
    }

    SubShader
    {
        Tags { "RenderType" = "TransparentCutout" "Queue" = "AlphaTest" "IgnoreProjector" = "True" }
        LOD 300
        Cull Off
        // Softens the cut-out edges when the camera uses MSAA
        AlphaToMask On

        CGPROGRAM
        #pragma surface surf Standard fullforwardshadows addshadow alphatest:_Cutoff
        #pragma target 3.0
        #include "UnityStandardUtils.cginc"

        sampler2D _MainTex;
        sampler2D _BumpMap;
        sampler2D _MetallicGlossMap;
        fixed4 _Color;
        half _BumpScale;
        half _Metallic;
        half _GlossMapScale;

        struct Input
        {
            float2 uv_MainTex;
            // Positive on a front face, negative on a back face
            float facing : VFACE;
        };

        void surf(Input IN, inout SurfaceOutputStandard o)
        {
            fixed4 albedo = tex2D(_MainTex, IN.uv_MainTex) * _Color;
            fixed4 metallicGloss = tex2D(_MetallicGlossMap, IN.uv_MainTex);
            o.Albedo = albedo.rgb;
            o.Alpha = albedo.a;
            fixed3 normal = UnpackScaleNormal(tex2D(_BumpMap, IN.uv_MainTex), _BumpScale);
            // The tangent-space normal of a back face points into the surface: flip it
            if (IN.facing < 0)
                normal.z = -normal.z;
            o.Normal = normal;
            o.Metallic = metallicGloss.r * _Metallic;
            o.Smoothness = metallicGloss.a * _GlossMapScale;
        }
        ENDCG
    }

    FallBack "Transparent/Cutout/Diffuse"
}
