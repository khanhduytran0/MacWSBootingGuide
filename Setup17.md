# Set up on iOS 17.0

THIS IS A DRAFT, IT DOES NOT WORK.

## Requirements
- nathanlr jailbreak

## Setup
### Patch ct_bypass to allow signing `dyld`
```diff
diff --git a/tests/ct_bypass/main.c b/tests/ct_bypass/main.c
index a679349..156f654 100644
--- a/tests/ct_bypass/main.c
+++ b/tests/ct_bypass/main.c
@@ -61,7 +61,7 @@ char *extract_preferred_slice(const char *fatPath)
 #endif // TARGET_OS_MAC && !TARGET_OS_IPHONE
 
     // Only re-sign MH_EXECUTE, MH_DYLIB, and MH_BUNDLE
-    if (macho->machHeader.filetype != MH_EXECUTE && macho->machHeader.filetype != MH_DYLIB && macho->machHeader.filetype != MH_BUNDLE) {
+    if (macho->machHeader.filetype != MH_EXECUTE && macho->machHeader.filetype != MH_DYLIB && macho->machHeader.filetype != MH_BUNDLE && macho->machHeader.filetype != MH_DYLINKER) {
         printf("Error: MachO is not an executable, dynamic library, or bundle! This is an unsupported MachO type for code-signing.\n");
         fat_free(fat);
         return NULL;
```

### Save this to `/var/jb/var/mobile/BootMacOS/ent.xml`
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>platform-application</key>
    <true/>
    <key>get-task-allow</key>
    <true/>
</dict>
</plist>
```

### Execute the following script
```
export BOOT_PATH=/var/jb/BootMacOS
export IPSW_PATH=$BOOT_PATH/ipsw

mkdir -p $IPSW_PATH

# Download macOS 14.0 IPSW and extract
cd $IPSW_PATH
wget https://updates.cdn-apple.com/2023FallFCS/fullrestores/042-54934/0E101AD6-3117-4B63-9BF1-143B6DB9270A/UniversalMac_14.0_23A344_Restore.ipsw
unzip UniversalMac_14.0_23A344_Restore.ipsw
cd $BOOT_PATH

# For now I will use RecoveryOS aka 022-13450-622.dmg
sudo hdik $IPSW_PATH/022-13450-622.dmg
# /dev/disk3              GUID_partition_scheme              
# /dev/disk3s1            7C3457EF-0000-11AA-AA11-0030654    
# /dev/disk4              EF57347C-0000-11AA-AA11-0030654    
# /dev/disk4s1            41504653-0000-11AA-AA11-0030654    

# Mount the system volume
sudo mkdir -p /var/mnt/staging
sudo mount_apfs -o ro /dev/disk4s1 /var/mnt/staging

# Copy files
sudo cp -ar /var/mnt/staging rootfs
# Fixup folders, use template data
sudo rm -r rootfs/System/Volumes/Data
sudo cp -ar rootfs/System/Library/Templates/Data rootfs/System/Volumes/Data # or hack: sudo ln -s ../Library/Templates/Data rootfs/System/Volumes/Data
# Fixup dyld shared cache
sudo mkdir rootfs/System/Cryptexes/OS/System/Library/Caches
sudo ln -s ../../../../../../System/Library/dyld rootfs/System/Cryptexes/OS/System/Library/Caches/com.apple.dyld

# FIXME: need to use iOS dyld for now
sudo cp /usr/lib/dyld rootfs/usr/lib/dyld
```
