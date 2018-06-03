//
//  PDDImageContext.m
//  PDDImage
//
//  Created by 郝一鹏 on 2018/5/29.
//  Copyright © 2018年 郝一鹏. All rights reserved.
//

#import "PDDImageContext.h"
#import <OpenGLES/EAGLDrawable.h>
#import <AVFoundation/AVFoundation.h>

// TODO: @pdd 优化
static const NSInteger kMaxSharedProgramsAllowedInCache = 40;

extern dispatch_queue_attr_t PDDImageDefaultQueueAttribute(void);

@interface PDDImageContext () {

    // TODO: @pdd 优化
    NSMutableDictionary *_shaderProgramCache;
    NSMutableArray *_shaderProgramUsageHistory;
    EAGLSharegroup *_shadergroup;
}

@end

@implementation PDDImageContext

@synthesize context = _context;
@synthesize currentShaderProgram = _currentShaderProgram;
@synthesize contextQueue = _contextQueue;
@synthesize coreVideoTextureCache = _coreVideoTextureCache;
@synthesize framebufferCache = _framebufferCache;

static void *openGLESContextQueueKey;

- (instancetype)init {

    if (!(self = [super init])) {
        return nil;
    }

    openGLESContextQueueKey = &openGLESContextQueueKey;x
    _contextQueue = dispatch_queue_create("com.bytedance.PDDImage.openGLESContextQueue", PDDImageDefaultQueueAttribute());

#if OS_OBJECT_USE_OBJC
    dispatch_queue_set_specific(_contextQueue, openGLESContextQueueKey, (__bridge void*)self, NULL);
#endif
    _shaderProgramCache = [[NSMutableDictionary alloc] init];
    _shaderProgramUsageHistory = [[NSMutableArray alloc] init];

    return self;
}

+ (void *)contextKey {
    return openGLESContextQueueKey;
}

+ (instancetype)sharedImageProcessingContext {
    static PDDImageContext *_sharedImageProcessingContext = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        _sharedImageProcessingContext = [[[self class] alloc]   init];
    });

    return _sharedImageProcessingContext;
}

+ (dispatch_queue_t)sharedContextQueue {
    return [[self sharedImageProcessingContext] contextQueue];
}

+ (PDDImageFramebufferCache *)sharedFramebufferCache {
    return [[self sharedImageProcessingContext] framebufferCache];
}

+ (void)useImageProcessingContext {
    [[PDDImageContext sharedImageProcessingContext] useAsCurrentContext];
}

- (void)useAsCurrentContext {

    EAGLContext *imageProcessingContext = [self context];
    if ([EAGLContext currentContext] != imageProcessingContext) {
        [EAGLContext setCurrentContext:imageProcessingContext];
    }
}

+ (void)setActiveShaderProgram:(GLProgram *)shaderProgram {
    PDDImageContext *shaderContext = [PDDImageContext sharedImageProcessingContext];
    [shaderContext setContextShaderProgram:shaderProgram];
}

- (void)setContextShaderProgram:(GLProgram *)shaderProgram {

    // TODO: @pdd
    [self useAsCurrentContext];

    if (self.currentShaderProgram != shaderProgram) {
        self.currentShaderProgram = shaderProgram;
        [shaderProgram use];
    }
}

+ (GLint)maximumTextureSizeForThisDevice {
    static dispatch_once_t onceToken;
    static GLint maxTextureSize = 0;

    dispatch_once(&onceToken, ^{
        [self useImageProcessingContext];
        glGetIntegerv(GL_MAX_TEXTURE_SIZE, &maxTextureSize);
    });

    return maxTextureSize;
}

+ (GLint)maximumTextureUnitsForThisDevice {
    static dispatch_once_t onceToken;
    static GLint maxTextureUnits = 0;

    dispatch_once(&onceToken, ^{
        [self useImageProcessingContext];
        glGetIntegerv(GL_MAX_TEXTURE_IMAGE_UNITS, &maxTextureUnits);
    });

    return maxTextureUnits;
}

// 一种代码执行一次
+ (BOOL)deviceSupportsOpenGLESExtension:(NSString *)extension {

    static dispatch_once_t onceToken;
    static NSArray *extensionNames = nil;

    // Cache extensions for later quick reference, since this won't change for a given device
    dispatch_once(&onceToken, ^{
        [PDDImageContext useImageProcessingContext];
        NSString *extensionsString = [NSString stringWithCString:(const char *)glGetString(GL_EXTENSIONS) encoding:NSASCIIStringEncoding];
        extensionNames = [extensionsString componentsSeparatedByString:@" "];
    });

    return [extensionNames containsObject:extension];
}

+ (BOOL)deviceSupportsRedTextures {
    static dispatch_once_t onceToken;
    static BOOL supportsRedTextures = NO;

    dispatch_once(&onceToken, ^{
        supportsRedTextures = [PDDImageContext deviceSupportsOpenGLESExtension:@"GL_EXT_texture_rg"];
    });

    return supportsRedTextures;
}

+ (BOOL)deviceSupportsFramebufferReads;
{
    static dispatch_once_t pred;
    static BOOL supportsFramebufferReads = NO;

    dispatch_once(&pred, ^{
        supportsFramebufferReads = [PDDImageContext deviceSupportsOpenGLESExtension:@"GL_EXT_shader_framebuffer_fetch"];
    });

    return supportsFramebufferReads;
}

+ (CGSize)sizeThatFitsWithinATextureForSize:(CGSize)inputSize {

    GLint maxTextureSize = [self maximumTextureSizeForThisDevice];
    if ( (inputSize.width < maxTextureSize) && (inputSize.height < maxTextureSize)) {
        return inputSize;
    }

    CGSize adjustedSize;

    if (inputSize.width > inputSize.height) {
        adjustedSize.width = (CGFloat)maxTextureSize;
        adjustedSize.height = ((CGFloat)maxTextureSize / inputSize.width) * inputSize.height;
    } else {
        adjustedSize.height = (CGFloat)maxTextureSize;
        adjustedSize.width = ((CGFloat)maxTextureSize / inputSize.height) * inputSize.width;
    }

    return adjustedSize;
}

- (void)presentBufferForDisplay {

    // Displays a renderbuffer’s contents on screen.
    [self.context presentRenderbuffer:GL_RENDERBUFFER];
}

- (GLProgram *)programForVertexShaderString:(NSString *)vertexShaderString fragmentShaderString:(NSString *)fragmentShaderString {

    NSString *lookupKeyForShaderProgram = [NSString stringWithFormat:@"V: %@ - F: %@", vertexShaderString, fragmentShaderString];
    GLProgram *programFromCache = [_shaderProgramCache objectForKey:lookupKeyForShaderProgram];

    if (programFromCache == nil) {
        programFromCache = [[GLProgram alloc] initWithVertexShaderString:vertexShaderString fragmentShaderString:fragmentShaderString];
        [_shaderProgramCache setObject:programFromCache forKey:lookupKeyForShaderProgram];
    }
    return programFromCache;
}

- (void)useSharegroup:(EAGLSharegroup *)sharegroup {

    NSAssert(_context == nil, @"Unable to use a share group when the context has already been created. Call this method before you use the context for the first time.");
    _shadergroup = sharegroup;
}

- (EAGLContext *)createContext {

    EAGLContext *context = [[EAGLContext alloc] initWithAPI:kEAGLRenderingAPIOpenGLES2 sharegroup:_shadergroup];
    NSAssert(context != nil, @"Unable to create an OpenGL ES 2.0 context. The GPUImage framework requires OpenGL ES 2.0 support to work.");
    return context;
}

#pragma mark -
#pragma mark Manage fast texture upload

+ (BOOL)supportsFastTextureUpload {
#if TARGET_IPHONE_SIMULATOR
    return NO;
#else

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wtautological-pointer-compare"
    return (CVOpenGLESTextureCacheCreate != NULL);
#pragma clang diagnostic pop

#endif
}

#pragma mark -
#pragma mark Accessors

- (EAGLContext *)context {
    if (_context == nil)
    {
        _context = [self createContext];
        [EAGLContext setCurrentContext:_context];

        // Set up a few global settings for the image processing pipeline
        glDisable(GL_DEPTH_TEST);
    }

    return _context;
}

- (CVOpenGLESTextureCacheRef)coreVideoTextureCache {

    if (_coreVideoTextureCache) {
#if defined(__IPHONE_6_0)
        CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, [self context], NULL, &_coreVideoTextureCache);
#else
        CVReturn err = CVOpenGLESTextureCacheCreate(kCFAllocatorDefault, NULL, (__bridge void *)[self context], NULL, &_coreVideoTextureCache);
#endif
        if (err) {
            NSAssert(NO, @"Error at CVOpenGLESTextureCacheCreate %d", err);
        }
    }
    return _coreVideoTextureCache;
}

- (PDDImageFramebufferCache *)framebufferCache {
    if (_framebufferCache == nil) {
        _framebufferCache = [[PDDImageFramebufferCache alloc] init];
    }
    return _framebufferCache;
}

@end
