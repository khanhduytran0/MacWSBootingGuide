@import Darwin;

#define CS_LAUNCH_TYPE_SYSTEM_SERVICE 1
int posix_spawnattr_set_launch_type_np(posix_spawnattr_t *attr, int launch_type);

int main(int argc, char *argv[], char *envp[]) {
    int uid = 0;
    int gid = 0;
    char *execArgs[] = {"/System/Library/Frameworks/Metal.framework/XPCServices/MTLCompilerService.xpc/Contents/MacOS/MTLCompilerService", NULL};
    const char *execPath = *execArgs;
    
    if(chroot("/var/jb/usr/macOS/rootfs") < 0) {
        perror("chroot");
        return 1;
    }
    if(chdir("/") < 0) {
        perror("chdir");
        chdir("/");
    }
    
    setenv("DYLD_INSERT_LIBRARIES", "/var/jb/usr/lib/libmachook.dylib", 1);
    setenv("HOME", "/Users/root", 1);
    setenv("TMPDIR", "/tmp", 1);
    
    posix_spawnattr_t attr;
    if(posix_spawnattr_init(&attr) != 0) {
        perror("posix_spawnattr_init");
        return 1;
    }
    
    if(getppid() == 1) {
        if(posix_spawnattr_set_launch_type_np(&attr, CS_LAUNCH_TYPE_SYSTEM_SERVICE) != 0) {
            perror("posix_spawnattr_set_launch_type_np");
            return 1;
        }
    }
    
    if(posix_spawnattr_setflags(&attr, POSIX_SPAWN_SETEXEC) != 0) {
        perror("posix_spawnattr_set_flags");
        return 1;
    }
    
    pid_t child_pid;
    extern char **environ;
    posix_spawn(&child_pid, execPath, NULL, &attr, execArgs, environ);
    perror("posix_spawn");
    return 1;
}
