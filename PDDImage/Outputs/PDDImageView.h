//
//  PDDImageView.h
//  PDDImage
//
//  Created by 郝一鹏 on 2018/6/3.
//  Copyright © 2018年 郝一鹏. All rights reserved.
//

#import <UIKit/UIKit.h>
#import "PDDImageContext.h"

typedef NS_ENUM(NSUInteger, PDDImageFillModeType) {
    kPDDImageFillModeStretch,
    kPDDImageFillModePreserveAspectRatio,
    kPDDImageFillModePreserveAspectRatioAndFill,
};

@interface PDDImageView : UIView

@end
