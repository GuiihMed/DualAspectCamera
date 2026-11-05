#!/usr/bin/env python3
import os
import json

base_dir = "/Users/guilherme-wdcom/.gemini/antigravity/scratch/DualAspectCamera"
proj_dir = os.path.join(base_dir, "DualAspectCamera.xcodeproj")
os.makedirs(proj_dir, exist_ok=True)

# Create Assets.xcassets
assets_dir = os.path.join(base_dir, "Assets.xcassets")
appicon_dir = os.path.join(assets_dir, "AppIcon.appiconset")
accent_dir = os.path.join(assets_dir, "AccentColor.colorset")
os.makedirs(appicon_dir, exist_ok=True)
os.makedirs(accent_dir, exist_ok=True)

with open(os.path.join(assets_dir, "Contents.json"), "w") as f:
    json.dump({"info": {"author": "xcode", "version": 1}}, f, indent=2)

with open(os.path.join(appicon_dir, "Contents.json"), "w") as f:
    json.dump({
        "images": [
            {
                "idiom": "universal",
                "platform": "ios",
                "size": "1024x1024"
            }
        ],
        "info": {"author": "xcode", "version": 1}
    }, f, indent=2)

with open(os.path.join(accent_dir, "Contents.json"), "w") as f:
    json.dump({
        "colors": [
            {
                "idiom": "universal",
                "color": {
                    "color-space": "srgb",
                    "components": {
                        "red": "0.98",
                        "green": "0.82",
                        "blue": "0.20",
                        "alpha": "1.000"
                    }
                }
            }
        ],
        "info": {"author": "xcode", "version": 1}
    }, f, indent=2)

# File IDs (24 hex characters)
FILE_APP_REF = "AA0000000000000000000001"
FILE_APP_BUILD = "BA0000000000000000000001"

FILE_MGR_REF = "AA0000000000000000000002"
FILE_MGR_BUILD = "BA0000000000000000000002"

FILE_VIEW_REF = "AA0000000000000000000003"
FILE_VIEW_BUILD = "BA0000000000000000000003"

FILE_ASSETS_REF = "AA0000000000000000000004"
FILE_ASSETS_BUILD = "BA0000000000000000000004"

FILE_PLIST_REF = "AA0000000000000000000005"

PROD_REF = "AA0000000000000000000006"

GRP_MAIN = "CA0000000000000000000001"
GRP_PROD = "CA0000000000000000000002"

TARGET_ID = "DA0000000000000000000001"
PROJECT_ID = "EA0000000000000000000001"

PHASE_SOURCES = "FA0000000000000000000001"
PHASE_FRAMEWORKS = "FA0000000000000000000002"
PHASE_RESOURCES = "FA0000000000000000000003"

CONF_DEBUG_PROJ = "0A0000000000000000000001"
CONF_RELEASE_PROJ = "0A0000000000000000000002"
CONF_DEBUG_TARG = "0A0000000000000000000003"
CONF_RELEASE_TARG = "0A0000000000000000000004"

LIST_PROJ_CONF = "1A0000000000000000000001"
LIST_TARG_CONF = "1A0000000000000000000002"

pbxproj_content = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 56;
	objects = {{

/* Begin PBXBuildFile section */
		{FILE_APP_BUILD} /* DualAspectCameraApp.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {FILE_APP_REF} /* DualAspectCameraApp.swift */; }};
		{FILE_MGR_BUILD} /* CameraManager.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {FILE_MGR_REF} /* CameraManager.swift */; }};
		{FILE_VIEW_BUILD} /* CameraView.swift in Sources */ = {{isa = PBXBuildFile; fileRef = {FILE_VIEW_REF} /* CameraView.swift */; }};
		{FILE_ASSETS_BUILD} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {FILE_ASSETS_REF} /* Assets.xcassets */; }};
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
		{PROD_REF} /* DualAspectCamera.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = DualAspectCamera.app; sourceTree = BUILT_PRODUCTS_DIR; }};
		{FILE_APP_REF} /* DualAspectCameraApp.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = DualAspectCameraApp.swift; sourceTree = "<group>"; }};
		{FILE_MGR_REF} /* CameraManager.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CameraManager.swift; sourceTree = "<group>"; }};
		{FILE_VIEW_REF} /* CameraView.swift */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = CameraView.swift; sourceTree = "<group>"; }};
		{FILE_ASSETS_REF} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};
		{FILE_PLIST_REF} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{PHASE_FRAMEWORKS} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{GRP_MAIN} = {{
			isa = PBXGroup;
			children = (
				{FILE_APP_REF} /* DualAspectCameraApp.swift */,
				{FILE_MGR_REF} /* CameraManager.swift */,
				{FILE_VIEW_REF} /* CameraView.swift */,
				{FILE_ASSETS_REF} /* Assets.xcassets */,
				{FILE_PLIST_REF} /* Info.plist */,
				{GRP_PROD} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{GRP_PROD} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{PROD_REF} /* DualAspectCamera.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{TARGET_ID} /* DualAspectCamera */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {LIST_TARG_CONF} /* Build configuration list for PBXNativeTarget "DualAspectCamera" */;
			buildPhases = (
				{PHASE_SOURCES} /* Sources */,
				{PHASE_FRAMEWORKS} /* Frameworks */,
				{PHASE_RESOURCES} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = DualAspectCamera;
			productName = DualAspectCamera;
			productReference = {PROD_REF} /* DualAspectCamera.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{PROJECT_ID} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastUpgradeCheck = 1500;
				TargetAttributes = {{
					{TARGET_ID} = {{
						CreatedOnToolsVersion = 15.0;
					}};
				}};
			}};
			buildConfigurationList = {LIST_PROJ_CONF} /* Build configuration list for PBXProject "DualAspectCamera" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {GRP_MAIN};
			productRefGroup = {GRP_PROD} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{TARGET_ID} /* DualAspectCamera */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{PHASE_RESOURCES} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{FILE_ASSETS_BUILD} /* Assets.xcassets in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{PHASE_SOURCES} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{FILE_APP_BUILD} /* DualAspectCameraApp.swift in Sources */,
				{FILE_MGR_BUILD} /* CameraManager.swift in Sources */,
				{FILE_VIEW_BUILD} /* CameraView.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		{CONF_DEBUG_PROJ} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				ENABLE_TESTABILITY = YES;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_OPTIMIZATION_LEVEL = 0;
				GCC_PREPROCESSOR_DEFINITIONS = (
					"DEBUG=1",
					"$(inherited)",
				);
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				IPHONEOS_DEPLOYMENT_TARGET = 16.0;
				MTL_ENABLE_DEBUG_INFO = INCLUDE_SOURCE;
				MTL_FAST_MATH = YES;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = DEBUG;
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
			}};
			name = Debug;
		}};
		{CONF_RELEASE_PROJ} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ANALYZER_NONNULL = YES;
				CLANG_CXX_LANGUAGE_STANDARD = "gnu++20";
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				ENABLE_NS_ASSERTIONS = NO;
				ENABLE_STRICT_OBJC_MSGSEND = YES;
				GCC_NO_COMMON_BLOCKS = YES;
				GCC_WARN_64_TO_32_BIT_CONVERSION = YES;
				GCC_WARN_ABOUT_RETURN_TYPE = YES_ERROR;
				GCC_WARN_UNINITIALIZED_AUTOS = YES_AGGRESSIVE;
				IPHONEOS_DEPLOYMENT_TARGET = 16.0;
				MTL_FAST_MATH = YES;
				ONLY_ACTIVE_ARCH = NO;
				SDKROOT = iphoneos;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_OPTIMIZATION_LEVEL = "-O";
				VALIDATE_PRODUCT = YES;
			}};
			name = Release;
		}};
		{CONF_DEBUG_TARG} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				CODE_SIGN_IDENTITY = "";
				CODE_SIGN_STYLE = Manual;
				CODE_SIGNING_ALLOWED = NO;
				CODE_SIGNING_REQUIRED = NO;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_ASSET_PATHS = "";
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_NSCameraUsageDescription = "DualAspectCamera needs access to the rear camera to capture simultaneous 16:9 and 9:16 4K video.";
				INFOPLIST_KEY_NSMicrophoneUsageDescription = "DualAspectCamera needs access to the microphone to record synchronized audio for both video streams.";
				INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription = "DualAspectCamera needs permission to save finalized horizontal and vertical videos to your Photo Library.";
				INFOPLIST_KEY_NSPhotoLibraryUsageDescription = "DualAspectCamera needs Photo Library access to export your recorded 16:9 and 9:16 videos.";
				INFOPLIST_KEY_UISupportedInterfaceOrientations = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeRight UIInterfaceOrientationLandscapeLeft";
				INFOPLIST_KEY_UIStatusBarHidden = YES;
				INFOPLIST_KEY_UIViewControllerBasedStatusBarAppearance = NO;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UIRequiresFullScreen = YES;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				PRODUCT_BUNDLE_IDENTIFIER = com.dualaspect.DualAspectCamera;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Debug;
		}};
		{CONF_RELEASE_TARG} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_IDENTITY = "";
				CODE_SIGN_STYLE = Manual;
				CODE_SIGNING_ALLOWED = NO;
				CODE_SIGNING_REQUIRED = NO;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_ASSET_PATHS = "";
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_NSCameraUsageDescription = "DualAspectCamera needs access to the rear camera to capture simultaneous 16:9 and 9:16 4K video.";
				INFOPLIST_KEY_NSMicrophoneUsageDescription = "DualAspectCamera needs access to the microphone to record synchronized audio for both video streams.";
				INFOPLIST_KEY_NSPhotoLibraryAddUsageDescription = "DualAspectCamera needs permission to save finalized horizontal and vertical videos to your Photo Library.";
				INFOPLIST_KEY_NSPhotoLibraryUsageDescription = "DualAspectCamera needs Photo Library access to export your recorded 16:9 and 9:16 videos.";
				INFOPLIST_KEY_UISupportedInterfaceOrientations = "UIInterfaceOrientationPortrait UIInterfaceOrientationLandscapeRight UIInterfaceOrientationLandscapeLeft";
				INFOPLIST_KEY_UIStatusBarHidden = YES;
				INFOPLIST_KEY_UIViewControllerBasedStatusBarAppearance = NO;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UIRequiresFullScreen = YES;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.dualaspect.DualAspectCamera;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = "1,2";
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{LIST_PROJ_CONF} /* Build configuration list for PBXProject "DualAspectCamera" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{CONF_DEBUG_PROJ} /* Debug */,
				{CONF_RELEASE_PROJ} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{LIST_TARG_CONF} /* Build configuration list for PBXNativeTarget "DualAspectCamera" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{CONF_DEBUG_TARG} /* Debug */,
				{CONF_RELEASE_TARG} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */

	}};
	rootObject = {PROJECT_ID} /* Project object */;
}}
"""

with open(os.path.join(proj_dir, "project.pbxproj"), "w") as f:
    f.write(pbxproj_content)

# Create xcshareddata/xcschemes/DualAspectCamera.xcscheme so Xcode can build immediately
scheme_dir = os.path.join(proj_dir, "xcshareddata", "xcschemes")
os.makedirs(scheme_dir, exist_ok=True)

scheme_content = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme
   LastUpgradeVersion = "1500"
   version = "1.7">
   <BuildAction
      parallelizeBuildables = "YES"
      buildImplicitDependencies = "YES">
      <BuildActionEntries>
         <BuildActionEntry
            buildForTesting = "YES"
            buildForRunning = "YES"
            buildForProfiling = "YES"
            buildForArchiving = "YES"
            buildForAnalyzing = "YES">
            <BuildableReference
               BuildableIdentifier = "primary"
               BlueprintIdentifier = "{TARGET_ID}"
               BuildableName = "DualAspectCamera.app"
               BlueprintName = "DualAspectCamera"
               ReferencedContainer = "container:DualAspectCamera.xcodeproj">
            </BuildableReference>
         </BuildActionEntry>
      </BuildActionEntries>
   </BuildAction>
   <TestAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      shouldUseLaunchSchemeArgsEnv = "YES">
   </TestAction>
   <LaunchAction
      buildConfiguration = "Debug"
      selectedDebuggerIdentifier = "Xcode.DebuggerFoundation.Debugger.LLDB"
      selectedLauncherIdentifier = "Xcode.DebuggerFoundation.Launcher.LLDB"
      launchStyle = "0"
      useCustomWorkingDirectory = "NO"
      ignoresPersistentStateOnLaunch = "NO"
      debugDocumentVersioning = "YES"
      debugServiceExtension = "internal"
      allowLocationSimulation = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{TARGET_ID}"
            BuildableName = "DualAspectCamera.app"
            BlueprintName = "DualAspectCamera"
            ReferencedContainer = "container:DualAspectCamera.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </LaunchAction>
   <ProfileAction
      buildConfiguration = "Release"
      shouldUseLaunchSchemeArgsEnv = "YES"
      savedToolIdentifier = ""
      useCustomWorkingDirectory = "NO"
      debugDocumentVersioning = "YES">
      <BuildableProductRunnable
         runnableDebuggingMode = "0">
         <BuildableReference
            BuildableIdentifier = "primary"
            BlueprintIdentifier = "{TARGET_ID}"
            BuildableName = "DualAspectCamera.app"
            BlueprintName = "DualAspectCamera"
            ReferencedContainer = "container:DualAspectCamera.xcodeproj">
         </BuildableReference>
      </BuildableProductRunnable>
   </ProfileAction>
   <AnalyzeAction
      buildConfiguration = "Debug">
   </AnalyzeAction>
   <ArchiveAction
      buildConfiguration = "Release"
      revealArchiveInOrganizer = "YES">
   </ArchiveAction>
</Scheme>
"""

with open(os.path.join(scheme_dir, "DualAspectCamera.xcscheme"), "w") as f:
    f.write(scheme_content)

print("Xcode project generated successfully!")
