//
//  IconScannerAppDelegate.m
//  IconScanner
//
//  Created by Sveinbjorn Thordarson on 9/7/10.
//  Copyright 2010 Sveinbjorn Thordarson. All rights reserved.
//  Distributed under a 3-clause BSD License
//

#import "IconScannerController.h"
#import "NSWorkspace+Additions.h"
#import <Quartz/Quartz.h>

#pragma mark - Data source object

@interface myImageObject : NSObject
{
    NSString* path;
    int imageSize;
}
@property (nonatomic) int imageSize;

@end

@implementation myImageObject

- (void)setPath:(NSString *)inPath {
    if (path != inPath) {
        path = inPath;
    }
}

#pragma mark IKImageBrowserItem protocol

- (NSString*)imageRepresentationType {
    return IKImageBrowserPathRepresentationType;
}

- (id)imageRepresentation {
    return path;
}

- (NSString*)imageUID {
    return path;
}

- (int)imageSize {
    return imageSize;
}

- (void)setImageSize:(int)size {
    imageSize = size;
}

@end

#pragma mark - UI Controller

@interface IconScannerController ()
{
    IBOutlet NSWindow               *window;
    IBOutlet id                     progressIndicator;
    IBOutlet IKImageBrowserView     *imageBrowser;
    NSMutableArray                  *images;
    NSMutableArray                  *imagesSubset;
    NSMutableArray                  *activeSet;
    NSMutableArray                  *importedImages;
    NSTask                          *task;
    NSTimer                         *checkStatusTimer;
    NSTimer                         *filterTimer;
    NSString                        *output;
    NSPipe                          *outputPipe;
    NSFileHandle                    *readHandle;
    IBOutlet id                     scanButton;
    IBOutlet id                     selectedIconPathLabel;
    IBOutlet id                     selectedIconSizeLabel;
    IBOutlet id                     selectedIconFileSizeLabel;
    IBOutlet id                     selectedIconImageView;
    IBOutlet id                     selectedIconRepsLabel;
    IBOutlet id                     statusLabel;
    IBOutlet id                     iconSizeSlider;
    IBOutlet id                     selectedIconBox;
    IBOutlet id                     numItemsLabel;
    IBOutlet id                     searchFilterTextField;
    IBOutlet id                     searchToolPopupButton;
    IBOutlet id                     saveCopyButton;
    

    int                             itemsFound;
    IBOutlet id                     progressWindow;
    IBOutlet id                     progressBar;
    IBOutlet id                     progressTextField;
}
- (IBAction)scan:(id)sender;
- (IBAction)zoomSliderDidChange:(id)sender;
- (IBAction)saveCopy:(id)sender;
@end

@implementation IconScannerController

+ (void)initialize {
    // create the user defaults here if none exists
    NSMutableDictionary *defaultPrefs = [NSMutableDictionary dictionary];
    
    defaultPrefs[@"pathInFilter"] = @YES;
    defaultPrefs[@"filenameInFilter"] = @NO;
    defaultPrefs[@"scanToolIndex"] = @0;
    defaultPrefs[@"iconDisplaySize"] = @0.5f;
    // load tool cmd dictionary
    NSDictionary *scanToolsDict = [NSDictionary dictionaryWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"ScanTools" ofType:@"plist"]];
    defaultPrefs[@"ScanTools"] = scanToolsDict[@"ScanTools"];
    
    // register the dictionary of defaults
    [[NSUserDefaults standardUserDefaults] registerDefaults:defaultPrefs];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification {
    
    [window setRepresentedURL:[NSURL URLWithString:@""]];
    [[window standardWindowButton:NSWindowDocumentIconButton] setImage:[NSApp applicationIconImage]];
    
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(foundFiles)
                                                 name:@"IconScannerFilesFoundNotification"
                                               object:nil];
    
    
}

- (BOOL)window:(NSWindow *)window shouldPopUpDocumentPathMenu:(NSMenu *)menu {
    // Prevent popup menu when window icon/title is cmd-clicked
    return NO;
}

- (BOOL)window:(NSWindow *)window shouldDragDocumentWithEvent:(NSEvent *)event from:(NSPoint)dragImageLocation withPasteboard:(NSPasteboard *)pasteboard {
    // Prevent dragging of title bar icon
    return NO;
}

- (void)awakeFromNib {
    // Create two arrays: The first is for the data source representation.
    // The second one contains temporary imported images for thread safety.
    images = [NSMutableArray array];
    importedImages = [NSMutableArray array];
    
    // Allow reordering, animations and set the dragging destination delegate.
    [imageBrowser setAnimates:YES];
    [imageBrowser setDraggingDestinationDelegate:self];
    [imageBrowser setAllowsMultipleSelection:NO];
    [imageBrowser setAllowsReordering:NO];
    [imageBrowser setZoomValue:[[[NSUserDefaults standardUserDefaults] objectForKey:@"iconDisplaySize"] floatValue]];
}

- (void)updateDatasource {
    // Update the datasource, add recently imported items.
    [images addObjectsFromArray:importedImages];
    
    // Empty the temporary array.
    [importedImages removeAllObjects];
    
    // Reload the image browser, which triggers setNeedsDisplay.
    [imageBrowser reloadData];
}

// -------------------------------------------------------------------------
//    isImageFile:filePath
//
//    This utility method indicates if the file located at 'filePath' is
//    an image file based on the UTI. It relies on the ImageIO framework for the
//    supported type identifiers.
//
// -------------------------------------------------------------------------
- (BOOL)isImageFile:(NSString *)filePath {
    BOOL isImageFile = NO;
    LSItemInfoRecord info;
    CFStringRef uti = NULL;
    
    CFURLRef url = CFURLCreateWithFileSystemPath(NULL, (CFStringRef)filePath, kCFURLPOSIXPathStyle, FALSE);
    
    if (LSCopyItemInfoForURL(url, kLSRequestExtension | kLSRequestTypeCreator, &info) == noErr) {
        // Obtain the UTI using the file information.
        
        // If there is a file extension, get the UTI.
        if (info.extension != NULL) {
            uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, info.extension, kUTTypeData);
            CFRelease(info.extension);
        }
        
        // No UTI yet
        if (uti == NULL) {
            // If there is an OSType, get the UTI.
            CFStringRef typeString = UTCreateStringForOSType(info.filetype);
            if ( typeString != NULL) {
                uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassOSType, typeString, kUTTypeData);
                CFRelease(typeString);
            }
        }
        
        // Verify that this is a file that the ImageIO framework supports.
        if (uti != NULL) {
            CFArrayRef supportedTypes = CGImageSourceCopyTypeIdentifiers();
            CFIndex i, typeCount = CFArrayGetCount(supportedTypes);
            
            for (i = 0; i < typeCount; i++) {
                if (UTTypeConformsTo(uti, (CFStringRef)CFArrayGetValueAtIndex(supportedTypes, i))) {
                    isImageFile = YES;
                    break;
                }
            }
            
            CFRelease(supportedTypes);
            CFRelease(uti);
        }
    }
    
    CFRelease(url);
    
    return isImageFile;
}

- (void)addAnImageWithPath:(NSString*)path {
    if ([self isImageFile:path]) {
        // Add a path to the temporary images array.
        myImageObject* p = [[myImageObject alloc] init];
        [p setPath:path];
        [importedImages addObject:p];
    }
}

- (IBAction)scan:(id)sender {
    if ([[sender title] isEqualToString:@"Cancel"]) {
        [task terminate];
        [progressIndicator stopAnimation:self];
        [sender setTitle:@"Scan"];
        return;
    }
    
    itemsFound = 0;
    [self foundFiles];
    [sender setTitle:@"Cancel"];
    
    [progressIndicator setUsesThreadedAnimation:YES];
    [progressIndicator startAnimation:self];
    
    [images removeAllObjects];
    output = @"";
    
    task = [[NSTask alloc] init];
    
    outputPipe = [NSPipe pipe];
    [task setStandardOutput:outputPipe];
    readHandle = [outputPipe fileHandleForReading];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(getTextData:) name:NSFileHandleReadCompletionNotification object:readHandle];
    [readHandle readInBackgroundAndNotify];
    
    NSString *title = [searchToolPopupButton titleOfSelectedItem];
    if ([title isEqualToString:@"mdfind"]) {
        [task setLaunchPath:@"/usr/bin/mdfind"];
        //[task setArguments:@[@"-name", @".icns"]];
        [task setArguments:@[@"kMDItemContentType == 'com.apple.icns'"]];
    } else if ([title isEqualToString:@"find"]) {
        [task setLaunchPath:@"/usr/bin/find"];
        [task setArguments:@[@"/", @"-name", @"*.icns"]];
    } else if ([title isEqualToString:@"searchfs"]) {
        NSString *searchfsPath = [[NSBundle mainBundle] pathForResource:@"searchfs" ofType:@""];
        if ([[NSFileManager defaultManager] fileExistsAtPath:searchfsPath]) {
            [task setLaunchPath:searchfsPath];
            [task setArguments:@[@".icns"]];
        } else {
            NSBeep();
        }
    } else {
        [task setLaunchPath:@"/usr/bin/locate"];
        [task setArguments:@[@"*.icns"]];
    }
    
    [task launch];
    
    [progressBar setUsesThreadedAnimation:YES];
    [progressBar startAnimation:self];
    
    [NSApp beginSheet:progressWindow
       modalForWindow:window
        modalDelegate:nil
       didEndSelector:nil
          contextInfo:nil];
    
    //set off timer that checks task status, i.e. when it's done
    checkStatusTimer = [NSTimer scheduledTimerWithTimeInterval:0.25
                                                        target:self
                                                      selector:@selector(checkTaskStatus)
                                                      userInfo:nil
                                                       repeats:YES];
}

// read from the file handle and append it to the text window
- (void)getTextData:(NSNotification *)aNotification {
    //get the data
    NSData *data = [aNotification userInfo][NSFileHandleNotificationDataItem];
    
    //make sure there's actual data
    if ([data length]) {
        //append the output to the text field
        NSString *outputStr = [[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding];
        
        output = [output stringByAppendingString:outputStr];
        
        itemsFound += [[outputStr componentsSeparatedByString:@"\n"] count]-1;
        [[NSNotificationCenter defaultCenter] postNotificationName:@"IconScannerFilesFoundNotification" object:self];
        
        // we schedule the file handle to go and read more data in the background again.
        [[aNotification object] readInBackgroundAndNotify];
    }
}

// check if task is running
- (void)checkTaskStatus {
    if (![task isRunning]) {
        [checkStatusTimer invalidate];
        [self taskFinished];
    }
}

- (void)taskFinished {
    NSMutableArray *appPaths = [NSMutableArray arrayWithArray:[output componentsSeparatedByString:@"\n"]];
    [appPaths removeLastObject];
    [self addImagesWithPaths:appPaths];
    
    [progressIndicator stopAnimation:self];
    [self filterResults];
    [self updateDatasource];
    [numItemsLabel setStringValue:[NSString stringWithFormat:@"%d items", (int)[activeSet count]]];
    [searchFilterTextField setEnabled:YES];
    task = nil;
    [scanButton setTitle:@"Scan"];
    
    // Dialog ends here.
    [NSApp endSheet:progressWindow];
    [progressWindow orderOut:self];
}

// creates a subset of the list of files based on our filtering criterion
- (void)filterResults {
    NSEnumerator *e = [images objectEnumerator];
    id object;
    
    
    imagesSubset = [[NSMutableArray alloc] init];
    NSString *filterString = [searchFilterTextField stringValue];
    
    while (object = [e nextObject]) {
        BOOL filtered = NO;
        
        if ([filterString length]) {
            NSString *rep = [object imageRepresentation];
            
            if ([rep rangeOfString:filterString options:NSCaseInsensitiveSearch].location == NSNotFound) {
                filtered = YES;
            }
        }
        
        if (!filtered) {
            [imagesSubset addObject:object];
        }
    }
    
    activeSet = imagesSubset;
    
    [numItemsLabel setStringValue:[NSString stringWithFormat:@"%d items", (int)[activeSet count]]];
}

- (void)controlTextDidChange:(NSNotification *)aNotification {
    if (filterTimer != nil) {
        [filterTimer invalidate];
        filterTimer = nil;
    }
    filterTimer = [NSTimer scheduledTimerWithTimeInterval:0.3 target:self selector:@selector(updateListing) userInfo:nil repeats:NO];
}

- (void)updateListing {
    [self filterResults];
    [self updateDatasource];
    [filterTimer invalidate];
    filterTimer = nil;
}

- (NSString *)selectedFilePath {
    NSUInteger sel = [[imageBrowser selectionIndexes] firstIndex];
    if (sel == -1 || sel > [activeSet count]) {
        return @"";
    }
    
    NSString *path =  [activeSet[sel] imageRepresentation];
    return path;
}

- (void)foundFiles {
    [progressTextField setStringValue:[NSString stringWithFormat:@"Found %d icons", itemsFound]];
}

// -------------------------------------------------------------------------
//    addImagesWithPaths:paths
//
//    Performed in an independent thread, parse all paths in "paths" and
//    add these paths in the temporary images array.
// -------------------------------------------------------------------------
- (void)addImagesWithPaths:(NSArray*)paths {
    @autoreleasepool {
        
        NSInteger i, n;
        n = [paths count];
        for (i = 0; i < n; i++) {
            NSString* path = paths[i];
            
            BOOL dir;
            [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&dir];
            if (!dir) {
                [self addAnImageWithPath:path];
            }
        }
        
        // Update the data source in the main thread.
        [self performSelectorOnMainThread:@selector(updateDatasource) withObject:nil waitUntilDone:YES];
        
    }
}

- (IBAction)zoomSliderDidChange:(id)sender {
    // update the zoom value to scale images
    [imageBrowser setZoomValue:[sender floatValue]];
    
    // redisplay
    [imageBrowser setNeedsDisplay:YES];
}

- (IBAction)saveCopy:(id)sender {
    NSString *path = [self selectedFilePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path] == NO) {
        NSBeep();
        return;
    }
    
    // Run save panel
    NSSavePanel *sPanel = [NSSavePanel savePanel];
    [sPanel setPrompt:@"Save"];
    [sPanel setNameFieldStringValue:[path lastPathComponent]];
    [sPanel beginSheetModalForWindow:window completionHandler:^(NSInteger result) {
        NSString *destPath = [[sPanel URL] path];
        NSError *error;
        BOOL res = [[NSFileManager defaultManager] copyItemAtPath:path toPath:destPath error:&error];
        if (!res) {
            NSBeep();
            NSLog(@"%@", [error localizedDescription]);
        }
    }];
}

#pragma mark IKImageBrowserDataSource

// Implement the image browser data source protocol .
// The data source representation is a simple mutable array.

- (NSUInteger)numberOfItemsInImageBrowser:(IKImageBrowserView*)view {
    // The item count to display is the datadsource item count.
    return [activeSet count];
}

- (id)imageBrowser:(IKImageBrowserView *) view itemAtIndex:(NSUInteger) index {
    return activeSet[index];
}

- (void)imageBrowser:(IKImageBrowserView*)view removeItemsAtIndexes:(NSIndexSet*)indexes {
}

- (BOOL)imageBrowser:(IKImageBrowserView*)view moveItemsAtIndexes:(NSIndexSet*)indexes toIndex:(NSUInteger)destinationIndex {
    return NO;
}

#pragma mark IKImageBrowserDelegate

- (void)imageBrowserSelectionDidChange:(IKImageBrowserView *)aBrowser {
    [saveCopyButton setEnabled:[[self selectedFilePath] length]];
    
    NSString *path = [self selectedFilePath];
    [selectedIconPathLabel setStringValue:path];
    [selectedIconFileSizeLabel setStringValue:[[NSWorkspace sharedWorkspace] fileOrFolderSizeAsHumanReadable:path]];
    
    NSImage *img = [[NSImage alloc] initByReferencingFile:path];
    [selectedIconImageView setImage:img];
    [selectedIconBox setTitle:[path lastPathComponent]];
    
    NSArray *reps = [img representations];
    NSInteger highestRep = 0;
    for (NSInteger i = 0; i < [reps count]; i++) {
        NSInteger height = [(NSImageRep *)reps[i] pixelsHigh];
        if (height > highestRep) {
            highestRep = height;
        }
    }
    
    NSString *iconSizeStr = [NSString stringWithFormat:@"%d x %d", (int)highestRep, (int)highestRep];
    [selectedIconSizeLabel setStringValue:iconSizeStr];
    [selectedIconRepsLabel setStringValue:[NSString stringWithFormat:@"%d", (int)[reps count]]];
}

- (void)imageBrowser:(IKImageBrowserView *)aBrowser cellWasDoubleClickedAtIndex:(NSUInteger)index {
    NSString *path =  [activeSet[index] imageRepresentation];
    BOOL cmdKeyDown = (([[NSApp currentEvent] modifierFlags] & NSCommandKeyMask) == NSCommandKeyMask);
    
    if (cmdKeyDown) {
        [[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:path];
    } else {
        [[NSWorkspace sharedWorkspace] openFile:path];
    }
}

- (void)imageBrowser:(IKImageBrowserView *)aBrowser cellWasRightClickedAtIndex:(NSUInteger)index withEvent:(NSEvent *)event {
    NSUInteger i = [aBrowser indexOfItemAtPoint:[aBrowser convertPoint:[event locationInWindow] fromView:nil]];
    if (i == NSNotFound) {
        return;
    }

    NSString *path =  [self selectedFilePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:path] == NO) {
        return;
    }
    
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"menu"];
    [menu setAutoenablesItems:NO];
    
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:@"Open" action:@selector(openFile:) keyEquivalent:@""];
    [item setTarget:self];
    [menu addItem:item];
    
    item = [[NSMenuItem alloc] initWithTitle:@"Open With" action:nil keyEquivalent:@""];
    [item setSubmenu:[self getOpenWithSubmenuForFile:path]];
    [menu addItem:item];
    
    [menu addItem:[NSMenuItem separatorItem]];
    
    item = [[NSMenuItem alloc] initWithTitle:@"Get Info" action:@selector(getInfo:) keyEquivalent:@""];
    [item setTarget:self];
    [menu addItem:item];
    
    item = [[NSMenuItem alloc] initWithTitle:@"Show in Finder" action:@selector(showInFinder:) keyEquivalent:@""];
    [item setTarget:self];
    [menu addItem:item];
    
    [NSMenu popUpContextMenu:menu withEvent:event forView:aBrowser];
}

#pragma mark Contextual menu

- (void)openFile:(id)sender {
    NSString *path = [self selectedFilePath];
    [[NSWorkspace sharedWorkspace] openFile:path];
}

- (void)showInFinder:(id)sender {
    NSString *path = [self selectedFilePath];
    [[NSWorkspace sharedWorkspace] selectFile:path inFileViewerRootedAtPath:path];
}

- (void)getInfo:(id)sender {
    NSString *path = [self selectedFilePath];
    [[NSWorkspace sharedWorkspace] getInfoInFinderForFile:path];
}

- (void)openWithSelected:(id)sender {
    NSString *appName = [[[sender toolTip] lastPathComponent] stringByDeletingPathExtension];
    [[NSWorkspace sharedWorkspace] openFile:[self selectedFilePath] withApplication:appName];
    NSLog(@"Opening %@ with %@", [self selectedFilePath], appName);
}

- (NSMenu *)getOpenWithSubmenuForFile:(NSString *)path {
    // lazy load
    static NSMenu *menu = nil;
    if (menu) {
        return menu;
    }
    menu = [[NSWorkspace sharedWorkspace] openWithMenuForFile:path target:self action:@selector(openWithSelected:)];
    return menu;
}

#pragma mark Drag and Drop

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
    return NSDragOperationNone;
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender {
    return NSDragOperationCopy;
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender {
    return NO;
}

@end
