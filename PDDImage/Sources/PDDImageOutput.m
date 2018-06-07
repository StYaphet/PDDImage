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
		block;
	} else {
		dispatch_sync(dispatch_get_main_queue(), block);
	}
}

void runSynchronouslyOnVideoProcessingQueue(void (^block)(void)) {
	dispatch_queue_t videoProcessingQueue = [PDDImageContext sharedContextQueue];
#if !OS_OBJECT_USE_OBJC
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
	if (dispatch_get_current_queue() == videoProcessingQueue) {
#pragma clang diagnostic pop
#else
		// + (void *)contextKey {
		//		return openGLESContextQueueKey;
		//	}
		
		// #if OS_OBJECT_USE_OBJC
		//		dispatch_queue_set_specific(_contextQueue, openGLESContextQueueKey, (__bridge void*)self, NULL);
		// 在 PDDImageContext 里是这么写的，所以 contextKey 对应的就是那个contextQueue
	if (dispatch_get_specific([PDDImageContext contextKey])) {
#endif
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
	if (dispatch_get_current_queue() == videoProcessingQueue) {
#pragma clang diagnostic pop
#else
		// + (void *)contextKey {
		//		return openGLESContextQueueKey;
		//	}
		
		// #if OS_OBJECT_USE_OBJC
		//		dispatch_queue_set_specific(_contextQueue, openGLESContextQueueKey, (__bridge void*)self, NULL);
		// 在 PDDImageContext 里是这么写的，所以 contextKey 对应的就是那个contextQueue
	if (dispatch_get_specific([PDDImageContext contextKey])) {
#endif
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

@end
