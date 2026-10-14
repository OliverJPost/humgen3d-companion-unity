// Finds the Human Generator export an asset belongs to, through the manifest of the export.
//
// Human Generator writes `<Name>.humgen3d.json` next to every exported character: which file is
// the character, which are its animation clips, what every material is and which texture files
// it has. The companion only sets up a model, clip or texture that a manifest claims, so it never
// touches anything else in the project and does not depend on the naming scheme of the export.
// Without a manifest Unity's own import happens. The manifest is read from disk, so it does not
// matter whether Unity has imported it yet.
using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEngine;

namespace HumGen3D.Companion
{
    /// <summary>What the companion sets up a material as.</summary>
    internal enum MaterialKind { Opaque, Cards, Cap }

    /// <summary>A material of the export, as the manifest describes it.</summary>
    internal sealed class ExportMaterial
    {
        public string Name;
        /// <summary>The part of the character, e.g. Skin, HairCards.</summary>
        public string Part;
        /// <summary>body, skin, eyes, eyes_outer, eyes_inner, teeth, haircap, face_haircap, hair_cards or clothing.</summary>
        public string Type;
        /// <summary>Project-relative path of the texture file of each pass (base_color, normal, ...); embedded textures are left out.</summary>
        public Dictionary<string, string> Textures = new Dictionary<string, string>();

        public bool IsSkin => Type == "skin";

        public MaterialKind Kind
        {
            get
            {
                switch (Type)
                {
                    case "hair_cards": return MaterialKind.Cards;
                    case "haircap":
                    case "face_haircap": return MaterialKind.Cap;
                    default: return MaterialKind.Opaque;
                }
            }
        }

        public string Texture(string pass)
        {
            string path;
            return Textures.TryGetValue(pass, out path) ? path : null;
        }
    }

    /// <summary>The manifest of one export: its files, materials and the settings it was made with.</summary>
    internal sealed class HumGenManifest
    {
        /// <summary>The newest manifest format this companion reads, the `humgen3d_export` key.</summary>
        public const int SupportedFormat = 1;
        public const string Extension = ".humgen3d.json";
        const string FormatKey = "humgen3d_export";

        public string Path;
        public int Format;
        public string Name;
        /// <summary>Project-relative path of the character file.</summary>
        public string CharacterPath;
        /// <summary>Project-relative paths of the files with only animation clips.</summary>
        public List<string> AnimationPaths = new List<string>();
        public Dictionary<string, ExportMaterial> Materials = new Dictionary<string, ExportMaterial>();
        /// <summary>`settings.textures.normal_map` of the export: "opengl" or "directx".</summary>
        public string NormalMap;

        // Parsed manifests by path, redone when the file changes
        static readonly Dictionary<string, KeyValuePair<DateTime, HumGenManifest>> cache = new Dictionary<string, KeyValuePair<DateTime, HumGenManifest>>();
        static readonly HashSet<string> warned = new HashSet<string>();

        /// <summary>The manifest at a project-relative path, null when it is missing, not a manifest or of a newer format.</summary>
        public static HumGenManifest Load(string path)
        {
            DateTime written;
            try { written = File.GetLastWriteTimeUtc(path); }
            catch (Exception) { return null; }
            KeyValuePair<DateTime, HumGenManifest> cached;
            HumGenManifest manifest;
            if (cache.TryGetValue(path, out cached) && cached.Key == written)
                manifest = cached.Value;
            else
            {
                manifest = Read(path);
                cache[path] = new KeyValuePair<DateTime, HumGenManifest>(written, manifest);
            }
            if (manifest == null)
                return null;
            if (manifest.Format > SupportedFormat)
            {
                if (warned.Add(path))
                    Debug.LogWarning(HumGenPostprocessor.LogPrefix + path + " was made by a newer Human Generator 3D (export format "
                        + manifest.Format + "), update the Companion to set up this character. Unity imports it as it is.");
                return null;
            }
            return manifest;
        }

        static HumGenManifest Read(string path)
        {
            Dictionary<string, object> data;
            try { data = HumGenJson.Parse(File.ReadAllText(path)) as Dictionary<string, object>; }
            catch (Exception) { return null; }
            if (data == null || !(data.TryGetValue(FormatKey, out var format) && format is double))
                return null;
            var folder = Normalize(System.IO.Path.GetDirectoryName(path));
            var manifest = new HumGenManifest { Path = path, Format = (int)(double)format, Name = data.TryGetValue("name", out var name) ? name as string : null };
            var files = Get(data, "files");
            manifest.CharacterPath = Resolve(folder, files != null && files.TryGetValue("character", out var character) ? character as string : null);
            if (files != null && files.TryGetValue("animations", out var animations) && animations is List<object> list)
                manifest.AnimationPaths = list.OfType<string>().Select(a => Resolve(folder, a)).Where(a => a != null).ToList();
            var materials = Get(data, "materials");
            if (materials != null)
            {
                foreach (var entry in materials)
                {
                    var material = entry.Value as Dictionary<string, object>;
                    if (material == null)
                        continue;
                    var result = new ExportMaterial
                    {
                        Name = entry.Key,
                        Part = material.TryGetValue("part", out var part) ? part as string : null,
                        Type = material.TryGetValue("type", out var type) ? type as string : null,
                    };
                    var textures = Get(material, "textures");
                    if (textures != null)
                        foreach (var texture in textures)
                        {
                            // "file" is null for a texture embedded in the character file
                            var pass = texture.Value as Dictionary<string, object>;
                            var file = pass != null && pass.TryGetValue("file", out var relative) ? Resolve(folder, relative as string) : null;
                            if (file != null)
                                result.Textures[texture.Key] = file;
                        }
                    manifest.Materials[entry.Key] = result;
                }
            }
            var textureSettings = Get(Get(data, "settings"), "textures");
            if (textureSettings != null && textureSettings.TryGetValue("normal_map", out var normalMap))
                manifest.NormalMap = normalMap as string;
            return manifest;
        }

        /// <summary>The manifests in a project-relative folder.</summary>
        public static IEnumerable<HumGenManifest> InFolder(string folder)
        {
            if (string.IsNullOrEmpty(folder) || !Directory.Exists(folder))
                yield break;
            foreach (var path in Directory.GetFiles(folder, "*" + Extension).Select(Normalize).OrderBy(p => p, StringComparer.Ordinal))
            {
                var manifest = Load(path);
                if (manifest != null)
                    yield return manifest;
            }
        }

        static Dictionary<string, object> Get(Dictionary<string, object> data, string key)
        {
            return data != null && data.TryGetValue(key, out var value) ? value as Dictionary<string, object> : null;
        }

        /// <summary>A path of the manifest, relative to its folder, as a project-relative path.</summary>
        static string Resolve(string folder, string relative)
        {
            if (string.IsNullOrEmpty(relative))
                return null;
            var parts = new List<string>();
            foreach (var part in (folder + "/" + relative.Replace('\\', '/')).Split('/'))
            {
                if (part.Length == 0 || part == ".")
                    continue;
                if (part == "..")
                {
                    if (parts.Count == 0)
                        return null;
                    parts.RemoveAt(parts.Count - 1);
                    continue;
                }
                parts.Add(part);
            }
            return string.Join("/", parts);
        }

        public static string Normalize(string path)
        {
            return (path ?? "").Replace('\\', '/');
        }

        public static bool SamePath(string a, string b)
        {
            return string.Equals(a, b, StringComparison.OrdinalIgnoreCase);
        }
    }

    /// <summary>The export a model, clip or texture belongs to, found through its manifest.</summary>
    internal sealed class HumGenExport
    {
        public HumGenManifest Manifest { get; private set; }

        /// <summary>Name of the character, from the manifest.</summary>
        public string Name => Manifest.Name;

        /// <summary>Project-relative path of the character file.</summary>
        public string ModelPath => Manifest.CharacterPath;

        /// <summary>Project-relative path of the manifest.</summary>
        public string ManifestPath => Manifest.Path;

        /// <summary>True when the asset is one of the files with only animation clips.</summary>
        public bool IsClip { get; private set; }

        /// <summary>The export a model asset is the character or a clip file of, or null when no manifest next to it claims it.</summary>
        public static HumGenExport FromModelPath(string assetPath)
        {
            if (string.IsNullOrEmpty(assetPath))
                return null;
            assetPath = HumGenManifest.Normalize(assetPath);
            foreach (var manifest in HumGenManifest.InFolder(System.IO.Path.GetDirectoryName(assetPath)))
            {
                if (HumGenManifest.SamePath(manifest.CharacterPath, assetPath))
                    return new HumGenExport { Manifest = manifest };
                if (manifest.AnimationPaths.Any(p => HumGenManifest.SamePath(p, assetPath)))
                    return new HumGenExport { Manifest = manifest, IsClip = true };
            }
            return null;
        }

        /// <summary>
        /// The export a texture is a file of, found in the texture's folder or a folder above it, or
        /// null when no manifest claims it. <paramref name="claims"/> are the materials that use it,
        /// with the pass it is for each.
        /// </summary>
        public static HumGenExport FromTexturePath(string assetPath, out List<KeyValuePair<ExportMaterial, string>> claims)
        {
            claims = new List<KeyValuePair<ExportMaterial, string>>();
            if (string.IsNullOrEmpty(assetPath))
                return null;
            assetPath = HumGenManifest.Normalize(assetPath);
            var folder = System.IO.Path.GetDirectoryName(assetPath);
            while (!string.IsNullOrEmpty(folder))
            {
                foreach (var manifest in HumGenManifest.InFolder(folder))
                {
                    foreach (var material in manifest.Materials.Values)
                        foreach (var texture in material.Textures)
                            if (HumGenManifest.SamePath(texture.Value, assetPath))
                                claims.Add(new KeyValuePair<ExportMaterial, string>(material, texture.Key));
                    if (claims.Count > 0)
                        return new HumGenExport { Manifest = manifest };
                }
                folder = System.IO.Path.GetDirectoryName(folder);
            }
            return null;
        }

        /// <summary>The material of the manifest with this name, or null when the manifest does not list it.</summary>
        public ExportMaterial FindMaterial(string materialName)
        {
            ExportMaterial material;
            return materialName != null && Manifest.Materials.TryGetValue(materialName, out material) ? material : null;
        }

        /// <summary>Project-relative paths of every texture file of this export.</summary>
        public string[] AllTextures()
        {
            return Manifest.Materials.Values.SelectMany(m => m.Textures.Values).Distinct().Where(File.Exists).ToArray();
        }

        /// <summary>Project-relative paths of the animation clip files of this export.</summary>
        public string[] ClipPaths()
        {
            return Manifest.AnimationPaths.Where(File.Exists).ToArray();
        }
    }
}
