//
//  PDDImageFramebuffer.h
//  PDDImage
//
//  Created by 郝一鹏 on 2018/5/29.
//  Copyright © 2018年 郝一鹏. All rights reserved.
//

#import <Foundation/Foundation.h>
#if TARGET_IPHONE_SIMULATER || TARGET_OS_IPHONE
#import <OpenGLES/EAGL.h>
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#else
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#endif

#import <QuartzCore/QuartzCore.h>
#import <CoreMedia/CoreMedia.h>

typedef struct GPUTextureOptions {
    GLenum minFilter;
    GLenum magFilter;
    GLenum warpS;
    GLenum warpT;
    GLenum imternalFormat;
    GLenum format;
    GLenum type;
} GPUTextureOptions;

// GPUImageFramebuffer类用于管理帧缓冲对象，负责帧缓冲对象的创建和销毁，读取帧缓冲内容，其中纹理附件涉及到了相关的纹理选项。
// 因此，它提供的属性也是和帧缓存、纹理附件、纹理选项等相关

@interface PDDImageFramebuffer : NSObject

@property (readonly) CGSize size;                           // 帧缓存大小
@property (readonly) GPUTextureOptions textureOptions;      // 纹理选项
@property (readonly) GLuint texture;                        // 纹理缓存
@property (readonly) BOOL missingFramebuffer;               // 是否仅有纹理没有帧缓存

// Initialization and teardown
- (id)initWithSize:(CGSize)framebufferSize;
- (id)initWithSize:(CGSize)framebufferSize textureOptions:(GPUTextureOptions)fboTextureOptions onlyTexture:(BOOL)onlyGenerateTexture;
- (id)initWithSize:(CGSize)framebufferSize overriddenTexture:(GLuint)inputTexture;

// Usage
- (void)avtivateFramebuffer;

// Reference counting
- (void)lock;
- (void)unlock;
- (void)clearAllLocks;
- (void)disableReferenceCounting;
- (void)enableReferenceCounting;

// Image capture
- (CGImageRef)newCGImageFromFramebufferContents;
- (void)restoreRenderTarget;

// Raw data bytes
- (void)lockForReading;
- (void)unlockAfterReading;
- (NSUInteger)bytesPerRow;
- (GLubyte *)byteBuffer;
- (CVPixelBufferRef)pixelBuffer;



@end
