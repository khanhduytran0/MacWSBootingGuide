#!/bin/bash
#set -e

cmd_sign="codesign --force --preserve-metadata=entitlements,identifier --sign -"
cd /var/jb/usr/macOS
plutil -convert xml1 entitlements*.plist

echo "copy rootfs/System/Library/Templates/Data to rootfs/System/Volumes/Data"
cp -R rootfs/System/Library/Templates/Data rootfs/System/Volumes/
mkdir rootfs/Users/root

echo "copy ellekit"
mkdir -p rootfs/var/jb/usr/lib/CydiaSubstrate.framework
cp /var/jb/usr/lib/libellekit.dylib rootfs/var/jb/usr/lib/CydiaSubstrate.framework/CydiaSubstrate
./bin/machotool platform rootfs/var/jb/usr/lib/CydiaSubstrate.framework/CydiaSubstrate
$cmd_sign rootfs/var/jb/usr/lib/CydiaSubstrate.framework/CydiaSubstrate

echo "copy libmachook"
cp lib/libmachook.dylib /var/jb/usr/macOS/rootfs/var/jb/usr/lib/

echo "copy MTLCompilerService shim"
mkdir -p rootfs/var/jb/XPCServices
cp -R /System/Library/Frameworks/Metal.framework/XPCServices/MTLCompilerService.xpc rootfs/var/jb/XPCServices/MTLCompilerService.xpc
cp bin/launchdchrootexec rootfs/var/jb/XPCServices/MTLCompilerService.xpc/MTLCompilerService

echo "patch MTLCompilerService"
./bin/machotool arm64 rootfs/System/Library/Frameworks/Metal.framework/XPCServices/MTLCompilerService.xpc/Contents/MacOS/MTLCompilerService
# clear entitlements from MTLCompilerService
codesign --force --preserve-metadata=identifier --entitlements entitlements_MTLCompilerService.plist --sign - rootfs/System/Library/Frameworks/Metal.framework/XPCServices/MTLCompilerService.xpc/Contents/MacOS/MTLCompilerService

echo "patch launchservicesd"
mv rootfs/System/Library/CoreServices/launchservicesd{,.dylib}
./bin/machotool dylib rootfs/System/Library/CoreServices/launchservicesd.dylib
$cmd_sign rootfs/System/Library/CoreServices/launchservicesd.dylib
cp bin/launchservicesd rootfs/System/Library/CoreServices/

# patch others
echo "patch Installer Progress"
bin_path="rootfs/System/Library/CoreServices/Installer Progress.app/Contents/MacOS/Installer Progress"
./bin/machotool arm64 "$bin_path"
./bin/machotool sign "$bin_path"
echo "patch WindowServer"
bin_path="rootfs/System/Library/PrivateFrameworks/SkyLight.framework/Resources/WindowServer"
./bin/machotool arm64 "$bin_path"
./bin/machotool sign "$bin_path"

# resign stuff (maybe you can skip with amfi_get_out_of_my_way=1?)
echo "resign system files"
find rootfs/usr/lib -type f -exec $cmd_sign {} \;
$cmd_sign rootfs/System/Library/Extensions/AGXMetal*.bundle/Contents/MacOS/AGXMetal*
$cmd_sign rootfs/System/Library/PrivateFrameworks/GPUCompiler.framework/Libraries/libGPUCompilerImplLazy.dylib
$cmd_sign rootfs/System/Library/HIDPlugins/ServicePlugins/*.plugin/Contents/MacOS/*

echo "done"
