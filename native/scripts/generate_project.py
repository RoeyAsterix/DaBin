#!/usr/bin/env python3
"""Generate a dependency-free Xcode project; portable command-line build uses build.sh."""
import argparse
import json
from pathlib import Path
from hashlib import sha256
from project_inventory import sources as production_sources, resources, RESOURCE_TYPES, source_group

parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true', help='Fail if checked-in project differs from the deterministic inventory')
args = parser.parse_args()

def write_artifact(path, text):
    if args.check:
        if not path.is_file() or path.read_text() != text:
            raise SystemExit('Generated project is stale. Run scripts/generate_project.py: ' + str(path))
    else:
        path.write_text(text)

root = Path(__file__).resolve().parents[1]
signing = json.loads((root / 'Config/AppStoreSigning.json').read_text())
bundle_identifier = signing['bundleIdentifier']
development_team = signing['developmentTeam']
def ident(value): return sha256(value.encode()).hexdigest()[:24].upper()
def q(value): return '"' + str(value).replace('\\', '\\\\').replace('"', '\\"') + '"'
objects = []
def obj(key, body):
    uid = ident(key)
    objects.append(f'\t\t{uid} = {{ {body} }};')
    return uid
sources = production_sources()
refs, builds = [], []
source_groups = {}
for path in sources:
    rel = str(path.relative_to(root))
    ref = obj(rel, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(rel)}; sourceTree = SOURCE_ROOT;')
    refs.append(ref)
    source_groups.setdefault(source_group(path), []).append(ref)
    builds.append(obj('build:'+rel, f'isa = PBXBuildFile; fileRef = {ref};'))
resource_builds = []
resource_refs = []
for path in resources():
    rel = str(path.relative_to(root))
    filetype = RESOURCE_TYPES[rel]
    if not path.exists(): raise SystemExit('Missing required resource: ' + rel)
    ref = obj(rel, f'isa = PBXFileReference; lastKnownFileType = {filetype}; path = {q(rel)}; sourceTree = SOURCE_ROOT;')
    resource_refs.append(ref)
    resource_builds.append(obj('build:'+rel, f'isa = PBXBuildFile; fileRef = {ref};'))
testref = obj('testfile', 'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = Tests/XcodeSmokeTests.swift; sourceTree = SOURCE_ROOT;')
testbuild = obj('testbuild', f'isa = PBXBuildFile; fileRef = {testref};')
product = obj('product', 'isa = PBXFileReference; explicitFileType = wrapper.application; path = DaBin.app; sourceTree = BUILT_PRODUCTS_DIR;')
testproduct = obj('testproduct', 'isa = PBXFileReference; explicitFileType = wrapper.cfbundle; path = DaBinTests.xctest; sourceTree = BUILT_PRODUCTS_DIR;')
products = obj('products', f'isa = PBXGroup; children = ({product}, {testproduct},); name = Products; sourceTree = "<group>";')
group_refs = []
for name in ['Application', 'State and Domain', 'Storage', 'Services', 'Desktop', 'Interface']:
    if name in source_groups:
        group_refs.append(obj('source-group:'+name, f'isa = PBXGroup; children = ({", ".join(source_groups[name])},); name = {q(name)}; sourceTree = "<group>";'))
source_root = obj('source-root', f'isa = PBXGroup; children = ({", ".join(group_refs)},); name = Sources; sourceTree = "<group>";')
resource_root = obj('resource-root', f'isa = PBXGroup; children = ({", ".join(resource_refs)},); name = Resources; sourceTree = "<group>";')
test_refs = [testref]
for path in sorted(root.glob('Tests/*.swift')):
    if path.name == 'XcodeSmokeTests.swift': continue
    rel = str(path.relative_to(root))
    test_refs.append(obj(rel, f'isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = {q(rel)}; sourceTree = SOURCE_ROOT;'))
test_root = obj('test-root', f'isa = PBXGroup; children = ({", ".join(test_refs)},); name = Tests; sourceTree = "<group>";')
main = obj('main', f'isa = PBXGroup; children = ({source_root}, {resource_root}, {test_root}, {products},); sourceTree = "<group>";')
srcphase = obj('sources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(builds)},); runOnlyForDeploymentPostprocessing = 0;')
resphase = obj('resources', f'isa = PBXResourcesBuildPhase; buildActionMask = 2147483647; files = ({", ".join(resource_builds)},); runOnlyForDeploymentPostprocessing = 0;')
frameworks = obj('frameworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
testsrc = obj('testsources', f'isa = PBXSourcesBuildPhase; buildActionMask = 2147483647; files = ({testbuild},); runOnlyForDeploymentPostprocessing = 0;')
testframeworks = obj('testframeworks', 'isa = PBXFrameworksBuildPhase; buildActionMask = 2147483647; files = (); runOnlyForDeploymentPostprocessing = 0;')
configs = {}
for owner in ['project','app','test']:
    ids = []
    for name in ['Debug','Release']:
        settings = {'SWIFT_VERSION':'5.0','MACOSX_DEPLOYMENT_TARGET':'14.0','SDKROOT':'macosx','ARCHS':'arm64','ONLY_ACTIVE_ARCH':'NO','CLANG_ENABLE_MODULES':'YES','SWIFT_TREAT_WARNINGS_AS_ERRORS':'YES','GCC_TREAT_WARNINGS_AS_ERRORS':'YES'}
        if name == 'Debug': settings.update(SWIFT_OPTIMIZATION_LEVEL='-Onone', SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG', ENABLE_TESTABILITY='YES', DEBUG_INFORMATION_FORMAT='dwarf')
        else: settings.update(SWIFT_OPTIMIZATION_LEVEL='-O', SWIFT_COMPILATION_MODE='wholemodule', DEBUG_INFORMATION_FORMAT='dwarf-with-dsym')
        if owner == 'app':
            settings.update(PRODUCT_NAME='DaBin', PRODUCT_BUNDLE_IDENTIFIER=bundle_identifier, INFOPLIST_FILE='Resources/Info.plist', CODE_SIGN_ENTITLEMENTS='Resources/DaBin.entitlements', ENABLE_APP_SANDBOX='YES', COMBINE_HIDPI_IMAGES='YES', SKIP_INSTALL='NO')
            if name == 'Debug':
                settings.update(CODE_SIGN_IDENTITY='-', CODE_SIGN_STYLE='Manual')
            else:
                # Release archives use the enrolled team while Xcode manages the
                # App Store certificate and provisioning profile.
                settings.update(CODE_SIGN_STYLE='Automatic', DEVELOPMENT_TEAM=development_team)
        if owner == 'test':
            settings.update(PRODUCT_NAME='DaBinTests', PRODUCT_BUNDLE_IDENTIFIER='com.dabin.mac.tests', GENERATE_INFOPLIST_FILE='YES', CODE_SIGN_IDENTITY='-', TEST_HOST='$(BUILT_PRODUCTS_DIR)/DaBin.app/Contents/MacOS/DaBin', BUNDLE_LOADER='$(TEST_HOST)', LD_RUNPATH_SEARCH_PATHS='$(inherited) @executable_path/../Frameworks @loader_path/../Frameworks')
        body = ' '.join(f'{k} = {q(v)};' for k,v in settings.items())
        ids.append(obj(owner+name, f'isa = XCBuildConfiguration; buildSettings = {{ {body} }}; name = {name};'))
    configs[owner] = obj(owner+'configlist', f'isa = XCConfigurationList; buildConfigurations = ({", ".join(ids)},); defaultConfigurationIsVisible = 0; defaultConfigurationName = Release;')
target = obj('target', f'isa = PBXNativeTarget; buildConfigurationList = {configs["app"]}; buildPhases = ({srcphase}, {frameworks}, {resphase},); buildRules = (); dependencies = (); name = DaBin; productName = DaBin; productReference = {product}; productType = "com.apple.product-type.application";')
proxy = obj('proxy', f'isa = PBXContainerItemProxy; containerPortal = {ident("project")}; proxyType = 1; remoteGlobalIDString = {target}; remoteInfo = DaBin;')
dependency = obj('dependency', f'isa = PBXTargetDependency; target = {target}; targetProxy = {proxy};')
testtarget = obj('testtarget', f'isa = PBXNativeTarget; buildConfigurationList = {configs["test"]}; buildPhases = ({testsrc}, {testframeworks},); buildRules = (); dependencies = ({dependency},); name = DaBinTests; productName = DaBinTests; productReference = {testproduct}; productType = "com.apple.product-type.bundle.unit-test";')
project = obj('project', f'isa = PBXProject; attributes = {{ LastUpgradeCheck = 1600; TargetAttributes = {{ {target} = {{ DevelopmentTeam = {q(development_team)}; ProvisioningStyle = Automatic; }}; }}; }}; buildConfigurationList = {configs["project"]}; compatibilityVersion = "Xcode 14.0"; developmentRegion = en; hasScannedForEncodings = 0; knownRegions = (en, Base,); mainGroup = {main}; productRefGroup = {products}; projectDirPath = ""; projectRoot = ""; targets = ({target}, {testtarget},);')
projectdir = root/'DaBin.xcodeproj'
projectdir.mkdir(exist_ok=True)
write_artifact(projectdir/'project.pbxproj', '// !$*UTF8*$!\n{ archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(objects)+f'\n}}; rootObject = {project}; }}\n')
scheme = projectdir/'xcshareddata/xcschemes/DaBin.xcscheme'
scheme.parent.mkdir(parents=True, exist_ok=True)
def reference(uid, name, blueprint): return f'<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="{uid}" BuildableName="{name}" BlueprintName="{blueprint}" ReferencedContainer="container:DaBin.xcodeproj"/>'
write_artifact(scheme, f'''<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1600" version="1.3">
<BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">{reference(target,'DaBin.app','DaBin')}</BuildActionEntry></BuildActionEntries></BuildAction>
<TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables><TestableReference skipped="NO">{reference(testtarget,'DaBinTests.xctest','DaBinTests')}</TestableReference></Testables></TestAction>
<LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(target,'DaBin.app','DaBin')}</BuildableProductRunnable></LaunchAction>
<ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">{reference(target,'DaBin.app','DaBin')}</BuildableProductRunnable></ProfileAction>
<AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/>
</Scheme>''')
print(projectdir)
