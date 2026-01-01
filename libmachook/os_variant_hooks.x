@import Darwin;
#include "interpose.h"

bool os_variant_is_basesystem(const char *subsystem);
bool os_variant_is_recovery(const char *subsystem);
bool os_variant_allows_internal_security_policies(const char *subsystem);
bool os_variant_has_internal_content(const char *subsystem);
bool os_variant_has_internal_ui(const char *subsystem);
bool os_variant_has_internal_diagnostics(const char *subsystem);

bool hooked_os_variant_is_basesystem(const char * subsystem) {
    return false;
}

bool hooked_os_variant_is_recovery(const char * subsystem) {
    return false;
}

bool hooked_os_variant_allows_internal_security_policies(const char * subsystem) {
    return true;
}

bool hooked_os_variant_has_internal_content(const char * subsystem) {
    return true;
}

bool hooked_os_variant_has_internal_ui(const char * subsystem) {
    return true;
}

bool hooked_os_variant_has_internal_diagnostics(const char * subsystem) {
    return true;
}

DYLD_INTERPOSE(hooked_os_variant_is_basesystem, os_variant_is_basesystem);
DYLD_INTERPOSE(hooked_os_variant_is_recovery, os_variant_is_recovery);
DYLD_INTERPOSE(hooked_os_variant_allows_internal_security_policies, os_variant_allows_internal_security_policies);
DYLD_INTERPOSE(hooked_os_variant_has_internal_content, os_variant_has_internal_content);
DYLD_INTERPOSE(hooked_os_variant_has_internal_diagnostics, os_variant_has_internal_diagnostics);
