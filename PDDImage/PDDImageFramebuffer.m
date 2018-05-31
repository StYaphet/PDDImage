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
	// renderTarget 与 renderTexture 是用来干嘛的？
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

        // 判断是否支持快速纹理上传（实际上是判断CVOpenGLESTextureCacheCreate是否可用）
//        if ([PDDImageContext supportFastTextureUpload]) {
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
        CVOpenGLESTextureCacheRef coreVideoTextureCache = [[PDDImageContext sharedImageProcessingContext] coreVideoTextureCache];

        // 这里是copy别人的代码，原地址在这：http://allmybrain.com/2011/12/08/rendering-to-a-texture-with-ios-5-texture-cache-api/
        // 这篇文章适用于那些不一定想在屏幕上渲染图像，但想执行一些OpenGL操作，然后再读取图像的人。
        // 首先，要渲染到纹理，您需要一个与OpenGL纹理缓存兼容的图像。 使用相机API创建的图像已经兼容，您可以立即映射它们以进行输入。
        // 假设你想创建一个图像来渲染，然后读出来做一些其他的处理。 您必须创建具有特殊属性的图像。 图像的属性必须具有kCVPixelBufferIOSurfacePropertiesKey作为字典的键之一。
        // 下面这些代码就是创建这样的一个字典
        CFDictionaryRef empty; // empty value for attr values.
        CFMutableDictionaryRef attrs;
        empty = CFDictionaryCreate(kCFAllocatorDefault,
                                   NULL,
                                   NULL,
                                   0,
                                   &kCFTypeDictionaryKeyCallBacks,
                                   &kCFTypeDictionaryValueCallBacks); // our empty IOSurface properties dictionary

        attrs = CFDictionaryCreateMutable(kCFAllocatorDefault,
                                          1,
                                          &kCFTypeDictionaryKeyCallBacks,
                                          &kCFTypeDictionaryValueCallBacks);
        CFDictionarySetValue(attrs, kCVPixelBufferIOSurfacePropertiesKey, empty);

        // 创建一个用于渲染的CVPixelBuffer，创建完成之后就有了一个pixelbuffer，它具有与纹理缓存一起使用的正确属性
        CVReturn err = CVPixelBufferCreate(kCFAllocatorDefault, (int)_size.width, (int)_size.height, kCVPixelFormatType_32RGBA, attrs, &renderTarget);
        if (err) {
            NSLog(@"FBO size: %f, %f", _size.width, _size.height);
            NSAssert(NO, @"Error at CVPixelBufferCreate %d", err);
        }

        // 首先从renderTarget中创建一个纹理
        err = CVOpenGLESTextureCacheCreateTextureFromImage(kCFAllocatorDefault,
                                                           coreVideoTextureCache,
                                                           renderTarget,
                                                           NULL,
                                                           GL_TEXTURE_2D,
                                                           _textureOptions.imternalFormat,
                                                           (int)_size.width,
                                                           (int)_size.height,
                                                           _textureOptions.format,
                                                           _textureOptions.type,
                                                           0,
                                                           &renderTexture);

        if (err) {
            NSAssert(NO, @"Error at CVOpenGLESTextureCacheCreateTextureFromImage %d", err);
        }
        CFRelease(attrs);
        CFRelease(empty);

        // 像设置其他纹理一样去设置该纹理
        glBindTexture(CVOpenGLESTextureGetTarget(renderTexture), CVOpenGLESTextureGetName(renderTexture));
        _texture = CVOpenGLESTextureGetName(renderTexture);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_S, _textureOptions.warpS);
        glTexParameterf(GL_TEXTURE_2D, GL_TEXTURE_WRAP_T, _textureOptions.warpT);

        // 将纹理绑定要你想要渲染的framebuffer
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

- (void)destoryFramebuffer {
	
	runSynchronouslyOnVideoProcessingQueue(^{
		[PDDImageContext useImageProcesssingContext];
		
		if (framebuffer) {
			glDeleteBuffers(1, &framebuffer);
			framebuffer = 0;
		}
		
		if ([GPUImageContext supportFastTextureUpload] && [!_missingFramebuffer]) {
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
			// TODO: @pdd renderTarget是什么？
			if (renderTarget) {
				CFRelease(renderTarget);
				renderTarget = NULL;
			}
			
			if (renderTexture) {
				CFRelease(renderTexture);
				renderTexture = NULL;
			}
#endif
		} else {
			glDeleteTextures(1, &_texture);
		}
	});
}

#pragma mark -
#pragma mark Usage

- (void)activateFramebuffer {
	
	glBindFramebuffer(GL_FRAMEBUFFER, framebuffer);
	glViewport(0, 0, (int)_size.width, (int)_size.height);
}

#pragma mark -
#pragma mark Reference counting

- (void)lock {
	
	if (referenceCountingDisabled) {
		return;
	}
	
	framebufferReferenceCount++;
}

- (void)unlock {
	
	if (referenceCountingDisabled) {
		return;
	}
	
	NSAssert(framebufferReferenceCount, @"Tried to overrelease a framebuffer, did you forget to call -useNextFrameForImageCapture before using -imageFromCurrentFramebuffer?");
	framebufferReferenceCount--;
	if (framebufferReferenceCount < 1) {
		[[PDDImageContext sharedFramebufferCache] returnFramebufferToCache:self];
	}
}

- (void)clearAllLocks;
{
	framebufferReferenceCount = 0;
}

- (void)disableReferenceCounting;
{
	referenceCountingDisabled = YES;
}

- (void)enableReferenceCounting;
{
	referenceCountingDisabled = NO;
}

#pragma mark -
#pragma mark Image capture

void dataProviderReleaseCallback (void *info, const void *data, size_t size) {
	
	free((void *)data);
}

void dataProviderUnlockCallback (void *info, const void *data, size_t size) {
	
	PDDImageFramebuffer *framebuffer = (__bridge_transfer PDDImageFramebuffer*)info;
	
	// TODO: @pdd 这个函数是干嘛用的？
	[framebuffer restoreRenderTarget];
	[framebuffer unlock];
	// TODO: @pdd 还有这个
	[[PDDImageContext sharedFramebufferCache] removeFramebufferFromActiveImageCaptureList:framebuffer];
}


// 通过帧缓存生成图像的时候，GPUImage使用CGImage相关的API生成相关的位图对象。
// CGImageRef这个结构用来创建像素位图，可以通过操作存储的像素位来编辑图片
// typedef struct CGImage *CGImageRef;

/**
 通过CGImageCreate方法，我们可以创建出一个CGImageRef类型的对象
 参数：
  width 图片宽度像素
  height 图片高度像素
  bitsPerComponent 每个颜色的比特数，例如在rgba32模式下为8
  bitsPerPixel 每个像素的总比特数
  bytesPerRow 每一行占用的字节数，注意这里的单位是字节
  space 颜色空间模式
  bitmapInfo 位图像素布局枚举
  provider 数据源提供者
  decode 解码渲染数组
  shouldInterpolate 是否抗锯齿
  intent 图片相关参数
 返回值：
  位图
 
CGImageRef CGImageCreate(size_t width,
						 size_t height,
						 size_t bitsPerComponent,
						 size_t bitsPerPixel,
						 size_t bytesPerRow,
						 CGColorSpaceRef space,
						 CGBitmapInfo bitmapInfo,
						 CGDataProviderRef provider,
						 const CGFloat *decode,
						 bool shouldInterpolate,
						 CGColorRenderingIntent intent)
*/

- (CGImageRef)newCGImageFromFramebufferContents {
	
	// CGImage 只能由 normal 的color texture 中创建
	NSAssert(self.textureOptions.imternalFormat == GL_RGBA, @"For conversion to a CGImage the output texture format for this filter must be GL_RGBA.");
	NSAssert(self.textureOptions.type == GL_UNSIGNED_BYTE, @"For conversion to a CGImage the type of the output texture of this filter must be GL_UNSIGNED_BYTE.");
	
	__block CGImageRef cgImageFromBytes;
	
	runSynchronouslyOnVideoProcessingQueue(^{
		// 设置OpenGLES上下文
		[PDDImageContext useImageProcessingContext];
		
		// 如果使用纹理缓存读取纹理，纹理的宽度必须被填充为8(32字节)的倍数。
		// 图片的总大小 = 帧缓存大小 * 每个像素点字节数
		NSUInteger totalBytesForImage = (int)_size.width * (int)_size.height * 4;
		
		GLubyte *rawImagePixels;
		
		CGDataProviderRef dataProvider = NULL;
		
		// 在读取图片数据的时候，根据设备是否支持 CoreVideo 框架，会选择使用 CVPixelBufferGetBaseAddress 或者 glReadPixels 读取帧缓存中的数据。
		if ([PDDImageContext supportsFastTextureUpload]) {
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
			//图像宽度(字节数) = 每行图像数据大小 / 每个像素点字节数
			NSUInteger paddedWidthOfImage = CVPixelBufferGetBytesPerRow(renderTarget) / 4.0;
			// 图像大小 = 图像宽度 * 高度 * 每个像素点字节数
			// TODO: pdd 这个为什么不从renderTarget中去取呢？
			NSUInteger paddedBytesFromImage = paddedWidthOfImage * (int)_size.height * 4;
			
			// 等待OpenGL指令执行完成，与glFlush有区别
			glFinish();
			CFRetain(renderTarget); // I need to retain the pixel buffer here and release in the data source callback to prevent its bytes from being prematurely deallocated during a photo write operation
			rawImagePixels = (GLubyte *)CVPixelBufferGetBaseAddress(renderTarget);
			// 创建CGDataProviderRef对象
			dataProvider = CGDataProviderCreateWithData((__bridge_retained void*)self,
														rawImagePixels,
														paddedBytesFromImage,
														dataProviderUnlockCallback);
			[[PDDImageContext sharedFramebufferCache] addFramebufferToActiveImageCaptureList:self]; // In case the framebuffer is swapped out on the filter, need to have a strong reference to it somewhere for it to hang on while the image is in existence
		} else {
			[self activateFramebuffer];
			rawImagePixels = (GLubyte *)malloc(totalBytesForImage);
			glReadPixels(0, 0, (int)_size.width, (int)_size.height, GL_RGBA, GL_UNSIGNED_BYTE, rawImagePixels);
			dataProvider = CGDataProviderCreateWithData(NULL, rawImagePixels, totalBytesForImage, dataProviderReleaseCallback);
			[self unlock]; // Don't need to keep this around anymore
		}
		
		CGColorSpaceRef defaultRGBColorSpace = CGColorSpaceCreateDeviceRGB();
		if ([PDDImageContext supportsFastTextureUpload]) {
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
			cgImageFromBytes = CGImageCreate((int)_size.width,
											 (int)_size.height,
											 8,
											 32,
											 CVPixelBufferGetBytesPerRow(renderTarget),
											 defaultRGBColorSpace,
											 kCGBitmapByteOrder32Little | kCGImageAlphaPremultipliedFirst,
											 dataProvider,
											 NULL,
											 NO,
											 kCGRenderingIntentDefault);
#else
#endif
		} else {
			cgImageFromBytes = CGImageCreate((int)_size.width, (int)_size.height, 8, 32, 4 * (int)_size.width, defaultRGBColorSpace, kCGBitmapByteOrderDefault | kCGImageAlphaLast, dataProvider, NULL, NO, kCGRenderingIntentDefault);
		}
		
		CGDataProviderRelease(dataProvider);
		CGColorSpaceRelease(defaultRGBColorSpace);
	});
	
	return cgImageFromBytes;
}

- (void)restoreRenderTarget {
	
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
	[self unlockAfterReading];
	CFRelease(renderTarget);
#else
#endif
}

- (void)lockForReading {
	
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
	if ([PDDImageContext supportsFastTextureUpload])
	{
		if (readLockCount == 0)
		{
			// TODO: @pdd 与下边配对使用的函数
			CVPixelBufferLockBaseAddress(renderTarget, 0);
		}
		readLockCount++;
	}
#endif
}

- (void)unlockAfterReading {
	
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
	if ([PDDImageContext supportsFastTextureUpload])
	{
		NSAssert(readLockCount > 0, @"Unbalanced call to -[GPUImageFramebuffer unlockAfterReading]");
		readLockCount--;
		if (readLockCount == 0)
		{
			// TODO: @pdd 与上边配对使用的函数
			CVPixelBufferUnlockBaseAddress(renderTarget, 0);
		}
	}
#endif
}

- (NSUInteger)bytesPerRow {
	
	if ([PDDImageContext supportsFastTextureUpload])
	{
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
		return CVPixelBufferGetBytesPerRow(renderTarget);
#else
		return _size.width * 4; // TODO: do more with this on the non-texture-cache side
#endif
	}
	else
	{
		return _size.width * 4;
	}
}

- (GLubyte *)byteBuffer {
	
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
	[self lockForReading];
	GLubyte * bufferBytes = CVPixelBufferGetBaseAddress(renderTarget);
	[self unlockAfterReading];
	return bufferBytes;
#else
	return NULL; // TODO: do more with this on the non-texture-cache side
#endif
}

- (CVPixelBufferRef )pixelBuffer {
#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
	return renderTarget;
#else
	return NULL; // TODO: do more with this on the non-texture-cache side
#endif
}

- (GLuint)texture {
	//    NSLog(@"Accessing texture: %d from FB: %@", _texture, self);
	return _texture;
}

@end
