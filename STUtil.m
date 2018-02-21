//
//  Created by Sveinbjorn Thordarson on 9/7/10.
//  Copyright 2010 Sveinbjorn Thordarson. All rights reserved.
//  Distributed under a 3-clause BSD License
//

#import "STUtil.h"

@implementation STUtil

+ (void)alert:(NSString *)message subText:(NSString *)subtext {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert addButtonWithTitle:@"OK"];
    [alert setMessageText:message];
    [alert setInformativeText:subtext];
    [alert setAlertStyle:NSWarningAlertStyle];
    
    [alert runModal]; 
    [alert release];
}

+ (void)fatalAlert:(NSString *)message subText:(NSString *)subtext {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert addButtonWithTitle:@"OK"];
    [alert setMessageText:message];
    [alert setInformativeText:subtext];
    [alert setAlertStyle:NSCriticalAlertStyle];
    [alert runModal];
    [alert release];
    [[NSApplication sharedApplication] terminate:self];
}

+ (void)sheetAlert:(NSString *)message subText:(NSString *)subtext forWindow:(NSWindow *)window {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert addButtonWithTitle:@"OK"];
    [alert setMessageText:message];
    [alert setInformativeText:subtext];
    [alert setAlertStyle:NSCriticalAlertStyle];
    [alert beginSheetModalForWindow:window modalDelegate:self didEndSelector:nil contextInfo:nil];
    [alert release];
}

+ (BOOL) proceedWarning:(NSString *)message subText:(NSString *)subtext withAction:(NSString *)action {
    NSAlert *alert = [[NSAlert alloc] init];
    [alert addButtonWithTitle:action];
    [alert addButtonWithTitle:@"Cancel"];
    [alert setMessageText:message];
    [alert setInformativeText:subtext];
    [alert setAlertStyle:NSWarningAlertStyle];
    
    if ([alert runModal] == NSAlertFirstButtonReturn) {
        [alert release];
        return YES;
    }
    [alert release];
    return NO;
}

+ (UInt64)fileOrFolderSize:(NSString *)path {
    NSString *fileOrFolderPath = [path copy];
#if !__has_feature(objc_arc)
    [fileOrFolderPath autorelease];
#endif
    
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
        size = [[self class] nrCalculateFolderSize:fileOrFolderPath];
    } else {
        size = [[[NSFileManager defaultManager] attributesOfItemAtPath:fileOrFolderPath error:nil] fileSize];
    }
    
    return size;
}

+ (unsigned long long)nrCalculateFolderSize:(NSString *)folderPath {
    unsigned long long size = 0;
    NSURL *url = [NSURL fileURLWithPath:folderPath];
    [[self class] getAllocatedSize:&size ofDirectoryAtURL:url error:nil];
    return size;
}

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

+ (NSString *)fileOrFolderSizeAsHumanReadable:(NSString *)path {
    return [self sizeAsHumanReadable:[self fileOrFolderSize:path]];
}

+ (NSString *)sizeAsHumanReadable:(UInt64)size {
    NSString *str = @"0 B";
    
    if( size < 1024ULL )  {
        /* bytes */
        str = [NSString stringWithFormat:@"%u B", (unsigned int)size];
    } 
    else if( size < 1048576ULL)  {
        /* kbytes */
        str = [NSString stringWithFormat:@"%d KB", (int)size/1024];
    } 
    else if( size < 1073741824ULL ) {
        /* megabytes */
        str = [NSString stringWithFormat:@"%.1f MB", size / 1048576.0];
    } 
    else {
        /* gigabytes */
        str = [NSString stringWithFormat:@"%.1f GB", size / 1073741824.0];
    }
    
    return str;
}

+ (NSArray *)imageFileSuffixes {
    return @[@"icns",
            @"pdf",
            @"jpg",
            @"png",
            @"jpeg",
            @"gif",
            @"tif",
            @"bmp",
            @"pcx",
            @"raw",
            @"pct",
            @"rsr",
            @"pxr",
            @"sct",
            @"tga",
            @"ICNS",
            @"PDF",
            @"JPG",
            @"PNG",
            @"JPEG",
            @"GIF",
            @"TIF",
            @"BMP",
            @"PCX",
            @"RAW",
            @"PCT",
            @"RSR",
            @"PXR",
            @"SCT",
            @"TGA"];
}

@end
