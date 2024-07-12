//
//  NSBundle+Extensions.m
//
//
//  Created by Kevin McKee
//
#import <Foundation/Foundation.h>
#include "include/NSBundle+Extensions.h"

@implementation NSBundle (Extension)

+ (NSBundle*) shadersBundle {
    return SWIFTPM_MODULE_BUNDLE;
}

@end
