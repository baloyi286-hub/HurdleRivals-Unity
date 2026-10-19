#if UNITY_EDITOR
using System;
using System.IO;
using UnityEditor;
using UnityEditor.Build.Reporting;
using UnityEngine;

namespace HurdleRivals.Editor
{
    public static class CIBuilder
    {
        public static void Build()
        {
            var targetName = Environment.GetEnvironmentVariable("BUILD_TARGET") ?? "Android";
            var target = targetName == "StandaloneLinux64" ? BuildTarget.StandaloneLinux64 : BuildTarget.Android;
            var output = Environment.GetEnvironmentVariable("BUILD_OUTPUT");
            if (string.IsNullOrEmpty(output))
                output = target == BuildTarget.Android ? "Builds/Android/HurdleRivals.apk" : "Builds/Linux/HurdleRivals.x86_64";

            HurdleRivalsSetup.Configure();
            var scenePath = "Assets/Scenes/Race.unity";
            if (!File.Exists(scenePath))
                throw new FileNotFoundException("Game scene missing", scenePath);

            var absoluteOutput = Path.GetFullPath(output);
            Directory.CreateDirectory(Path.GetDirectoryName(absoluteOutput));
            if (target == BuildTarget.Android)
            {
                EditorUserBuildSettings.buildAppBundle = false;
                PlayerSettings.Android.targetArchitectures = AndroidArchitecture.ARM64;
                PlayerSettings.Android.minSdkVersion = AndroidSdkVersions.AndroidApiLevel26;
            }

            var options = new BuildPlayerOptions
            {
                scenes = new[] { scenePath },
                locationPathName = absoluteOutput,
                target = target,
                options = BuildOptions.StrictMode
            };
            Debug.Log("Building Hurdle Rivals for " + target + " at " + absoluteOutput);
            var report = BuildPipeline.BuildPlayer(options);
            if (report.summary.result != BuildResult.Succeeded)
                throw new InvalidOperationException("Unity build failed: " + report.summary.result +
                                                    " (" + report.summary.totalErrors + " errors)");
            Debug.Log("Unity build succeeded: " + absoluteOutput);
        }
    }
}
#endif
