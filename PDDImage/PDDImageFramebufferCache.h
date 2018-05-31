//
//  PDDImageFramebufferCache.h
//  PDDImage
//
//  Created by 郝一鹏 on 2018/5/31.
//  Copyright © 2018年 郝一鹏. All rights reserved.
//

#import <Foundation/Foundation.h>
#import <QuartzCore/QuartzCore.h>
#import "PDDImageFramebuffer.h"

@interface PDDImageFramebufferCache : NSObject

// Framebuffer management
- (PDDImageFramebuffer *)fetchFramebufferForSize:(CGSize)framebufferSize textureOptions:(GPUTextureOptions)textureOptions onlyTexture:(BOOL)onlyTexture;
- (PDDImageFramebuffer *)fetchFramebufferForSize:(CGSize)framebufferSize onlyTexture:(BOOL)onlyTexture;
- (void)retureFrambufferToCache:(PDDImageFramebuffer *)framebuffer;
- (void)purgeAllUnassignedFramebuffers;
- (void)addFramebufferToActiveImageCaptureList:(PDDImageFramebuffer *)framebuffer;
- (void)removeFrambufferFromActiveImageCaptureList:(PDDImageFramebuffer *)framebuffer;

@end
