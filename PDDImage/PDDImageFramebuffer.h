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

@interface PDDImageFramebuffer : NSObject

@property (readonly) CGSize size;
@property (readonly) GPUTextureOptions textureOptions;
@property (readonly) GLuint texture;
@property (readonly) BOOL missingFramebuffer;

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
