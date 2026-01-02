//
//  xpc.h
//  
//
//  Created by Duy Tran on 2/1/26.
//

@import ObjectiveC;

#define XPC_CONNECTION_MACH_SERVICE_LISTENER (1 << 0)
#define XPC_CONNECTION_MACH_SERVICE_PRIVILEGED (1 << 1)

typedef id xpc_object_t;
typedef id xpc_connection_t;

void xpc_add_bundle(char *, int);
xpc_connection_t xpc_connection_create_mach_service(const char * name, dispatch_queue_t targetq, uint64_t flags);
