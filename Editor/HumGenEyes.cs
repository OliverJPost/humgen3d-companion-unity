// The eye shader in URP: everything the companion does for it that is not a line in the
// shared code. To drop the eye shader, delete this file and Shaders/HumGen3D_EyeURP.shader and
// remove the lines marked "[eye shader]" in HumGenImportOptions.cs and HumGenPostprocessor.cs;
// the eyes then get URP/Lit with the smoothness of the export, as before.
using UnityEngine;

namespace HumGen3D.Companion
{
    public enum EyeShading
    {
        /// <summary>The package's Eye URP shader: the iris refracted behind the cornea, the glint off the cornea.</summary>
        EyeShader = 0,
        /// <summary>Universal Render Pipeline/Lit.</summary>
        Lit = 1,
    }

    internal static class HumGenEyes
    {
        /// <summary>
        /// The eyes in URP: the inputs and cost of URP/Lit, with the iris sampled where the view
        /// ray refracted at the cornea meets it, the lights and the environment reflected off the
        /// smooth cornea at the reflectance of water instead of off the normal-mapped iris, a dark
        /// limbus and a pupil size. Its iris and pupil radii are those of the eye texture Human
        /// Generator bakes.
        /// </summary>
        public const string UrpShader = "Human Generator 3D/Eye URP";

        /// <summary>Whether a material of the export gets the eye shader.</summary>
        public static bool Wanted(ExportMaterial material, HumGenImportOptions options)
        {
            return material.Type == "eyes" && options.eyeShading == EyeShading.EyeShader;
        }

        public static Shader Find()
        {
            return Shader.Find(UrpShader);
        }
    }
}
