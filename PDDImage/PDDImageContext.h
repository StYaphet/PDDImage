//
//  PDDImageContext.h
//  PDDImage
//
//  Created by 郝一鹏 on 2018/5/29.
//  Copyright © 2018年 郝一鹏. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "GLProgram.h"
#import "PDDImageFramebuffer.h"
#import "PDDImageFramebufferCache.h"

typedef NS_ENUM(NSUInteger, PDDImageRotationMode) {
    kPDDImageNoRotation,
    kPDDImageRotateLeft,
    kPDDImageRotateRight,
    kPDDImageFlipVertical,
    kPDDImageFlipHorizontal,
    kPDDImageRotateRightFlpVertical,
    kPDDImageRotateRightFlpHorizontal,
    kPDDImageRotate180,
};

@interface PDDImageContext : NSObject

@property (nonatomic, readonly) dispatch_queue_t contextQueue;
@property (nonatomic, readwrite) GLProgram *currentShaderProgram;
@property (nonatomic, readonly) EAGLContext *context;
@property (readonly) CVOpenGLESTextureCacheRef *coreVideoTextureCache; // TODO: @pdd这里没写nonatomic，是atomic的吗
@property (readonly) PDDImageFramebufferCache *frameBufferCache; // TODO: @pdd这里没写nonatomic，是atomic的吗

+ (void)contextKey;
+ (PDDImageContext *)sharedImageProcessingContext;
+ (dispatch_queue_t)sharedContextQueue;
+ (PDDImageFramebufferCache *)sharedFramebufferCache;
+ (void)useImageProcessingContext;
- (void)userAsCurrentContext;
+ (void)setActiveShaderProgram:(GLProgram *)shaderProgram;
- (void)setContextShaderProgram:(GLProgram *)shaderProgram;
+ (GLint)maximumTextureSizeForThisDevice;
+ (GLint)maximumTextureUnitsForThisDevice;
+ (BOOL)deviceSupportsOpenGLESExtension:(NSString *)extension;
+ (BOOL)deviceSupportsRedTextures;
+ (BOOL)deviceSupportsFramebufferReads;
+ (CGSize)sizeThatFitsWithinATextureForSize:(CGSize)inputSize;

- (void)presentBufferForDisplay;
- (GLProgram *)programForVertexShaderString:(NSString *)vertexShaderString fragmentShaderString:(NSString *)fragmentShaderString;

- (void)useSharegroup:(EAGLSharegroup *)sharegroup;

// Manage fast texture upload
+ (BOOL)supportsFastTextureUpload;

@end

@protocol PDDImageInput <NSObject>

- (void)newFrameReadyAtTime:(CMTime)frameTime atIndex:(NSInteger)textureIndex;
- (void)setInputFramebuffer:(PDDImageFramebuffer *)newInputFramebuffer atIndex:(NSInteger)textureIndex;
- (NSInteger)nextAvailableTextureIndex;
- (void)setInputSize:(CGSize)newSize atIndex:(NSInteger)textureIndex;
- (void)setInputRotation:(PDDImageRotationMode)newInputRotation atIndex:(NSInteger)textureIndex;
- (CGSize)maximumOutputSize;
- (void)endProcessing;
- (BOOL)shouldIgnoreUpdatesToThisTarget;
- (BOOL)enabled;
- (BOOL)wantsMonochromeInput;
- (void)setCurrentlyReceivingMonochromeInput:(BOOL)newValue;

@end
