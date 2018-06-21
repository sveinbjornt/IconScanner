/*
 Copyright (c) 2003-2018, Sveinbjorn Thordarson <sveinbjorn@sveinbjorn.org>
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without modification,
 are permitted provided that the following conditions are met:
 
 1. Redistributions of source code must retain the above copyright notice, this
 list of conditions and the following disclaimer.
 
 2. Redistributions in binary form must reproduce the above copyright notice, this
 list of conditions and the following disclaimer in the documentation and/or other
 materials provided with the distribution.
 
 3. Neither the name of the copyright holder nor the names of its contributors may
 be used to endorse or promote products derived from this software without specific
 prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED.
 IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT,
 INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT
 NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY,
 WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE)
 ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
 POSSIBILITY OF SUCH DAMAGE.
 */

#import "NSWorkspace+Additions.h"
#import <sys/stat.h>
#import <sys/types.h>
#import <dirent.h>

@implementation NSWorkspace (Additions)

#pragma mark - File/folder size

//  Copyright (c) 2015 Nikolai Ruhe. All rights reserved.
//
// This method calculates the accumulated size of a directory on the volume in bytes.
//
// As there's no simple way to get this information from the file system it has to crawl the entire hierarchy,
// accumulating the overall sum on the way. The resulting value is roughly equivalent with the amount of bytes
// that would become available on the volume if the directory would be deleted.
//
// Caveat: There are a couple of oddities that are not taken into account (like symbolic links, meta data of
// directories, hard links, ...).

- (BOOL)getAllocatedSize:(unsigned long long *)size ofDirectoryAtURL:(NSURL *)directoryURL error:(NSError * __autoreleasing *)error
{
    NSParameterAssert(size != NULL);
    NSParameterAssert(directoryURL != nil);
    
    // We'll sum up content size here:
    unsigned long long accumulatedSize = 0;
    
    // prefetching some properties during traversal will speed up things a bit.
    NSArray *prefetchedProperties = @[NSURLIsRegularFileKey,
                                      NSURLFileAllocatedSizeKey,
                                      NSURLTotalFileAllocatedSizeKey];
    
    // The error handler simply signals errors to outside code.
    __block BOOL errorDidOccur = NO;
    BOOL (^errorHandler)(NSURL *, NSError *) = ^(NSURL *url, NSError *localError) {
        if (error != NULL) {
            *error = localError;
        }
        errorDidOccur = YES;
        return NO;
    };
    
    // We have to enumerate all directory contents, including subdirectories.
    NSDirectoryEnumerator *enumerator = [[NSFileManager defaultManager] enumeratorAtURL:directoryURL
                                                             includingPropertiesForKeys:prefetchedProperties
                                                                                options:(NSDirectoryEnumerationOptions)0
                                                                           errorHandler:errorHandler];
    
    // Start the traversal:
    for (NSURL *contentItemURL in enumerator) {
        
        // Bail out on errors from the errorHandler.
        if (errorDidOccur)
            return NO;
        
        // Get the type of this item, making sure we only sum up sizes of regular files.
        NSNumber *isRegularFile;
        if (! [contentItemURL getResourceValue:&isRegularFile forKey:NSURLIsRegularFileKey error:error])
            return NO;
        if (! [isRegularFile boolValue])
            continue; // Ignore anything except regular files.
        
        // To get the file's size we first try the most comprehensive value in terms of what the file may use on disk.
        // This includes metadata, compression (on file system level) and block size.
        NSNumber *fileSize;
        if (! [contentItemURL getResourceValue:&fileSize forKey:NSURLTotalFileAllocatedSizeKey error:error])
            return NO;
        
        // In case the value is unavailable we use the fallback value (excluding meta data and compression)
        // This value should always be available.
        if (fileSize == nil) {
            if (! [contentItemURL getResourceValue:&fileSize forKey:NSURLFileAllocatedSizeKey error:error])
                return NO;
            
            NSAssert(fileSize != nil, @"huh? NSURLFileAllocatedSizeKey should always return a value");
        }
        
        // We're good, add up the value.
        accumulatedSize += [fileSize unsignedLongLongValue];
    }
    
    // Bail out on errors from the errorHandler.
    if (errorDidOccur)
        return NO;
    
    // We finally got it.
    *size = accumulatedSize;
    return YES;
}

- (unsigned long long)nrCalculateFolderSize:(NSString *)folderPath {
    unsigned long long size = 0;
    NSURL *url = [NSURL fileURLWithPath:folderPath];
    [self getAllocatedSize:&size ofDirectoryAtURL:url error:nil];
    return size;
}

- (UInt64)fileOrFolderSize:(NSString *)path {
    NSString *fileOrFolderPath = [path copy];
    
    BOOL isDir;
    if (path == nil || ![[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir]) {
        return 0;
    }
    
    // resolve if symlink
    NSDictionary *fileAttrs = [[NSFileManager defaultManager] attributesOfItemAtPath:fileOrFolderPath error:nil];
    if (fileAttrs) {
        NSString *fileType = [fileAttrs fileType];
        if ([fileType isEqualToString:NSFileTypeSymbolicLink]) {
            NSError *err;
            fileOrFolderPath = [[NSFileManager defaultManager] destinationOfSymbolicLinkAtPath:fileOrFolderPath error:&err];
            if (fileOrFolderPath == nil) {
                NSLog(@"Error resolving symlink %@: %@", path, [err localizedDescription]);
                fileOrFolderPath = path;
            }
        }
    }
    
    UInt64 size = 0;
    if (isDir) {
        NSDirectoryEnumerator *dirEnumerator = [[NSFileManager defaultManager] enumeratorAtPath:fileOrFolderPath];
        while ([dirEnumerator nextObject]) {
            if ([NSFileTypeRegular isEqualToString:[[dirEnumerator fileAttributes] fileType]]) {
                size += [[dirEnumerator fileAttributes] fileSize];
            }
        }
        size = [[NSWorkspace sharedWorkspace] nrCalculateFolderSize:fileOrFolderPath];
    } else {
        size = [[[NSFileManager defaultManager] attributesOfItemAtPath:fileOrFolderPath error:nil] fileSize];
    }
    
    return size;
}

- (NSString *)fileOrFolderSizeAsHumanReadable:(NSString *)path {
    return [self fileSizeAsHumanReadableString:[self fileOrFolderSize:path]];
}

- (NSString *)fileSizeAsHumanReadableString:(UInt64)size {
    NSString *str;
    
    if (size < 1024ULL) {
        str = [NSString stringWithFormat:@"%u bytes", (unsigned int)size];
    } else if (size < 1048576ULL) {
        str = [NSString stringWithFormat:@"%llu KB", (UInt64)size / 1024];
    } else if (size < 1073741824ULL) {
        str = [NSString stringWithFormat:@"%.1f MB", size / 1048576.0];
    } else {
        str = [NSString stringWithFormat:@"%.1f GB", size / 1073741824.0];
    }
    return str;
}

#pragma mark - Default apps for files

- (NSString *)defaultApplicationForFile:(NSString *)filePath {
    CFURLRef appURL;

    OSStatus ret = LSGetApplicationForURL((__bridge CFURLRef)[NSURL fileURLWithPath:filePath], kLSRolesAll, NULL, &appURL);
    if (ret != noErr || appURL == nil) {
        return nil;
    }
    
    return [(__bridge NSURL *)appURL path];
}

- (NSMenu *)openWithMenuForFile:(NSString *)path target:(id)target action:(SEL)selector {
    // create open with submenu
    NSMenu *submenu = [[NSMenu alloc] initWithTitle: @"Open With"];
    
    //get default app for file
    NSString *defaultApp = [self defaultApplicationForFile:path];
    NSString *defaultAppName = [NSString stringWithFormat:@"%@", [[NSFileManager defaultManager] displayNameAtPath:defaultApp]];
    
    NSMenuItem *defaultAppItem = [submenu addItemWithTitle:defaultAppName action:selector keyEquivalent:@""];
    NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFile:defaultApp];
    [icon setSize:NSMakeSize(16,16)];
    [defaultAppItem setImage:icon];
    [defaultAppItem setTarget:target];
    [defaultAppItem setToolTip:defaultApp];
    
    [submenu addItem:[NSMenuItem separatorItem]];
    
    //get all apps that open this file
    NSArray *apps = [self applicationsForFile:path];
    if (apps == nil) {
        [submenu addItemWithTitle: @"None" action:nil keyEquivalent: @""];
    }
    
    apps = [apps sortedArrayUsingSelector:@selector(localizedCaseInsensitiveCompare:)];
    
    for (int i = 0; i < [apps count]; i++) {
        if ([[apps objectAtIndex:i] isEqualToString:defaultApp]) {
            continue;
        }
        
        NSString *title = [[NSFileManager defaultManager] displayNameAtPath:[apps objectAtIndex:i]];
        
        NSMenuItem *item = [submenu addItemWithTitle:title action:selector keyEquivalent:@""];
        [item setTarget:target];
        [item setToolTip:[apps objectAtIndex:i]];
        
        NSImage *icon = [[NSWorkspace sharedWorkspace] iconForFile:[apps objectAtIndex:i]];
        if (icon != nil) {
            [icon setSize:NSMakeSize(16,16)];
            [item setImage:icon];
        }
    }
    
    return submenu;
}

- (NSArray *)applicationsForFile:(NSString *)filePath {
    NSURL *url = [NSURL fileURLWithPath:filePath];
    NSMutableArray *appPaths = [NSMutableArray array];
    
    NSArray *applications = (__bridge NSArray *)LSCopyApplicationURLsForURL((__bridge CFURLRef)url, kLSRolesAll);
    if (applications == nil) {
        return nil;
    }
    
    for (int i = 0; i < [applications count]; i++) {
        [appPaths addObject: [[applications objectAtIndex:i] path]];
    }
    return appPaths;
}

- (BOOL)getInfoInFinderForFile:(NSString *)path {
    BOOL isDir;
    if ([[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] == NO) {
        NSBeep();
        return NO;
    }
    
    NSString *type = (isDir && ![[NSWorkspace sharedWorkspace] isFilePackageAtPath:path]) ? @"folder" : @"file";
    NSString *osaScript = [NSString stringWithFormat:
                           @"tell application \"Finder\"\n\
                           \tactivate\n\
                           \topen the information window of %@ POSIX file \"%@\"\n\
                           end tell", type, path, nil];
    
    NSAppleScript *appleScript = [[NSAppleScript alloc] initWithSource:osaScript];
    if (appleScript != nil) {
        [appleScript executeAndReturnError:nil];
        return YES;
    } else {
        NSLog(@"Error running AppleScript");
        return NO;
    }
}

@end
