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

    // TODO: @pdd 这里是创建纹理的流程
    glActiveTexture(GL_TEXTURE1);
    glGenTextures(1, &_texture);
    glBindTexture(GL_TEXTURE_2D, _texture);

    // https://learnopengl-cn.readthedocs.io/zh/latest/01%20Getting%20started/06%20Textures/
    // 设置纹理过滤方式，常用的纹理过滤方式有 GL_NEAREST 、 GL_LINEAR
    // 当进行放大(magnify)和缩小(minify)操作的时候可以设置纹理过滤的选项，比如你可以在纹理被缩小的时候使用邻近过滤，被放大时使用线性过滤。
    // 我们需要使用 glTexParameter* 函数为放大和缩小指定过滤方式
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MIN_FILTER, _textureOptions.minFilter);
    glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_MAG_FILTER, _textureOptions.magFilter);

    // This is necessary for non-power-of-two textures
    // 设置纹理的环绕方式，环绕方式有GL_REPEAT、GL_MIRRORED_REPEAT、GL_CLAMP_TO_EDGE、GL_CLAMP_TO_BORDER
    // 每个选项都可以使用 glTexParmaters* 函数对单独的一个坐标轴进行设置
    // 因为这里是2D纹理，所以可以在对两个坐标轴(s、t)进行设置
    // 第一个参数指定了纹理目标，因为使用的是2D纹理，因此纹理目标是GL_TEXTURE_2D。
    // 第二个参数需要指定设置的选项与应用的纹理轴。我们打算配置的是WRAP选项，并且指定S和T轴。
    // 最后一个参数需要我们传递一个环绕方式，即_textureOptions中的warpS与warpT。
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
