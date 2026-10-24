#!/usr/bin/env python3
"""Generate the dependency-free, shared-source iOS Xcode project."""
from pathlib import Path
import hashlib, json
root=Path(__file__).resolve().parent.parent
objects={}
def uid(name): return hashlib.sha1(name.encode()).hexdigest()[:24].upper()
def quote(s): return json.dumps(str(s),ensure_ascii=False)
def add(key,isa,**fields):
 objects[uid(key)]='isa = '+isa+'; '+ ' '.join(k+' = '+v+';' for k,v in fields.items());return uid(key)
def arr(items): return '('+','.join(items)+(',' if items else '')+')'
def dictionary(items): return '{'+' '.join(k+' = '+quote(v)+';' for k,v in items.items())+'}'
def file(path,typ):
 return add('file:'+path,'PBXFileReference',lastKnownFileType=typ,path=quote(path),sourceTree='SOURCE_ROOT')
def build(ref): return add('build:'+ref,'PBXBuildFile',fileRef=ref)
shared=['AppState','AircraftPicker','ContentView','GlassSlider','Livery','Platform','Renderer','SolarController','Weather']
sources=[file('../../Sources/Winglight/'+n+'.swift','sourcecode.swift') for n in shared]
sources += [file('Sources/'+n+'.swift','sourcecode.swift') for n in ['MobileApp','MobileStage','MobileContentView']]
sources += [file('../../Sources/Winglight/Resources/Lights.metal','sourcecode.metal')]
resources=[file('../../Sources/Winglight/Resources/'+n,'folder') for n in ['Models','Textures','Liveries']]
resources += [file('Assets.xcassets','folder.assetcatalog')]
resources += [file('../../'+n,'text') for n in ['LICENSE','NOTICE','THIRD_PARTY.md']]
resources += [file('../../ThirdParty/Licenses','folder'),file('../../ThirdParty/NOTICE.txt','text')]
ui=[file('Tests/MobileUITests.swift','sourcecode.swift')]
unit=[file('../../Tests/WinglightAppTests/'+n+'.swift','sourcecode.swift') for n in ['SolarControllerTests','WeatherTests','InteractionTests','LiveryTests']]
unit += [file('Tests/MobileTests.swift','sourcecode.swift')]
products=[]
for name,typ,ext in [('Winglight','wrapper.application','app'),('WinglightTests','wrapper.cfbundle','xctest'),('WinglightUITests','wrapper.cfbundle','xctest')]:
 products.append(add('product:'+name,'PBXFileReference',explicitFileType=typ,path=quote(name+'.'+ext),sourceTree='BUILT_PRODUCTS_DIR'))
group=add('mainGroup','PBXGroup',children=arr(sources+resources+ui+unit+[uid('products')]),sourceTree='"<group>"')
add('products','PBXGroup',children=arr(products),name='Products',sourceTree='"<group>"')
package=add('localPackage','XCLocalSwiftPackageReference',relativePath=quote('../..'))
product=add('coreProduct','XCSwiftPackageProductDependency',package=package,productName='WinglightCore')
corebuild=add('coreBuild','PBXBuildFile',productRef=product)
project_config={'IPHONEOS_DEPLOYMENT_TARGET':'18.0','SWIFT_VERSION':'5.0','SDKROOT':'iphoneos','CLANG_ENABLE_MODULES':'YES','ENABLE_USER_SCRIPT_SANDBOXING':'YES'}
app_config={'PRODUCT_BUNDLE_IDENTIFIER':'com.wzk112.Winglight.iOS','PRODUCT_NAME':'Winglight','PRODUCT_MODULE_NAME':'Winglight','TARGETED_DEVICE_FAMILY':'1,2','INFOPLIST_FILE':'Info.plist','ASSETCATALOG_COMPILER_APPICON_NAME':'AppIcon','CODE_SIGN_STYLE':'Automatic','SWIFT_EMIT_LOC_STRINGS':'YES','SUPPORTED_PLATFORMS':'iphoneos iphonesimulator','SUPPORTS_MACCATALYST':'NO','MARKETING_VERSION':'1.6.0','CURRENT_PROJECT_VERSION':'12','MTL_LANGUAGE_REVISION':'Metal31','GENERATE_INFOPLIST_FILE':'NO','ENABLE_TESTABILITY':'YES'}
def configs(name,settings):
 ids=[]
 for conf in ['Debug','Release']:
  values=dict(settings)
  if conf=='Debug': values.update({'SWIFT_OPTIMIZATION_LEVEL':'-Onone','DEBUG_INFORMATION_FORMAT':'dwarf','ONLY_ACTIVE_ARCH':'YES'})
  else: values.update({'SWIFT_OPTIMIZATION_LEVEL':'-O','DEBUG_INFORMATION_FORMAT':'dwarf-with-dsym'})
  ids.append(add(name+conf,'XCBuildConfiguration',name=conf,buildSettings=dictionary(values)))
 return add(name+'configs','XCConfigurationList',buildConfigurations=arr(ids),defaultConfigurationIsVisible='0',defaultConfigurationName='Release')
project_configs=configs('project',project_config)
for idx,(name,src,settings,kind) in enumerate([
 ('WinglightMobile',sources,app_config,'com.apple.product-type.application'),
 ('WinglightTests',unit,{'PRODUCT_NAME':'WinglightTests','PRODUCT_BUNDLE_IDENTIFIER':'com.wzk112.Winglight.iOS.Tests','GENERATE_INFOPLIST_FILE':'YES','TEST_HOST':'$(BUILT_PRODUCTS_DIR)/Winglight.app/Winglight','BUNDLE_LOADER':'$(TEST_HOST)','CODE_SIGN_STYLE':'Automatic','TARGETED_DEVICE_FAMILY':'1,2'},'com.apple.product-type.bundle.unit-test'),
 ('WinglightUITests',ui,{'PRODUCT_NAME':'WinglightUITests','PRODUCT_BUNDLE_IDENTIFIER':'com.wzk112.Winglight.iOS.UITests','GENERATE_INFOPLIST_FILE':'YES','TEST_TARGET_NAME':'WinglightMobile','CODE_SIGN_STYLE':'Automatic','TARGETED_DEVICE_FAMILY':'1,2'},'com.apple.product-type.bundle.ui-testing')]):
 phases=[add(name+'sources','PBXSourcesBuildPhase',buildActionMask='2147483647',files=arr([build(r) for r in src]),runOnlyForDeploymentPostprocessing='0')]
 phases.append(add(name+'frameworks','PBXFrameworksBuildPhase',buildActionMask='2147483647',files=arr([corebuild] if idx<2 else []),runOnlyForDeploymentPostprocessing='0'))
 phases.append(add(name+'resources','PBXResourcesBuildPhase',buildActionMask='2147483647',files=arr([build(r) for r in resources] if idx==0 else []),runOnlyForDeploymentPostprocessing='0'))
 deps=[]
 if idx:
  proxy=add(name+'proxy','PBXContainerItemProxy',containerPortal=uid('project'),proxyType='1',remoteGlobalIDString=uid('targetWinglightMobile'),remoteInfo='WinglightMobile')
  deps=[add(name+'dependency','PBXTargetDependency',target=uid('targetWinglightMobile'),targetProxy=proxy)]
 add('target'+name,'PBXNativeTarget',buildConfigurationList=configs(name,settings),buildPhases=arr(phases),buildRules='()',dependencies=arr(deps),name=name,productName=name,productReference=products[idx],productType=quote(kind),packageProductDependencies=arr([product]) if idx<2 else '()')
add('project','PBXProject',attributes='{BuildIndependentTargetsInParallel = YES; LastUpgradeCheck = 2700; TargetAttributes = {'+uid('targetWinglightUITests')+' = {TestTargetID = '+uid('targetWinglightMobile')+';};};}',buildConfigurationList=project_configs,compatibilityVersion='"Xcode 14.0"',developmentRegion='en',knownRegions='(en,zh-Hans,Base)',mainGroup=group,productRefGroup=uid('products'),projectDirPath='""',projectRoot='""',targets=arr([uid('target'+n) for n in ['WinglightMobile','WinglightTests','WinglightUITests']]),packageReferences=arr([package]))
folder=root/'Apps/iOS/Winglight.xcodeproj';folder.mkdir(exist_ok=True)
(folder/'project.pbxproj').write_text('// !$*UTF8*$!\n{archiveVersion = 1; classes = {}; objectVersion = 56; objects = {\n'+'\n'.join(k+' = {'+v+'};' for k,v in objects.items())+'\n}; rootObject = '+uid('project')+';}\n')
schemes=folder/'xcshareddata/xcschemes';schemes.mkdir(parents=True,exist_ok=True)
def ref(n): return '<BuildableReference BuildableIdentifier="primary" BlueprintIdentifier="'+uid('target'+n)+'" BuildableName="'+('Winglight.app' if n=='WinglightMobile' else n+'.xctest')+'" BlueprintName="'+n+'" ReferencedContainer="container:Winglight.xcodeproj"/>'
(schemes/'Winglight.xcscheme').write_text('<?xml version="1.0" encoding="UTF-8"?><Scheme LastUpgradeVersion="2700" version="1.3"><BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES"><BuildActionEntries><BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">'+ref('WinglightMobile')+'</BuildActionEntry></BuildActionEntries></BuildAction><TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" shouldUseLaunchSchemeArgsEnv="YES"><Testables>'+''.join('<TestableReference skipped="NO">'+ref(n)+'</TestableReference>' for n in ['WinglightTests','WinglightUITests'])+'</Testables></TestAction><LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES"><BuildableProductRunnable runnableDebuggingMode="0">'+ref('WinglightMobile')+'</BuildableProductRunnable></LaunchAction><ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES"><BuildableProductRunnable runnableDebuggingMode="0">'+ref('WinglightMobile')+'</BuildableProductRunnable></ProfileAction><AnalyzeAction buildConfiguration="Debug"/><ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES"/></Scheme>')
print(folder)
