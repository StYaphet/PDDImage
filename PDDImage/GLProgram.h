//
//  GLProgram.h
//  PDDImage
//
//  Created by 郝一鹏 on 2018/5/29.
//  Copyright © 2018年 郝一鹏. All rights reserved.
//

#import <Foundation/Foundation.h>

#if TARGET_IPHONE_SIMULATOR || TARGET_OS_IPHONE
#import <OpenGLES/ES2/gl.h>
#import <OpenGLES/ES2/glext.h>
#else
#import <OpenGL/OpenGL.h>
#import <OpenGL/gl.h>
#endif

@interface GLProgram : NSObject
{
	NSMutableArray *attributes;
	NSMutableArray *uniformsl;
	GLuint program,
	vertShader,
	fragShader;
}

@property (readwrite, nonatomic) BOOL initialized;
@property (readwrite, copy, nonatomic) NSString *vertexShaderLog;
@property (readwrite, copy, nonatomic) NSString *fragmentShaderLog;
@property (readwrite, copy, nonatomic) NSString *programLog;

- (id)initWithVertexShaderString:(NSString *)vShaderString fragmentShaderString:(NSString *)fShaderString;
- (id)initWithVertexShaderString:(NSString *)vShaderString fragmentShaderFilename:(NSString *)fShaderFilename;
- (id)initWithVertexShaderFilename:(NSString *)vShaderString fragmentShaderFilename:(NSString *)fShaderFileName;

- (void)addAttribute:(NSString *)attributeName;
- (GLuint)attributeIndex:(NSString *)attributeName;
- (GLuint)uniformIndex:(NSString *)uniformName;
- (BOOL)link;
- (void)use;
- (void)validate;

@end
