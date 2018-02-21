//
//  Created by Sveinbjorn Thordarson on 9/7/10.
//  Copyright 2010 Sveinbjorn Thordarson. All rights reserved.
//  Distributed under a 3-clause BSD License
//

#import <Foundation/Foundation.h>
#import <Cocoa/Cocoa.h>

@interface STUtil : NSObject

+ (void)alert:(NSString *)message subText:(NSString *)subtext;
+ (void)fatalAlert:(NSString *)message subText:(NSString *)subtext;
+ (BOOL)proceedWarning:(NSString *)message subText:(NSString *)subtext withAction:(NSString *)action;
+ (void)sheetAlert:(NSString *)message subText:(NSString *)subtext forWindow:(NSWindow *)window;
+ (UInt64)fileOrFolderSize:(NSString *)path;
+ (NSString *)sizeAsHumanReadable:(UInt64)size;
+ (NSString *)fileOrFolderSizeAsHumanReadable:(NSString *)path;
+ (NSArray *)imageFileSuffixes;

@end
