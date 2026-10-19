#if UNITY_EDITOR
using UnityEditor;
using UnityEditor.SceneManagement;
using UnityEngine;

namespace HurdleRivals.Editor
{
    public static class HurdleRivalsSetup
    {
        [MenuItem("Hurdle Rivals/Configure Project")]
        public static void Configure()
        {
            System.IO.Directory.CreateDirectory("Assets/Scenes");
            var scene = EditorSceneManager.NewScene(NewSceneSetup.EmptyScene, NewSceneMode.Single);
            EditorSceneManager.SaveScene(scene, "Assets/Scenes/Race.unity");
            EditorBuildSettings.scenes = new[] { new EditorBuildSettingsScene("Assets/Scenes/Race.unity", true) };
            PlayerSettings.productName = "Hurdle Rivals";
            PlayerSettings.companyName = "Hurdle Rivals";
            PlayerSettings.SetApplicationIdentifier(NamedBuildTarget.Android, "com.hurdlerivals.tv");
            PlayerSettings.defaultInterfaceOrientation = UIOrientation.LandscapeLeft;
            PlayerSettings.Android.minSdkVersion = AndroidSdkVersions.AndroidApiLevel26;
            PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
            AssetDatabase.SaveAssets();
        }
    }
}
#endif
