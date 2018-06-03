//
//  PDDImageFramebufferCache.m
//  PDDImage
//
//  Created by 郝一鹏 on 2018/5/31.
//  Copyright © 2018年 郝一鹏. All rights reserved.
//

#import "PDDImageFramebufferCache.h"
#import "PDDImageContext.h"

#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#endif

@interface PDDImageFramebufferCache () {
    // 为什么不用这个做缓存呢？
    // NSCache *framebufferCache;
    NSMutableDictionary *framebufferCache;
    NSMutableDictionary *framebufferTypeCounts;
    NSMutableArray *activeImageCaptureList; // Where framebuffers that may be lost by a filter, but which are still needed for a UIImage, etc., are stored
    id memoryWarningObserver;

    dispatch_queue_t framebufferCacheQueue;
}

- (NSString *)hashForSize:(CGSize)size textureOptions:(GPUTextureOptions)textureOptions onlyTexture:(BOOL)onlyTexture;

@end

@implementation PDDImageFramebufferCache

#pragma mark -
#pragma mark Initialization and teardown

- (id)init {

    if (!(self = [super init])) {
        return nil;
    }

#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
    __unsafe_unretained __typeof__ (self)weakSelf = self;
    memoryWarningObserver = [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidReceiveMemoryWarningNotification object:nil queue:nil usingBlock:^(NSNotification * _Nonnull note) {
        __typeof__ (self) strongSelf = weakSelf;
        if (strongSelf) {
            [strongSelf purgeAllUnassignedFramebuffers];
        }
    }];
#else
#endif

    // TODO: @pdd 为什么不用NSCache做缓存呢？
    //    framebufferCache = [[NSCache alloc] init];
    framebufferCache = [[NSMutableDictionary alloc] init];
    framebufferTypeCounts = [[NSMutableDictionary alloc] init];
    activeImageCaptureList = [[NSMutableArray alloc] init];
    framebufferCacheQueue = dispatch_queue_create("com.bytedance.pddImage.framebufferCacheQueue", GPUImageDefaultQueueAttribute());
    return self;
}

- (void)dealloc {
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
    [[NSNotificationCenter defaultCenter] removeObserver:self];
#else
#endif
}

#pragma mark -
#pragma mark Framebuffer management

// 一种hash算法
- (NSString *)hashForSize:(CGSize)size textureOptions:(GPUTextureOptions)textureOptions onlyTexture:(BOOL)onlyTexture {

    if (onlyTexture) {
        return [NSString stringWithFormat:@"%.1fx%.1f-%d:%d:%d:%d:%d:%d:%d-NOFB", size.width, size.height, textureOptions.minFilter, textureOptions.magFilter, textureOptions.warpS, textureOptions.warpT, textureOptions.internalFormat, textureOptions.format, textureOptions.type];
    } else {
        return [NSString stringWithFormat:@"%.1fx%.1f-%d:%d:%d:%d:%d:%d:%d", size.width, size.height, textureOptions.minFilter, textureOptions.magFilter, textureOptions.warpT, textureOptions.warpT, textureOptions.internalFormat, textureOptions.format, textureOptions.type];
    }
}

- (PDDImageFramebuffer *)fetchFramebufferForSize:(CGSize)framebufferSize textureOptions:(GPUTextureOptions)textureOptions onlyTexture:(BOOL)onlyTexture {
    __block PDDImageFramebuffer *framebufferFromCache = nil;
    runSynchronouslyOnVideoProcessingQueue(^{
        NSString *lookupHash = [self hashForSize:framebufferSize textureOptions:textureOptions onlyTexture:onlyTexture];
        NSNumber *numberOfMatchingTexturesInCache = [framebufferTypeCounts objectForKey:lookupHash];
        NSInteger numberOfMatchingTextures = [numberOfMatchingTexturesInCache integerValue];

        if (numberOfMatchingTextures < 1) {
            // 没有缓存，创建一个新的framebuffer
            framebufferFromCache = [[PDDImageFramebuffer alloc] initWithSize:framebufferSize textureOptions:textureOptions onlyTexture:onlyTexture];
        } else {

            NSInteger currentTextureID = (numberOfMatchingTextures - 1);
            while ((framebufferFromCache == nil) && (currentTextureID >= 0)) {
                NSString *textureHash = [NSString stringWithFormat:@"%@-%ld", lookupHash, (long)currentTextureID];
                framebufferFromCache = [framebufferCache objectForKey:textureHash];
                // Test the values in the cache first, to see if they got invalidated behind our back
                // 防止多线程出现的问题
                if (framebufferFromCache != nil) {
                    [framebufferCache removeObjectForKey:textureHash];
                }
                currentTextureID--;
            }

            // 这里加一的原因是因为要设置给framebufferTypeCounts的值应该是count，而现在currentTextureID是Index，所以要将currentTextureID+1；
            currentTextureID++;
            [framebufferTypeCounts setObject:[NSNumber numberWithInteger:currentTextureID] forKey:lookupHash];

            if (framebufferFromCache == nil) {
                framebufferFromCache = [[PDDImageFramebuffer alloc] initWithSize:framebufferSize textureOptions:textureOptions onlyTexture:onlyTexture];
            }
        }
    });
    [framebufferFromCache lock];
    return framebufferFromCache;
}

- (PDDImageFramebuffer *)fetchFramebufferForSize:(CGSize)framebufferSize onlyTexture:(BOOL)onlyTexture {

    GPUTextureOptions defaultTextureOptions;
    defaultTextureOptions.minFilter = GL_LINEAR;
    defaultTextureOptions.magFilter = GL_LINEAR;
    defaultTextureOptions.warpS = GL_CLAMP_TO_EDGE;
    defaultTextureOptions.warpT = GL_CLAMP_TO_EDGE;
    defaultTextureOptions.internalFormat = GL_RGBA;
    defaultTextureOptions.format = GL_BGRA;
    defaultTextureOptions.type = GL_UNSIGNED_BYTE;

    return [self fetchFramebufferForSize:framebufferSize textureOptions:defaultTextureOptions onlyTexture:onlyTexture];
}

- (void)retureFrambufferToCache:(PDDImageFramebuffer *)framebuffer {

    [framebuffer clearAllLocks];
    runSynchronouslyOnVideoProcessingQueue(^{
        CGSize framebufferSize = framebuffer.size;
        GPUTextureOptions framebufferTextureOptions = framebuffer.textureOptions;
        NSString *lookupHash = [self hashForSize:framebufferSize textureOptions:framebufferTextureOptions onlyTexture:framebuffer.missingFramebuffer];
        NSNumber *numberOfMatchingTexturesInCache = [framebufferTypeCounts objectForKey:lookupHash];
        NSInteger numberOfMatchingTextures = [numberOfMatchingTexturesInCache integerValue];

        NSString *textureHash = [NSString stringWithFormat:@"%@-%ld", lookupHash, (long)numberOfMatchingTextures];
        [framebufferCache setObject:framebuffer forKey:textureHash];
        [framebufferTypeCounts setObject:[NSNumber numberWithInteger:(numberOfMatchingTextures + 1)] forKey:lookupHash];
    });
}

- (void)purgeAllUnassignedFramebuffers
{
    runSynchronouslyOnVideoProcessingQueue(^{
        [framebufferCache removeAllObjects];
        [framebufferTypeCounts removeAllObjects];
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
        CVOpenGLESTextureCacheFlush([[PDDImageContext sharedImageProcessingContext] coreVideoTextureCache], 0);
#else
#endif
    });
}

- (void)addFramebufferToActiveImageCaptureList:(PDDImageFramebuffer *)framebuffer {

    runSynchronouslyOnVideoProcessingQueue(^{
        [activeImageCaptureList addObject:framebuffer];
    });
}

- (void)removeFrambufferFromActiveImageCaptureList:(PDDImageFramebuffer *)framebuffer {

    runSynchronouslyOnVideoProcessingQueue(^{
        [activeImageCaptureList removeObject:framebuffer];
    });
}

@end
