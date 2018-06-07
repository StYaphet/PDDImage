//
//  PDDImageOutput.h
//  PDDImage
//
//  Created by 郝一鹏 on 2018/6/3.
//  Copyright © 2018年 郝一鹏. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "PDDImageContext.h"
#import "PDDImageFramebuffer.h"

#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else

typedef NS_ENUM(NSInteger, UIImageOrientation) {
    UIImageOrientationUp,            // default orientation
    UIImageOrientationDown,          // 180 deg rotation
    UIImageOrientationLeft,          // 90 deg CCW
    UIImageOrientationRight,         // 90 deg CW
    UIImageOrientationUpMirrored,    // as above but image mirrored along other axis. horizontal flip
    UIImageOrientationDownMirrored,  // horizontal flip
    UIImageOrientationLeftMirrored,  // vertical flip
    UIImageOrientationRightMirrored, // vertical flip
};

#endif

dispatch_queue_attr_t GPUImageDefaultQueueAttribute(void);
void runOnMainQueueWithoutDeadLocking(void(^block)(void));
void runSynchronouslyOnVideoProcessingQueue(void(^block)(void));
void runAsynchronouslyOnVideoProcessingQueue(void(^block)(void));
void runSynchronouslyOnContextQueue(PDDImageContext *context, void(^block)(void));
void runAsynchronouslyOnContextQueue(PDDImageContext *context, void(^block)(void));
void reportAvailableMemoryForPDDImage(NSString *tag);

@class PDDImageMovieWriter;

@interface PDDImageOutput : NSObject {

    // 输出的帧缓存对象
    PDDImageFramebuffer *_outputFramebuffer;
    // target列表，target纹理索引列表
    NSMutableArray *_targets, *_targetTextureIndices;
    // 纹理尺寸
    CGSize _inputTextureSize, _cachedMaximumOutputSize, _forcedMaximumSize;
    BOOL _overrideInputSize;
    BOOL _allTargetsWantMonocharomeData;

    // 设置下一帧提取图片
    BOOL _usingNextFrameForImageCapture;
}

// 是否使用mipmaps
@property (nonatomic, assign) BOOL *shouldSmoothlyScaleOutput;
// 是否忽略处理当前Target
@property (nonatomic, assign) BOOL *shouldIgnoreUpdatesToThisTarget;
@property (nonatomic, strong) PDDImageMovieWriter *audioEncodingTarget;
// 当前忽略处理的Target
@property (nonatomic, weak) id<PDDImageInput> targetToIgnoreForUpdates;
// 每帧处理完回调
@property (nonatomic, copy) void(^frameProcessingCompletionBlock)(PDDImageOutput *, CMTime);
// 是否启用渲染目标
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) GPUTextureOptions outputTextureOptions;

- (void)setInputFramebufferForTarget:(id<PDDImageInput>)target atIndex:(NSInteger)inputTextureIndex;
- (PDDImageFramebuffer *)framebufferForOutput;
- (void)removeOutputFramebuffer;
- (void)notifyTargetsAboutNewOutputTexture;

- (NSArray *)targets;

- (void)addTarget:(id<PDDImageInput>)newTarget;
- (void)addTarget:(id<PDDImageInput>)newTarget atTextureLocation:(NSInteger)textureLocation;

- (void)removeTarget:(id<PDDImageInput>)targetToRemove;
- (void)removeAllTargets;

- (void)forceProcessingAtSize:(CGSize)frameSize;
- (void)forceProcessingAtSizeRespectingAspectRatio:(CGSize)frameSize;

/// @name Still image processing

- (void)useNextFrameForImageCapture;
- (CGImageRef)newCGImageFromCurrentlyProcessedOutput;
- (CGImageRef)newCGImageByFilteringCGImage:(CGImageRef)imageToFilter;

// Platform-specific image output methods
// If you're trying to use these methods, remember that you need to set -useNextFrameForImageCapture before running -processImage or running video and calling any of these methods, or you will get a nil image
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
- (UIImage *)imageFromCurrentFramebuffer;
- (UIImage *)imageFromCurrentFramebufferWithOrientation:(UIImageOrientation)imageOrientation;
- (UIImage *)imageByFilteringImage:(UIImage *)imageToFilter;
- (CGImageRef)newCGImageByFilteringImage:(UIImage *)imageToFilter;
#else
- (NSImage *)imageFromCurrentFramebuffer;
- (NSImage *)imageFromCurrentFramebufferWithOrientation:(UIImageOrientation)imageOrientation;
- (NSImage *)imageByFilteringImage:(NSImage *)imageToFilter;
- (CGImageRef)newCGImageByFilteringImage:(NSImage *)imageToFilter;
#endif

- (BOOL)providesMonochromeOutput;

@end
