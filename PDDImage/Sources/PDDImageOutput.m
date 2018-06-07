//
//  PDDImageOutput.m
//  PDDImage
//
//  Created by 郝一鹏 on 2018/6/3.
//  Copyright © 2018年 郝一鹏. All rights reserved.
//

#import "PDDImageOutput.h"
#import "PDDImageContext.h"
#import <mach/mach.h>
#import "PDDImagePicture.h"

dispatch_queue_attr_t GPUImageDefaultQueueAttribute(void) {
	
#if TARGET_OS_IPHONE
	if ([[[UIDevice currentDevice] systemVersion] compare:@"9.0" options:NSNumericSearch] != NSOrderedAscending) {
		return dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_DEFAULT, 0);
	}
#endif
	return nil;
}

void runOnMainQueueWithoutDeadlocking(void(^block)(void)) {
	if ([NSThread isMainThread]) {
		block();
	} else {
		dispatch_sync(dispatch_get_main_queue(), block);
	}
}

void runSynchronouslyOnVideoProcessingQueue(void (^block)(void)) {
	dispatch_queue_t videoProcessingQueue = [PDDImageContext sharedContextQueue];
#if !OS_OBJECT_USE_OBJC
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	if (dispatch_get_current_queue() == videoProcessingQueue)
#pragma clang diagnostic pop
#else
		// + (void *)contextKey {
		//		return openGLESContextQueueKey;
		//	}
		
		// #if OS_OBJECT_USE_OBJC
		//		dispatch_queue_set_specific(_contextQueue, openGLESContextQueueKey, (__bridge void*)self, NULL);
		// 在 PDDImageContext 里是这么写的，所以 contextKey 对应的就是那个contextQueue
	if (dispatch_get_specific([PDDImageContext contextKey]))
#endif
	{
		block();
	} else {
		dispatch_sync(videoProcessingQueue, block);
	}

}
	
void runAsynchronouslyOnVideoProcessingQueue(void (^block)(void)) {
	dispatch_queue_t videoProcessingQueue = [PDDImageContext sharedContextQueue];
#if !OS_OBJECT_USE_OBJC
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	if (dispatch_get_current_queue() == videoProcessingQueue)
#pragma clang diagnostic pop
#else
		// + (void *)contextKey {
		//		return openGLESContextQueueKey;
		//	}
		
		// #if OS_OBJECT_USE_OBJC
		//		dispatch_queue_set_specific(_contextQueue, openGLESContextQueueKey, (__bridge void*)self, NULL);
		// 在 PDDImageContext 里是这么写的，所以 contextKey 对应的就是那个contextQueue
	if (dispatch_get_specific([PDDImageContext contextKey]))
#endif
	{
		block();
	} else {
		dispatch_async(videoProcessingQueue, block);
	}
}
	
void runSynchronouslyOnContextQueue(PDDImageContext *context, void (^block)(void))
{
	dispatch_queue_t videoProcessingQueue = [context contextQueue];
#if !OS_OBJECT_USE_OBJC
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	if (dispatch_get_current_queue() == videoProcessingQueue)
#pragma clang diagnostic pop
#else
	if (dispatch_get_specific([PDDImageContext contextKey]))
#endif
	{
		block();
	}else
	{
		dispatch_sync(videoProcessingQueue, block);
	}
}
	
void runAsynchronouslyOnContextQueue(PDDImageContext *context, void (^block)(void))
{
	dispatch_queue_t videoProcessingQueue = [context contextQueue];
#if !OS_OBJECT_USE_OBJC
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	if (dispatch_get_current_queue() == videoProcessingQueue)
#pragma clang diagnostic pop
#else
	if (dispatch_get_specific([PDDImageContext contextKey]))
#endif
	{
		block();
	}else
	{
		dispatch_async(videoProcessingQueue, block);
	}
}
	
void reportAvailableMemoryForPDDImage(NSString *tag)
{
	if (!tag)
		tag = @"Default";
	
	struct task_basic_info info;
	
	mach_msg_type_number_t size = sizeof(info);
	
	kern_return_t kerr = task_info(mach_task_self(),
								   
								   TASK_BASIC_INFO,
								   
								   (task_info_t)&info,
								   
								   &size);
	if( kerr == KERN_SUCCESS ) {
		NSLog(@"%@ - Memory used: %u", tag, (unsigned int)info.resident_size); //in bytes
	} else {
		NSLog(@"%@ - Error: %s", tag, mach_error_string(kerr));
	}
}

@implementation PDDImageOutput

@synthesize shouldSmoothlyScaleOutput = _shouldSmoothlyScaleOutput;
@synthesize shouldIgnoreUpdatesToThisTarget = _shouldIgnoreUpdatesToThisTarget;
@synthesize audioEncodingTarget = _audioEncodingTarget;
@synthesize targetToIgnoreForUpdates = _targetToIgnoreForUpdates;
@synthesize frameProcessingCompletionBlock = _frameProcessingCompletionBlock;
@synthesize enabled = _enabled;
@synthesize outputTextureOptions = _outputTextureOptions;

#pragma mark -
#pragma mark Initialization and teardown

- (instancetype)init {
	
	if (!(self = [super init])) {
		return nil;
	}
	
	_targets = [[NSMutableArray alloc] init];
	_targetTextureIndices = [[NSMutableArray alloc] init];
	_enabled = YES;
	_allTargetsWantMonocharomeData = YES;
	_usingNextFrameForImageCapture = NO;
	
	// set default texture options
	_outputTextureOptions.minFilter = GL_LINEAR;
	_outputTextureOptions.magFilter = GL_LINEAR;
	_outputTextureOptions.warpS = GL_CLAMP_TO_EDGE;
	_outputTextureOptions.warpT = GL_CLAMP_TO_EDGE;
	_outputTextureOptions.internalFormat = GL_RGBA;
	_outputTextureOptions.format = GL_BGRA;
	_outputTextureOptions.type = GL_UNSIGNED_BYTE;

	return self;
}

- (void)dealloc
{
	[self removeAllTargets];
}

#pragma mark -
#pragma mark Managing targets

- (void)setInputFramebufferForTarget:(id<PDDImageInput>)target atIndex:(NSInteger)inputTextureIndex {
	
	[target setInputFramebuffer:[self framebufferForOutput] atIndex:inputTextureIndex];
}

- (PDDImageFramebuffer *)framebufferForOutput;
{
	return _outputFramebuffer;
}

- (void)removeOutputFramebuffer;
{
	_outputFramebuffer = nil;
}

- (void)notifyTargetsAboutNewOutputTexture;
{
	for (id<PDDImageInput> currentTarget in _targets)
	{
		NSInteger indexOfObject = [_targets indexOfObject:currentTarget];
		NSInteger textureIndex = [[_targetTextureIndices objectAtIndex:indexOfObject] integerValue];
		
		[self setInputFramebufferForTarget:currentTarget atIndex:textureIndex];
	}
}

- (NSArray*)targets;
{
	return [NSArray arrayWithArray:_targets];
}

- (void)addTarget:(id<PDDImageInput>)newTarget;
{
	NSInteger nextAvailableTextureIndex = [newTarget nextAvailableTextureIndex];
	[self addTarget:newTarget atTextureLocation:nextAvailableTextureIndex];
	
	if ([newTarget shouldIgnoreUpdatesToThisTarget])
	{
		_targetToIgnoreForUpdates = newTarget;
	}
}

- (void)addTarget:(id<PDDImageInput>)newTarget atTextureLocation:(NSInteger)textureLocation;
{
	if([_targets containsObject:newTarget])
	{
		return;
	}
	
	_cachedMaximumOutputSize = CGSizeZero;
	runSynchronouslyOnVideoProcessingQueue(^{
		[self setInputFramebufferForTarget:newTarget atIndex:textureLocation];
		[_targets addObject:newTarget];
		[_targetTextureIndices addObject:[NSNumber numberWithInteger:textureLocation]];
		
		_allTargetsWantMonochromeData = _allTargetsWantMonochromeData && [newTarget wantsMonochromeInput];
	});
}

- (void)removeTarget:(id<PDDImageInput>)targetToRemove;
{
	if(![_targets containsObject:targetToRemove])
	{
		return;
	}
	
	if (_targetToIgnoreForUpdates == targetToRemove)
	{
		_targetToIgnoreForUpdates = nil;
	}
	
	_cachedMaximumOutputSize = CGSizeZero;
	
	NSInteger indexOfObject = [_targets indexOfObject:targetToRemove];
	NSInteger textureIndexOfTarget = [[_targetTextureIndices objectAtIndex:indexOfObject] integerValue];
	
	runSynchronouslyOnVideoProcessingQueue(^{
		[targetToRemove setInputSize:CGSizeZero atIndex:textureIndexOfTarget];
		[targetToRemove setInputRotation:kPDDImageNoRotation atIndex:textureIndexOfTarget];
		
		[_targetTextureIndices removeObjectAtIndex:indexOfObject];
		[_targets removeObject:targetToRemove];
		[targetToRemove endProcessing];
	});
}

- (void)removeAllTargets;
{
	_cachedMaximumOutputSize = CGSizeZero;
	runSynchronouslyOnVideoProcessingQueue(^{
		for (id<PDDImageInput> targetToRemove in _targets)
		{
			NSInteger indexOfObject = [_targets indexOfObject:targetToRemove];
			NSInteger textureIndexOfTarget = [[_targetTextureIndices objectAtIndex:indexOfObject] integerValue];
			
			[targetToRemove setInputSize:CGSizeZero atIndex:textureIndexOfTarget];
			[targetToRemove setInputRotation:kPDDImageNoRotation atIndex:textureIndexOfTarget];
		}
		[_targets removeAllObjects];
		[_targetTextureIndices removeAllObjects];
		
		_allTargetsWantMonocharomeData = YES;
	});
}

#pragma mark -
#pragma mark Manage the output texture

- (void)forceProcessingAtSize:(CGSize)frameSize
{
	
}

- (void)forceProcessingAtSizeRespectingAspectRatio:(CGSize)frameSize
{
}

#pragma mark -
#pragma mark Still image processing

- (void)useNextFrameForImageCapture
{
	
}

- (CGImageRef)newCGImageFromCurrentlyProcessedOutput
{
	return nil;
}

- (CGImageRef)newCGImageByFilteringCGImage:(CGImageRef)imageToFilter;
{
	GPUImagePicture *stillImageSource = [[GPUImagePicture alloc] initWithCGImage:imageToFilter];
	
	[self useNextFrameForImageCapture];
	[stillImageSource addTarget:(id<GPUImageInput>)self];
	[stillImageSource processImage];
	
	CGImageRef processedImage = [self newCGImageFromCurrentlyProcessedOutput];
	
	[stillImageSource removeTarget:(id<GPUImageInput>)self];
	return processedImage;
}

- (BOOL)providesMonochromeOutput;
{
	return NO;
}

#pragma mark -
#pragma mark Platform-specific image output methods

#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE

- (UIImage *)imageFromCurrentFramebuffer;
{
	UIDeviceOrientation deviceOrientation = [[UIDevice currentDevice] orientation];
	UIImageOrientation imageOrientation = UIImageOrientationLeft;
	switch (deviceOrientation)
	{
		case UIDeviceOrientationPortrait:
			imageOrientation = UIImageOrientationUp;
			break;
		case UIDeviceOrientationPortraitUpsideDown:
			imageOrientation = UIImageOrientationDown;
			break;
		case UIDeviceOrientationLandscapeLeft:
			imageOrientation = UIImageOrientationLeft;
			break;
		case UIDeviceOrientationLandscapeRight:
			imageOrientation = UIImageOrientationRight;
			break;
		default:
			imageOrientation = UIImageOrientationUp;
			break;
	}
	
	return [self imageFromCurrentFramebufferWithOrientation:imageOrientation];
}

- (UIImage *)imageFromCurrentFramebufferWithOrientation:(UIImageOrientation)imageOrientation;
{
	CGImageRef cgImageFromBytes = [self newCGImageFromCurrentlyProcessedOutput];
	UIImage *finalImage = [UIImage imageWithCGImage:cgImageFromBytes scale:1.0 orientation:imageOrientation];
	CGImageRelease(cgImageFromBytes);
	
	return finalImage;
}

- (UIImage *)imageByFilteringImage:(UIImage *)imageToFilter;
{
	CGImageRef image = [self newCGImageByFilteringCGImage:[imageToFilter CGImage]];
	UIImage *processedImage = [UIImage imageWithCGImage:image scale:[imageToFilter scale] orientation:[imageToFilter imageOrientation]];
	CGImageRelease(image);
	return processedImage;
}

- (CGImageRef)newCGImageByFilteringImage:(UIImage *)imageToFilter
{
	return [self newCGImageByFilteringCGImage:[imageToFilter CGImage]];
}

#else

- (NSImage *)imageFromCurrentFramebuffer;
{
	return [self imageFromCurrentFramebufferWithOrientation:UIImageOrientationLeft];
}

- (NSImage *)imageFromCurrentFramebufferWithOrientation:(UIImageOrientation)imageOrientation;
{
	CGImageRef cgImageFromBytes = [self newCGImageFromCurrentlyProcessedOutput];
	NSImage *finalImage = [[NSImage alloc] initWithCGImage:cgImageFromBytes size:NSZeroSize];
	CGImageRelease(cgImageFromBytes);
	
	return finalImage;
}

- (NSImage *)imageByFilteringImage:(NSImage *)imageToFilter;
{
	CGImageRef image = [self newCGImageByFilteringCGImage:[imageToFilter CGImageForProposedRect:NULL context:[NSGraphicsContext currentContext] hints:nil]];
	NSImage *processedImage = [[NSImage alloc] initWithCGImage:image size:NSZeroSize];
	CGImageRelease(image);
	return processedImage;
}

- (CGImageRef)newCGImageByFilteringImage:(NSImage *)imageToFilter
{
	return [self newCGImageByFilteringCGImage:[imageToFilter CGImageForProposedRect:NULL context:[NSGraphicsContext currentContext] hints:nil]];
}

#endif

#pragma mark -
#pragma mark Accessors

- (void)setAudioEncodingTarget:(PDDImageMovieWriter *)newValue;
{
	_audioEncodingTarget = newValue;
	if( !_audioEncodingTarget.hasAudioTrack )
	{
		_audioEncodingTarget.hasAudioTrack = YES;
	}
}

-(void)setOutputTextureOptions:(GPUTextureOptions)outputTextureOptions
{
	_outputTextureOptions = outputTextureOptions;
	
	if( outputFramebuffer.texture )
	{
		glBindTexture(GL_TEXTURE_2D,  outputFramebuffer.texture);
		//_outputTextureOptions.format
		//_outputTextureOptions.internalFormat
		//_outputTextureOptions.magFilter
		//_outputTextureOptions.minFilter
		//_outputTextureOptions.type
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, _outputTextureOptions.wrapS);
		glTexParameteri(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, _outputTextureOptions.wrapT);
		glBindTexture(GL_TEXTURE_2D, 0);
	}
}

@end


