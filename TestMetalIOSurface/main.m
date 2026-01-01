@import Darwin;
@import ImageIO;
#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/QuartzCore.h>
#import <simd/simd.h>
#include <dlfcn.h>
#import "IOMobileFramebuffer.h"

#define kUTTypePNG CFSTR("public.png")
#define USE_HW_FORMAT 0

BOOL CGImageWriteToFile(CGImageRef image, NSString *path) {
    CFURLRef url = (__bridge CFURLRef)[NSURL fileURLWithPath:path];
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL(url, kUTTypePNG, 1, NULL);
    if (!destination) {
        NSLog(@"Failed to create CGImageDestination for %@", path);
        return NO;
    }

    CGImageDestinationAddImage(destination, image, nil);

    if (!CGImageDestinationFinalize(destination)) {
        NSLog(@"Failed to write image to %@", path);
        CFRelease(destination);
        return NO;
    }

    CFRelease(destination);
    return YES;
}

typedef struct {
    vector_float4 position;
    vector_float4 color;
} Vertex;

@interface MetalRenderer : NSObject
@property(retain) id<MTLDevice> device;
@property(retain) id<MTLCommandQueue> commandQueue;
@property(retain) id<MTLRenderPipelineState> pipelineState;
@property IOSurfaceRef surface;
@property(retain) id<MTLTexture> surfaceTexture;
@end

@implementation MetalRenderer

- (instancetype)init {
    self = [super init];
    CFPreferencesSetAppValue((const CFStringRef)@"EnableSimApple5", (__bridge CFPropertyListRef)@(YES), (const CFStringRef)@"com.apple.Metal");
    
    _device = MTLCreateSystemDefaultDevice();
    _commandQueue = [_device newCommandQueue];
    
    NSError *error = nil;
    NSString *source = @" \
#include <metal_stdlib> \n \
using namespace metal; \n \
 \n \
struct Vertex { \n \
    float4 position; \n \
    float4 color; \n \
}; \n \
 \n \
struct VertexOut { \n \
    float4 position [[position]]; \n \
    float4 color; \n \
}; \n \
    \n \
vertex VertexOut vertex_main(uint vertex_id [[vertex_id]], \n \
                             const device Vertex *vertices [[buffer(0)]]) { \n \
    VertexOut out; \n \
    out.position = vertices[vertex_id].position; \n \
    out.color = vertices[vertex_id].color; \n \
    return out; \n \
} \n \
 \n \
fragment float4 fragment_main(VertexOut in [[stage_in]]) { \n \
    return in.color; \n \
}";
    id<MTLLibrary> library = [_device newLibraryWithSource:source options:nil error:&error];
    if (!library) {
        NSLog(@"Error compiling shaders: %@", error);
        return nil;
    }
    
    // Create pipeline
    MTLRenderPipelineDescriptor *desc = [[MTLRenderPipelineDescriptor alloc] init];
    desc.vertexFunction = [library newFunctionWithName:@"vertex_main"];
    desc.fragmentFunction = [library newFunctionWithName:@"fragment_main"];
#if USE_HW_FORMAT
    desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA10_XR;
#else
    desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
#endif
    
    _pipelineState = [_device newRenderPipelineStateWithDescriptor:desc error:&error];
    if (error) {
        NSLog(@"Pipeline error: %@", error);
    }
    
    CGSize screenSize;
    IOMobileFramebufferRef fbConn;
    IOMobileFramebufferGetMainDisplay(&fbConn);
    IOMobileFramebufferGetDisplaySize(fbConn, &screenSize);
    [self createIOSurfaceBackedTexture:screenSize.width height:screenSize.height];
    return self;
}

- (void)createIOSurfaceBackedTexture:(size_t)width height:(size_t)height {
    int tileWidth = 8;
    int tileHeight = 16;
    int widthLonger = ((width-1) & ~(tileWidth-1))+tileWidth;
    int heightLonger = ((height-1) & ~(tileHeight-1))+tileHeight;
    int bytesPerElement = 8;
    size_t bytesPerRow = widthLonger * bytesPerElement;
    size_t size = widthLonger * heightLonger * bytesPerElement;
    size_t totalBytes = size + 0x20000;
    NSDictionary *surfaceProps = @{
        //@"IOSurfaceAllocSize": @(totalBytes),
        @"IOSurfaceCacheMode": @0x700, // 1024: older, 0x700: 18.0+?
        @"IOSurfaceWidth": @(width),
        @"IOSurfaceHeight": @(height),
        @"IOSurfaceMapCacheAttribute": @0,
        @"IOSurfaceMemoryRegion": @"PurpleGfxMem",
        @"IOSurfacePixelSizeCastingAllowed": @0,
        @"IOSurfaceBytesPerElement": @(bytesPerElement),
#if USE_HW_FORMAT
        @"IOSurfacePixelFormat": @((uint32_t)'&w4a'),
        @"IOSurfacePlaneInfo": @[
            @{
                @"IOSurfacePlaneWidth": @(width),
                @"IOSurfacePlaneHeight": @(height),
                @"IOSurfacePlaneBytesPerRow": @(bytesPerRow),
                @"IOSurfacePlaneOffset": @0,
                @"IOSurfacePlaneSize": @(totalBytes),
                
                @"IOSurfaceAddressFormat": @3,
                @"IOSurfacePlaneBytesPerCompressedTileHeader": @2,
                @"IOSurfacePlaneBytesPerElement": @(bytesPerElement),
                @"IOSurfacePlaneCompressedTileDataRegionOffset": @0,
                @"IOSurfacePlaneCompressedTileHeaderRegionOffset": @(size),
                @"IOSurfacePlaneCompressedTileHeight": @(tileHeight),
                @"IOSurfacePlaneCompressedTileWidth": @(tileWidth),
                @"IOSurfacePlaneCompressionType": @2,
                @"IOSurfacePlaneHeightInCompressedTiles": @(heightLonger / tileHeight),
                @"IOSurfacePlaneWidthInCompressedTiles": @(widthLonger / tileWidth),
            }
        ],
#else
        @"IOSurfacePixelFormat": @((uint32_t)'BGRA'),
#endif
    };
    _surface = IOSurfaceCreate((__bridge CFDictionaryRef)surfaceProps);
    
    MTLTextureDescriptor *texDesc = [[MTLTextureDescriptor alloc] init];
    texDesc.textureType = MTLTextureType2D;
#if USE_HW_FORMAT
    texDesc.pixelFormat = MTLPixelFormatBGRA10_XR;
#else
    texDesc.pixelFormat = MTLPixelFormatBGRA8Unorm;
#endif
    texDesc.width = (NSUInteger)width;
    texDesc.height = (NSUInteger)height;
    texDesc.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    
    _surfaceTexture = [_device newTextureWithDescriptor:texDesc iosurface:_surface plane:0];
}

- (void)renderToIOSurface {
    Vertex vertices[] = {
        {{-0.8, -0.8, 0, 1}, {1, 0, 0, 1}},
        {{ 0.8, -0.8, 0, 1}, {0, 1, 0, 1}},
        {{ 0.0,  0.8, 0, 1}, {0, 0, 1, 1}},
    };
    
    id<MTLBuffer> vertexBuffer = [_device newBufferWithBytes:vertices
                                                      length:sizeof(vertices)
                                                     options:MTLResourceStorageModeShared];
    
    MTLRenderPassDescriptor *passDesc = [MTLRenderPassDescriptor renderPassDescriptor];
    passDesc.colorAttachments[0].texture = _surfaceTexture;
    passDesc.colorAttachments[0].loadAction = MTLLoadActionClear;
    passDesc.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    passDesc.colorAttachments[0].storeAction = MTLStoreActionStore;
    
    id<MTLCommandBuffer> cmdBuffer = [_commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [cmdBuffer renderCommandEncoderWithDescriptor:passDesc];
    [encoder setRenderPipelineState:_pipelineState];
    [encoder setVertexBuffer:vertexBuffer offset:0 atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder endEncoding];
    [cmdBuffer commit];
    [cmdBuffer waitUntilCompleted];
    
    int token;
    CGRect frame = CGRectMake(0, 0, 0, 0);
    IOMobileFramebufferRef fbConn;
    IOMobileFramebufferGetMainDisplay(&fbConn);
    IOMobileFramebufferGetDisplaySize(fbConn, &frame.size);
    IOMobileFramebufferSwapBegin(fbConn, &token);
    IOMobileFramebufferSwapSetLayer(fbConn, 0, _surface, frame, frame, 0);
    IOMobileFramebufferSwapEnd(fbConn);
    
    [self saveTexture:_surfaceTexture];
}

- (void)saveTexture:(id<MTLTexture>)texture {
    NSUInteger width = texture.width;
    NSUInteger height = texture.height;
    NSUInteger bytesPerPixel = 8;
    NSUInteger bytesPerRow = bytesPerPixel * width;

    void *rawData = malloc(height * bytesPerRow);
    MTLRegion region = {
        {0, 0, 0},
        {width, height, 1}
    };

    [texture getBytes:rawData
          bytesPerRow:bytesPerRow
           fromRegion:region
          mipmapLevel:0];

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(rawData, width, height, 8, bytesPerRow,
                                                 colorSpace, kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst);

    CGImageRef imageRef = CGBitmapContextCreateImage(context);
    CGImageWriteToFile(imageRef, @"/tmp/output.png");

    CGImageRelease(imageRef);
    CGContextRelease(context);
    CGColorSpaceRelease(colorSpace);

    free(rawData);
    NSLog(@"✅ Texture saved to output.png");
}

@end

void xpc_connection_set_instance(xpc_connection_t connection, const uuid_t uuid);
void testCompiler() {
    uuid_t uuid;
    uuid_generate(uuid);
    xpc_connection_t connection = xpc_connection_create("com.apple.MTLCompilerService", 0);
    xpc_connection_set_instance(connection, uuid);
    xpc_connection_set_event_handler(connection, ^(xpc_object_t object) {
        NSLog(@"Process received event: %@", [object description]);
    });
    xpc_connection_resume(connection);

    xpc_object_t dict = xpc_dictionary_create(NULL, NULL, 0);
    xpc_dictionary_set_uint64(dict, "requestType", 9); // XPCCompilerConnection::checkConnectionActive(bool&)
    xpc_object_t object = xpc_connection_send_message_with_reply_sync(connection, dict);
    NSLog(@"Received synced event: %@", [object description]);
    NSLog(@"XPC connection now: %@", [connection description]);
    sleep(1);
    xpc_connection_cancel(connection);
}

int main(int argc, const char * argv[]) {
    testCompiler();
    
    @autoreleasepool {
        MetalRenderer *renderer = [[MetalRenderer alloc] init];
        [renderer renderToIOSurface];
        sleep(10);
    }

    return 0;
}
