//
//  PDDImageFramebuffer.m
//  PDDImage
//
//  Created by 郝一鹏 on 2018/5/29.
//  Copyright © 2018年 郝一鹏. All rights reserved.
//

#import "PDDImageFramebuffer.h"

// TODO: @pdd 这个函数应该放在PDDImageOutput中，但是因为PDDImageFramebuffer用到了这个方法，所以先放在这
void runSynchronouslyOnVideoProcessingQueue(void (^block)(void)) {

//    dispatch_queue_t videoProcessingQueue = [PDDImageContext sharedContextQueue];
    dispatch_queue_t videoProcessingQueue;
#if !OS_OBJECT_UES_OBJC
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
    if (dispatch_get_current_queue() == videoProcessingQueue)
#pragma clang diagnostic pop
#else
    if (dispatch_get_specific([PDDImageContext contextKey]))
#endif
    {
        block();
    } else {
        dispatch_sync(videoProcessingQueue, block);
    }
}

@interface PDDImageFramebuffer () {
    GLuint framebuffer;
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
    CVPixelBufferRef renderTarget;
    CVOpenGLESTextureRef renderTexture;
    NSUInteger readLockCount;
#else
#endif
    NSUInteger framebufferReferenceCount;
    BOOL referenceCountingDisabled;
}

- (void)generateFramebuffer;
- (void)generateTexture;
- (void)destoryFramebuffer;

@end

void dataProviderReleaseCallback (void *info, const void *data, size_t size);
void dataProviderUnlockCallback (void *info, const void *data, size_t size);

@implementation PDDImageFramebuffer

// TODO: @pdd 这些合成现在是不是不需要了
@synthesize size = _size;
@synthesize textureOptions = _textureOptions;
@synthesize texture = _texture;
@synthesize missingFramebuffer = _missingFramebuffer;

#pragma mark -
#pragma mark - Initialization and teardown

- (id)initWithSize:(CGSize)framebufferSize textureOptions:(GPUTextureOptions)fboTextureOptions onlyTexture:(BOOL)onlyGenerateTexture {

    if (!(self = [super init])) {
        return nil;
    }

    _textureOptions = fboTextureOptions;
    _size = framebufferSize;
    framebufferReferenceCount = 0;
    referenceCountingDisabled = NO;
    _missingFramebuffer = onlyGenerateTexture;

    if (_missingFramebuffer) {
        runSynchronouslyOnVideoProcessingQueue(^{
//            [PDDImageContext useImageProcessingContext];
            [self generateTexture];
            framebuffer = 0;
        });
    }
    else
    {
        [self generateFramebuffer];
    }
    return self;
}

- (id)initWithSize:(CGSize)framebufferSize overriddenTexture:(GLuint)inputTexture {

    if (!(self = [super init])) {
        return nil;
    }

    GPUTextureOptions defaultTextureOptions;
    defaultTextureOptions.minFilter = GL_LINEAR;
    defaultTextureOptions.magFilter = GL_LINEAR;
    defaultTextureOptions.warpS = GL_CLAMP_TO_EDGE;
    defaultTextureOptions.warpT = GL_CLAMP_TO_EDGE;
    defaultTextureOptions.imternalFormat = GL_RGBA;
    defaultTextureOptions.format = GL_RGBA;
    defaultTextureOptions.type = GL_UNSIGNED_BYTE;

    _textureOptions = defaultTextureOptions;
    _size = framebufferSize;
    framebufferReferenceCount = 0;
    referenceCountingDisabled = YES;

    _texture = inputTexture;

    return self;
}

- (id)initWithSize:(CGSize)framebufferSize {

    GPUTextureOptions defaultTextureOptions;
    defaultTextureOptions.minFilter = GL_LINEAR;
    defaultTextureOptions.magFilter = GL_LINEAR;
    defaultTextureOptions.warpS = GL_CLAMP_TO_EDGE;
    defaultTextureOptions.warpT = GL_CLAMP_TO_EDGE;
    defaultTextureOptions.imternalFormat = GL_RGBA;
    defaultTextureOptions.format = GL_RGBA;
    defaultTextureOptions.type = GL_UNSIGNED_BYTE;

    if (!(self = [self initWithSize:framebufferSize textureOptions:defaultTextureOptions onlyTexture:NO])) {
        return nil;
    }

    return self;
}

- (void)dealloc {

    [self destoryFramebuffer];
}

#pragma mark -
#pragma mark - Internal

- (void)generateTexture {

    // TODO: @pdd 这里纹理创建需要再看一下流程
    glActiveTexture(GL_TEXTURE1);
    glGenTextures(1, &_texture);
    glBindTexture(GL_TEXTURE_2D, _texture);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, _textureOptions.minFilter);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, _textureOptions.magFilter);
    // This is necessary for non-power-of-two textures
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, _textureOptions.warpS);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, _textureOptions.warpT);

    // TODO: Handle mipmaps
}

- (void)generateFramebuffer {

    runSynchronouslyOnVideoProcessingQueue(^{
//        [PDDImageContext useImageProcessingContext];

        glGenFramebuffers(1, &framebuffer);
        glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);

//        if ([PDDImageContext supportFastTextureUpload]) {
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
        CVOpenGLESTextureRef coreVideoTextureCache = [[PDDImageContext sharedImageProcessingContext] coreVideoTextureCache];
        CFDictionaryRef empty; // empty value for attr values.
        CFMutableDictionaryRef attrs;
        empty = CFDictionaryCreate(kCFAllocatorDefault, NULL, NULL, 0, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks); // our empty IOSurface properties dictionary
        attrs = CFDictionaryCreateMutable(kCFAllocatorDefault, 1, &kCFTypeDictionaryKeyCallBacks, &kCFTypeDictionaryValueCallBacks);

        CVReturn err = CVPixelBufferCreate(kCFAllocatorDefault, (int)_size.width, (int)_size.height, kCVPixelFormatType_32RGBA, attrs, &renderTarget);
        if (err) {
            NSLog(@"FBO size: %f, %f", _size.width, _size.height);
            NSAssert(NO, @"Error at CVPixelBufferCreate %d", err);
        }

        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault, coreVideoTextureCache, renderTarget, NULL, GL_TEXTURE_2D, _textureOptions.imternalFormat, (int)_size.width, (int)_size.height, _textureOptions.format, _textureOptions.type, 0, &renderTexture);

        if (err) {
            NSAssert(NO, @"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }
        CFRelease(attrs);
        CFRelease(empty);

        glBindTexture(CVOpenGLESTextureGetTarget(renderTexture), CVOpenGLESTextureGetName(renderTexture));
        _texture = CVOpenGLESTextureGetName(renderTexture);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, _textureOptions.warpS);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, _textureOptions.warpT);

        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, CVOpenGLESTextureGetName(renderTexture), 0);
#endif
//        }
//        else
//        {
        [self generateTexture];
        glBindTexture(GL_TEXTURE_2D, _texture);
        glTexImage2D(GL_TEXTURE_2D, 0, _textureOptions.imternalFormat, (int)_size.width, (int)_size.height, 0, _textureOptions.format, _textureOptions.type, 0);
        glFramebufferTexture2D(GL_FRAMEBUFFER, GL_COLOR_ATTACHMENT0, GL_TEXTURE_2D, _texture, 0);
//        }

#ifndef NS_BLOCK_ASSERTIONS
        GLenum status = glCheckFramebufferStatus(GL_FRAMEBUFFER);
        NSAssert(status == GL_FRAMEBUFFER_COMPLETE, @"Incomplete filter FBO: %d", status);
#endif
        glBindTexture(GL_TEXTURE_2D, 0);
    });
}

@end
