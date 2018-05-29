//
//  GLProgram.m
//  PDDImage
//
//  Created by 郝一鹏 on 2018/5/29.
//  Copyright © 2018年 郝一鹏. All rights reserved.
//

#import "GLProgram.h"
// START: typedefs
#pragma mark Function Pointer Definitions
typedef void(^GLInfoFunction)(GLuint program, GLenum pname, GLint *params);
typedef void(^GLLogFunction)(GLuint program, GLsizei bufsize, GLsizei length, GLchar *infolog);
// END: typedefs
#pragma mark -
#pragma mark Private Extention Method Declaration
// START: extension
@interface GLProgram ()
- (BOOL)compileShader:(GLuint *)shader
				 type:(GLenum)type
			   string:(NSString *)shaderString;
@end
// END: extension

@implementation GLProgram
// START: init

@synthesize initialized = _initialized;

- (id)initWithVertexShaderString:(NSString *)vShaderString fragmentShaderString:(NSString *)fShaderString {
	
	if (self = [super init]) {
		
		_initialized = NO;
		attributes = [NSMutableArray array];
		uniform = [NSMutableArray array];
		program = glCreateProgram();
		
		if (![self compileShader:&vertShader type:GL_VERTEX_SHADER string:vShaderString]) {
			NSLog(@"Failed to compile vertex shader");
		}
		
		if (![self compileShader:&fragShader type:GL_FRAGMENT_SHADER string:fShaderString]) {
			NSLog(@"Failed to compile fragment shader");
		}
		
		glAttachShader(program, vertShader);
		glAttachShader(program, fragShader);
	}
	return self;
}

- (id)initWithVertexShaderString:(NSString *)vShaderString fragmentShaderFilename:(NSString *)fShaderFilename {
	
	NSString *fragShaderPathname = [[NSBundle mainBundle] pathForResource:fShaderFilename ofType:@"fsh"];
	NSString *fragmentShaderString = [NSString stringWithContentsOfFile:fragShaderPathname encoding:NSUTF8StringEncoding error:nil];
	
	if ((self = [self initWithVertexShaderString:vShaderString fragmentShaderString:fragmentShaderString])) {
		
	}
	return self;
}

- (id)initWithVertexShaderFilename:(NSString *)vShaderFilename fragmentShaderFilename:(NSString *)fShaderFilename {
	
	NSString *vertShaderPathname = [[NSBundle mainBundle] pathForResource:vShaderFilename ofType:@"vsh"];
	NSString *vertextShaderString = [NSString stringWithContentsOfFile:vertShaderPathname encoding:NSUTF8StringEncoding error:nil];
	
	NSString *fragShaderPathname = [[NSBundle mainBundle] pathForResource:fShaderFilename ofType:@"fsh"];
	NSString *fragmentShaderString = [NSString stringWithContentsOfFile:fragShaderPathname encoding:NSUTF8StringEncoding error:nil];
	
	if ((self = [self initWithVertexShaderString:vertextShaderString fragmentShaderString:fragmentShaderString])) {
		
	}
	return self;
}

- (BOOL)compileShader:(GLuint *)shader type:(GLenum)type string:(NSString *)shaderString {
	
	// TODO: @pdd 这个是干什么用的呢？
	// CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
	
	GLint status;
	const GLchar *source;
	
	source = (GLchar *)[shaderString UTF8String];
	if (!source) {
		// TODO: @pdd 这里应该也有 Failed to load fragment shader 吧？
		NSLog(@"Failed to load vertex shader");
		return NO;
	}
	
	*shader = glCreateShader(type);
	glShaderSource(*shader, 1, &source, NULL);
	glCompileShader(*shader);
	
	// TODO: @pdd 这个函数是干什么用的呢？看起来好像是获取shader的compile状态，因为传进去的是 GL_COMPILE_STATUS
	glGetShaderiv(*shader, GL_COMPILE_STATUS, &status);
	if (status != GL_TRUE) {
		
		GLint logLength;
		// TODO: @pdd 看起来好像是获取shader的compile状态，因为传进去的是 GL_INFO_LOG_LENGTH
		glGetShaderiv(*shader, GL_INFO_LOG_LENGTH, &logLength);
		
		if (logLength > 0) {
			
			GLchar *log = (GLchar *)malloc(logLength);
			glGetShaderInfoLog(*shader, logLength, &logLength, log);
			
			if (shader == &vertShader) {
				
				self.vertexShaderLog = [NSString stringWithFormat:@"%s", log];
			} else {
				
				self.fragmentShaderLog = [NSString stringWithFormat:@"%s", log];
			}
			free(log);
		}
	}
	return status == GL_TRUE;
}

- (void)addAttribute:(NSString *)attributeName {
	
	if (![attributes containsObject:attributeName]) {
		
		[attributes addObject:attributeName];
		glBindAttribLocation(program, (GLuint)[attributes indexOfObject:attributeName], [attributeName UTF8String]);
	}
}

- (GLuint)attributeIndex:(NSString *)attributeName {
	
	return (GLuint)[attributes indexOfObject:attributeName];
}

- (GLuint)uniformIndex:(NSString *)uniformName {
	
	return glGetUniformLocation(program, [uniformName UTF8String]);
}

#pragma mark -

- (BOOL)link {
	
	// CFAbsoluteTime startTime = CFAbsoluteTimeGetCurrent();
	GLint status;
	
	glLinkProgram(program);
	
	glGetProgramiv(program, GL_LINK_STATUS, &status);
	
	if (status == GL_FALSE) {
		return NO;
	}
	
	if (vertShader) {
		glDeleteShader(vertShader);
		vertShader = 0;
	}
	if (fragShader) {
		glDeleteShader(fragShader);
		fragShader = 0;
	}
	
	self.initialized = YES;
	
	// CFAbsoluteTime lineTime = (CFAbsoluteTimeGetCurrent() - startTime);
	//	NSLog(@"Linked in %f ms", linkTime * 1000.0);
	return YES;
}

- (void)use {
	
	glUseProgram(program);
}

#pragma mark -

- (void)validate {
	
	GLint logLength;
	
	glValidateProgram(program);
	glGetProgramiv(program, GL_INFO_LOG_LENGTH, &logLength);
	
	if (logLength > 0) {
		
		GLchar *log = (GLchar *)malloc(logLength);
		glGetProgramInfoLog(program, logLength, &logLength, log);
		self.programLog = [NSString stringWithFormat:@"%s", log];
		free(log);
	}
}

#pragma mark -
- (void)dealloc {
	
	if (vertShader) {
		glDeleteShader(vertShader);
	}
	
	if (fragShader) {
		glDeleteShader(fragShader);
	}
	
	if (program) {
		glDeleteProgram(program);
	}
}

@end
