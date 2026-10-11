"""Create the local macOS Xcode project from the checked-in Swift sources.

Run from any directory: python3 BuildSupport/create_xcode_project.py
No external package, network access, or Xcode installation is required.
Regenerating replaces the generated project and shared scheme; edit app code
under Sources and preserve any custom project settings separately first.
"""
from pathlib import Path
import hashlib
import json
import plistlib
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parent.parent
PROJECT = ROOT / "EngineeringBoard.xcodeproj"
INFO = plistlib.loads((ROOT / "Info.plist").read_bytes())
PRODUCT_NAME = INFO["CFBundleDisplayName"]
APP_PRODUCT = PRODUCT_NAME + ".app"
objects = {}


class Ref(str):
    """A reference to another PBX object, not an arbitrary string."""


def uid(name):
    return Ref(hashlib.sha256(("EngineeringBoard/" + name).encode()).hexdigest()[:24].upper())


def add(identifier, isa, **fields):
    key = uid(identifier)
    if key in objects:
        raise ValueError("Duplicate project object: " + identifier)
    objects[key] = {"isa": isa, **fields}
    return key


def encode(value, depth=0):
    indent = "\t" * depth
    if isinstance(value, Ref):
        return str(value)
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=False)
    if isinstance(value, int):
        return str(value)
    if isinstance(value, list):
        return "(\n" + "".join("\t" * (depth + 1) + encode(v, depth + 1) + ",\n" for v in value) + indent + ")"
    if isinstance(value, dict):
        return "{\n" + "".join("\t" * (depth + 1) + encode(k) + " = " + encode(v, depth + 1) + ";\n" for k, v in value.items()) + indent + "}"
    raise TypeError(type(value))


def files_in(relative):
    references, build_files = [], []
    for file in sorted((ROOT / relative).glob("*.swift")):
        path = file.relative_to(ROOT).as_posix()
        ref = add("file/" + path, "PBXFileReference", lastKnownFileType="sourcecode.swift", path=path, sourceTree="SOURCE_ROOT")
        references.append(ref)
        build_files.append(add("build/" + path, "PBXBuildFile", fileRef=ref))
    return references, build_files


app_files, app_builds = files_in("Sources/EngineeringBoard")
test_files, test_builds = files_in("Tests/EngineeringBoardTests")
if not app_files:
    raise SystemExit("No app source files found")

resources, resource_builds = [], []
for path, kind in [("AppIcon.icns", "image.icns"), ("Resources/MathSymbols", "folder"),
                   ("Resources/QuickKeys", "folder"), ("third-party-licenses", "folder"), ("THIRD_PARTY_NOTICES.md", "text"), ("LICENSE", "text")]:
    if not (ROOT / path).exists():
        raise SystemExit("Missing app resource: " + path)
    ref = add("file/" + path, "PBXFileReference", lastKnownFileType=kind, path=path, sourceTree="SOURCE_ROOT")
    resources.append(ref)
    resource_builds.append(add("build/" + path, "PBXBuildFile", fileRef=ref))

documents = []
for path in ["Info.plist", "Package.swift", "README.md", "CONTRIBUTING.md", "VERIFICATION.md", "build.sh",
             "BuildSupport/create_xcode_project.py", "BuildSupport/prepare_sdk.py"]:
    kind = "text.plist.xml" if path.endswith(".plist") else "text"
    documents.append(add("file/" + path, "PBXFileReference", lastKnownFileType=kind, path=path, sourceTree="SOURCE_ROOT"))

app_product = add("product/app", "PBXFileReference", explicitFileType="wrapper.application", includeInIndex=0,
                  path=APP_PRODUCT, sourceTree="BUILT_PRODUCTS_DIR")
test_product = add("product/tests", "PBXFileReference", explicitFileType="wrapper.cfbundle", includeInIndex=0,
                   path="EngineeringBoardTests.xctest", sourceTree="BUILT_PRODUCTS_DIR")
source_group = add("group/source", "PBXGroup", children=app_files, name="App source", sourceTree="<group>")
tests_group = add("group/tests", "PBXGroup", children=test_files, name="Tests", sourceTree="<group>")
resources_group = add("group/resources", "PBXGroup", children=resources, name="Resources", sourceTree="<group>")
docs_group = add("group/documents", "PBXGroup", children=documents, name="Project and guides", sourceTree="<group>")
products_group = add("group/products", "PBXGroup", children=[app_product, test_product], name="Products", sourceTree="<group>")
main_group = add("group/main", "PBXGroup", children=[source_group, resources_group, tests_group, docs_group, products_group], sourceTree="<group>")


def phase(name, isa, files):
    return add(name, isa, buildActionMask=2147483647, files=files, runOnlyForDeploymentPostprocessing=0)


app_sources = phase("phase/app/sources", "PBXSourcesBuildPhase", app_builds)
app_resources = phase("phase/app/resources", "PBXResourcesBuildPhase", resource_builds)
app_frameworks = phase("phase/app/frameworks", "PBXFrameworksBuildPhase", [])
test_sources = phase("phase/tests/sources", "PBXSourcesBuildPhase", test_builds)
test_resources = phase("phase/tests/resources", "PBXResourcesBuildPhase", [])
test_frameworks = phase("phase/tests/frameworks", "PBXFrameworksBuildPhase", [])

version = plistlib.loads((ROOT / "Info.plist").read_bytes())["CFBundleShortVersionString"]
common = {
    "SDKROOT": "macosx", "MACOSX_DEPLOYMENT_TARGET": "14.0", "SWIFT_VERSION": "5.0",
    "CLANG_ENABLE_MODULES": "YES", "CLANG_ENABLE_OBJC_ARC": "YES",
    "CLANG_WARN_DOCUMENTATION_COMMENTS": "YES", "GCC_WARN_UNUSED_VARIABLE": "YES",
    "ENABLE_USER_SCRIPT_SANDBOXING": "YES", "SUPPORTED_PLATFORMS": "macosx",
    "SWIFT_EMIT_LOC_STRINGS": "NO",
}
app_settings = {
    "PRODUCT_NAME": PRODUCT_NAME, "PRODUCT_MODULE_NAME": "EngineeringBoard",
    "EXECUTABLE_NAME": "EngineeringBoard", "PRODUCT_BUNDLE_IDENTIFIER": INFO["CFBundleIdentifier"],
    "INFOPLIST_FILE": "Info.plist", "GENERATE_INFOPLIST_FILE": "NO",
    "CODE_SIGN_IDENTITY": "-", "CODE_SIGN_STYLE": "Manual",
    "ENABLE_APP_SANDBOX": "NO", "ENABLE_HARDENED_RUNTIME": "NO",
    "COMBINE_HIDPI_IMAGES": "YES", "ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES": "YES",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks"],
    "MARKETING_VERSION": version,
    "CURRENT_PROJECT_VERSION": str(plistlib.loads((ROOT / "Info.plist").read_bytes())["CFBundleVersion"]),
}
test_settings = {
    "PRODUCT_NAME": "$(TARGET_NAME)", "PRODUCT_BUNDLE_IDENTIFIER": "local.karim.engineeringboard.tests",
    "GENERATE_INFOPLIST_FILE": "YES", "CODE_SIGN_IDENTITY": "-", "CODE_SIGN_STYLE": "Manual",
    "TEST_HOST": "$(BUILT_PRODUCTS_DIR)/" + APP_PRODUCT + "/Contents/MacOS/EngineeringBoard",
    "BUNDLE_LOADER": "$(TEST_HOST)",
    "LD_RUNPATH_SEARCH_PATHS": ["$(inherited)", "@executable_path/../Frameworks", "@loader_path/../Frameworks"],
}


def configuration_list(scope, base):
    refs = []
    for mode in ["Debug", "Release"]:
        settings = dict(base)
        if scope == "project":
            settings.update({"DEBUG_INFORMATION_FORMAT": "dwarf" if mode == "Debug" else "dwarf-with-dsym",
                             "SWIFT_OPTIMIZATION_LEVEL": "-Onone" if mode == "Debug" else "-O",
                             "ONLY_ACTIVE_ARCH": "YES" if mode == "Debug" else "NO",
                             "ENABLE_TESTABILITY": "YES" if mode == "Debug" else "NO"})
            if mode == "Debug":
                settings["SWIFT_ACTIVE_COMPILATION_CONDITIONS"] = "DEBUG $(inherited)"
        refs.append(add("config/" + scope + "/" + mode, "XCBuildConfiguration", buildSettings=settings, name=mode))
    return add("configs/" + scope, "XCConfigurationList", buildConfigurations=refs,
               defaultConfigurationIsVisible=0, defaultConfigurationName="Release")


project_configs = configuration_list("project", common)
app_configs = configuration_list("app", app_settings)
test_configs = configuration_list("tests", test_settings)
app_target_id = uid("target/app")
proxy = add("dependency/proxy", "PBXContainerItemProxy", containerPortal=uid("project"), proxyType=1,
            remoteGlobalIDString=app_target_id, remoteInfo="EngineeringBoard")
dependency = add("dependency/app", "PBXTargetDependency", target=app_target_id, targetProxy=proxy)
app_target = add("target/app", "PBXNativeTarget", buildConfigurationList=app_configs,
                 buildPhases=[app_sources, app_frameworks, app_resources], buildRules=[], dependencies=[],
                 name="EngineeringBoard", productName=PRODUCT_NAME, productReference=app_product,
                 productType="com.apple.product-type.application")
test_target = add("target/tests", "PBXNativeTarget", buildConfigurationList=test_configs,
                  buildPhases=[test_sources, test_frameworks, test_resources], buildRules=[], dependencies=[dependency],
                  name="EngineeringBoardTests", productName="EngineeringBoardTests", productReference=test_product,
                  productType="com.apple.product-type.bundle.unit-test")
project = add("project", "PBXProject", attributes={"LastUpgradeCheck": "1600", "BuildIndependentTargetsInParallel": "YES",
              "TargetAttributes": {app_target: {"CreatedOnToolsVersion": "16.0"},
                                   test_target: {"CreatedOnToolsVersion": "16.0", "TestTargetID": app_target}}},
              buildConfigurationList=project_configs, compatibilityVersion="Xcode 14.0",
              developmentRegion="en", hasScannedForEncodings=0, knownRegions=["en", "Base"],
              mainGroup=main_group, productRefGroup=products_group, projectDirPath="", projectRoot="",
              targets=[app_target, test_target])
PROJECT.mkdir(parents=True, exist_ok=True)
(PROJECT / "project.pbxproj").write_text("// !$*UTF8*$!\n" + encode({"archiveVersion": 1, "classes": {}, "objectVersion": 56,
                                      "objects": objects, "rootObject": project}) + "\n")

workspace = PROJECT / "project.xcworkspace"
workspace.mkdir(exist_ok=True)
(workspace / "contents.xcworkspacedata").write_text('<?xml version="1.0" encoding="UTF-8"?>\n<Workspace version="1.0"><FileRef location="self:"></FileRef></Workspace>\n')
schemes = PROJECT / "xcshareddata" / "xcschemes"
schemes.mkdir(parents=True, exist_ok=True)
scheme = ET.Element("Scheme", LastUpgradeVersion="1600", version="1.3")


def buildable(parent, target, name):
    ET.SubElement(parent, "BuildableReference", BuildableIdentifier="primary", BlueprintIdentifier=str(target),
                  BuildableName=name, BlueprintName="EngineeringBoard" if target == app_target else "EngineeringBoardTests",
                  ReferencedContainer="container:EngineeringBoard.xcodeproj")


build = ET.SubElement(scheme, "BuildAction", parallelizeBuildables="YES", buildImplicitDependencies="YES")
entries = ET.SubElement(build, "BuildActionEntries")
entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="YES",
                      buildForProfiling="YES", buildForArchiving="YES", buildForAnalyzing="YES")
buildable(entry, app_target, APP_PRODUCT)
entry = ET.SubElement(entries, "BuildActionEntry", buildForTesting="YES", buildForRunning="NO",
                      buildForProfiling="NO", buildForArchiving="NO", buildForAnalyzing="YES")
buildable(entry, test_target, "EngineeringBoardTests.xctest")
test = ET.SubElement(scheme, "TestAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB",
                     selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", shouldUseLaunchSchemeArgsEnv="YES")
testables = ET.SubElement(test, "Testables")
buildable(ET.SubElement(testables, "TestableReference", skipped="NO"), test_target, "EngineeringBoardTests.xctest")
launch = ET.SubElement(scheme, "LaunchAction", buildConfiguration="Debug", selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB",
                       selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB", launchStyle="0", useCustomWorkingDirectory="NO",
                       ignoresPersistentStateOnLaunch="NO", debugDocumentVersioning="YES", debugServiceExtension="internal", allowLocationSimulation="NO")
buildable(ET.SubElement(launch, "BuildableProductRunnable", runnableDebuggingMode="0"), app_target, APP_PRODUCT)
profile = ET.SubElement(scheme, "ProfileAction", buildConfiguration="Release", shouldUseLaunchSchemeArgsEnv="YES",
                        savedToolIdentifier="", useCustomWorkingDirectory="NO", debugDocumentVersioning="YES")
buildable(ET.SubElement(profile, "BuildableProductRunnable", runnableDebuggingMode="0"), app_target, APP_PRODUCT)
ET.SubElement(scheme, "AnalyzeAction", buildConfiguration="Debug")
ET.SubElement(scheme, "ArchiveAction", buildConfiguration="Release", revealArchiveInOrganizer="YES")
ET.indent(scheme)
ET.ElementTree(scheme).write(schemes / "EngineeringBoard.xcscheme", encoding="utf-8", xml_declaration=True)
print(f"Created {PROJECT.name}: {len(app_files)} app sources, {len(test_files)} test sources, {len(resources)} resource entries.")
