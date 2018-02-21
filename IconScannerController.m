//
//  IconScannerAppDelegate.m
//  IconScanner
//
//  Created by Sveinbjorn Thordarson on 9/7/10.
//  Copyright 2010 Sveinbjorn Thordarson. All rights reserved.
//  Distributed under a 3-clause BSD License
//

#import "IconScannerController.h"
#import "STUtil.h"
#import <Quartz/Quartz.h>


//==============================================================================
// This is the data source object.
@interface myImageObject : NSObject
{
    NSString* path; 
    int imageSize;
}
@property (nonatomic) int imageSize;

@end

@implementation myImageObject

- (void)dealloc {
    [path release];
    [super dealloc];
}

- (void)setPath:(NSString*)inPath {
    if (path != inPath) {
        [path release];
        path = [inPath retain];
    }
}

// The required methods of the IKImageBrowserItem protocol.
#pragma mark - Item data source protocol

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
    
    int                             itemsFound;
    IBOutlet id                     progressWindow;
    IBOutlet id                     progressBar;
    IBOutlet id                     progressTextField;
}
- (IBAction)scan:(id)sender;
- (IBAction)zoomSliderDidChange:(id)sender;

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
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(foundFiles)
                                                 name:@"IconScannerFilesFoundNotification"
                                               object:NULL];
}

- (void)dealloc {
    [images release];
    [importedImages release];
    [activeSet release];
    [imagesSubset release];
    [super dealloc];
}

- (void)awakeFromNib {
    // Create two arrays: The first is for the data source representation.
    // The second one contains temporary imported images for thread safeness.
    images = [[NSMutableArray alloc] init];
    importedImages = [[NSMutableArray alloc] init];
    
    // Allow reordering, animations and set the dragging destination delegate.
    [imageBrowser setAllowsReordering:YES];
    [imageBrowser setAnimates:YES];
    [imageBrowser setDraggingDestinationDelegate:self];
    [imageBrowser setAllowsMultipleSelection:NO];
    [imageBrowser setZoomValue:[[[NSUserDefaults standardUserDefaults] objectForKey:@"iconDisplaySize"] floatValue]];
    imagesSubset = NULL;
    filterTimer = NULL;
}

- (void)updateDatasource {
    // Update the datasource, add recently imported items.
    [images addObjectsFromArray:importedImages];
    
    // Empty the temporary array.
    [importedImages removeAllObjects];
    
    // Reload the image browser, which triggers setNeedsDisplay.
    [imageBrowser reloadData];
}

#pragma mark - Import images from file system

// -------------------------------------------------------------------------
//    isImageFile:filePath
//
//    This utility method indicates if the file located at 'filePath' is
//    an image file based on the UTI. It relies on the ImageIO framework for the
//    supported type identifiers.
//
// -------------------------------------------------------------------------
- (BOOL)isImageFile:(NSString *)filePath {
    BOOL                isImageFile = NO;
    LSItemInfoRecord    info;
    CFStringRef         uti = NULL;
    
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
        }
    }
    
    return isImageFile;
}

- (void)addAnImageWithPath:(NSString*)path {
    if ([self isImageFile:path]) {
        // Add a path to the temporary images array.
        myImageObject* p = [[myImageObject alloc] init];
        [p setPath:path];
        [importedImages addObject:p];
        [p release];
    }
}

- (IBAction)scan:(id)sender {
    if ([[sender title] isEqualToString:@"Cancel"]) {
        [task terminate];
        [output release];
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
    
    int selectedTool = [[[NSUserDefaults standardUserDefaults] objectForKey:@"scanToolIndex"] intValue];
    NSString *cmd = [[NSUserDefaults standardUserDefaults] objectForKey:@"ScanTools"][selectedTool];
    
    NSArray *cmdComponents = [cmd componentsSeparatedByString:@" "];
    [task setLaunchPath:cmdComponents[0]];
     NSIndexSet *indexSet = [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(1, [cmdComponents count]-1)];
     [task setArguments:[cmdComponents objectsAtIndexes:indexSet]];
    
    
    if ([[searchToolPopupButton titleOfSelectedItem] isEqualToString:@"locate"]) {
        [task setLaunchPath:@"/usr/bin/locate"];
        [task setArguments:@[@"*.icns"]];
    } else if ([[searchToolPopupButton titleOfSelectedItem] isEqualToString:@"mdfind"]) {
        [task setLaunchPath:@"/usr/bin/mdfind"];
        //[task setArguments:@[@"-name", @".icns"]];
        [task setArguments:@[@"kMDItemContentType == 'com.apple.icns'"]];
    } else if ([[searchToolPopupButton titleOfSelectedItem] isEqualToString:@"find"]) {
//find / \! \( -path "/bin/*" -or -path "/dev/*" -or -path "/sbin/*" -or -path "/private/*" -or -path "/usr/*" -or -name ".*" \) -name *.icns -print
        [task setLaunchPath:@"/usr/bin/find"];
        [task setArguments:@[@"/", @"-name", @"*.icns"]];
    } else {
        [STUtil fatalAlert:@"Illegal search tool" subText:@"No search tool specified"];
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
        NSString *outputStr = [[[NSString alloc] initWithData:data encoding:NSASCIIStringEncoding] autorelease];
        
        output = [[output stringByAppendingString:outputStr] retain];
        
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
    
    [output release];
    [progressIndicator stopAnimation:self];
    [self filterResults];
    [self updateDatasource];
    [numItemsLabel setStringValue:[NSString stringWithFormat:@"%d items", (int)[activeSet count]]];
    [searchFilterTextField setEnabled:YES];
    task = NULL;
    [scanButton setTitle:@"Scan"];
    
    // Dialog ends here.
    [NSApp endSheet:progressWindow];
    [progressWindow orderOut:self];
}

// creates a subset of the list of files based on our filtering criterion
- (void)filterResults {
    NSEnumerator *e = [images objectEnumerator];
    id object;
    
    if (imagesSubset != NULL) {
        [imagesSubset release];
    }
    
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
    if (filterTimer != NULL) {
        [filterTimer invalidate];
        filterTimer = NULL;
    }
    filterTimer = [NSTimer scheduledTimerWithTimeInterval:0.3 target:self selector:@selector(updateListing) userInfo:nil repeats:NO];
}

- (void)updateListing {
    [self filterResults];
    [self updateDatasource];
    [filterTimer invalidate];
    filterTimer = NULL;
}

- (NSString *)selectedFilePath {
    NSUInteger sel = [[imageBrowser selectionIndexes] firstIndex];
    if (sel == -1) {
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
    NSAutoreleasePool *pool = [[NSAutoreleasePool alloc] init];
    [paths retain];
    
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
    
    [paths release];
    [pool release];
}

#pragma mark - Actions

- (IBAction)zoomSliderDidChange:(id)sender {
    // update the zoom value to scale images
    [imageBrowser setZoomValue:[sender floatValue]];
    
    // redisplay
    [imageBrowser setNeedsDisplay:YES];
}

#pragma mark - IKImageBrowserDataSource

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

#pragma mark - IKImageBrowserDelegate

- (void)imageBrowserSelectionDidChange:(IKImageBrowserView *)aBrowser {
    NSString *path = [self selectedFilePath];
    [selectedIconPathLabel setStringValue:path];
    [selectedIconFileSizeLabel setStringValue:[STUtil fileOrFolderSizeAsHumanReadable:path]];
    
    NSImage *img = [[[NSImage alloc] initByReferencingFile:path] autorelease];
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

#pragma mark - Drag and Drop

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
