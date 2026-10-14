// Menu item that reimports selected Human Generator exports, for characters that were imported
// before the companion was installed.
using System.Collections.Generic;
using System.IO;
using System.Linq;
using UnityEditor;
using UnityEngine;

namespace HumGen3D.Companion
{
    public static class HumGenMenu
    {
        const string MenuPath = "Human Generator 3D/Set Up Selected Characters";

        [MenuItem(MenuPath, true)]
        static bool CanSetUpSelected()
        {
            return Selection.assetGUIDs.Length > 0;
        }

        [MenuItem(MenuPath)]
        static void SetUpSelected()
        {
            var exports = new Dictionary<string, HumGenExport>();
            foreach (var guid in Selection.assetGUIDs)
            {
                var path = AssetDatabase.GUIDToAssetPath(guid);
                var candidates = AssetDatabase.IsValidFolder(path)
                    ? Directory.GetFiles(path, "*.fbx", SearchOption.AllDirectories).Select(p => p.Replace('\\', '/'))
                    : new[] { path };
                foreach (var candidate in candidates)
                {
                    var export = HumGenExport.FromModelPath(candidate);
                    if (export != null)
                        exports[export.ModelPath] = export;
                }
            }
            if (exports.Count == 0)
            {
                Debug.LogWarning("Human Generator 3D Companion: the selection holds no Human Generator export "
                    + "(a .fbx with its <Name>.humgen3d.json manifest next to it).");
                return;
            }

            AssetDatabase.StartAssetEditing();
            try
            {
                foreach (var export in exports.Values)
                {
                    foreach (var texture in export.AllTextures())
                        AssetDatabase.ImportAsset(texture, ImportAssetOptions.ForceUpdate);
                    AssetDatabase.ImportAsset(export.ModelPath, ImportAssetOptions.ForceUpdate);
                    foreach (var clip in export.ClipPaths())
                        AssetDatabase.ImportAsset(clip, ImportAssetOptions.ForceUpdate);
                }
            }
            finally
            {
                AssetDatabase.StopAssetEditing();
            }
        }
    }
}
