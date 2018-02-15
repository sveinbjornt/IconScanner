//
//  IconScannerAppDelegate.m
//  IconScanner
//
//  Created by Sveinbjorn Thordarson on 9/7/10.
//  Copyright 2010 Sveinbjorn Thordarson. All rights reserved.
//  Distributed under a 3-clause BSD License
//

#import "IconScannerAppDelegate.h"

//==============================================================================
// This is the data source object.
@interface myImageObject : NSObject
{
    NSString* path; 
	int imageSize;
}
- (int)imageSize;
- (void)setImageSize: (int)size;

@end

@implementation myImageObject

// -------------------------------------------------------------------------
//	dealloc
// -------------------------------------------------------------------------
- (void)dealloc
{
    [path release];
    [super dealloc];
}

// -------------------------------------------------------------------------
//	setPath:path
//
//	The data source object is just a file path representation
// -------------------------------------------------------------------------
- (void)setPath:(NSString*)inPath
{
    if (path != inPath)
	{
        [path release];
        path = [inPath retain];
    }
}

// The required methods of the IKImageBrowserItem protocol.
#pragma mark -
#pragma mark item data source protocol

// -------------------------------------------------------------------------
//	imageRepresentationType:
//
//	Set up the image browser to use a path representation.
// -------------------------------------------------------------------------
- (NSString*)imageRepresentationType
{
	return IKImageBrowserPathRepresentationType;
}

// -------------------------------------------------------------------------
//	imageRepresentation:
//
//	Give the path representation to the image browser.
// -------------------------------------------------------------------------
- (id)imageRepresentation
{
	return path;
}

// -------------------------------------------------------------------------
//	imageUID:
//
//	Use the absolute file path as the identifier.
// -------------------------------------------------------------------------
- (NSString*)imageUID
{
    return path;
}

- (int)imageSize
{
	return imageSize;
}

-(void)setImageSize: (int)size
{
	imageSize = size;
}

@end

//==============================================================================
@implementation IconScannerAppDelegate

@synthesize window;

+ (void)initialize 
{ 
	// create the user defaults here if none exists
    NSMutableDictionary *defaultPrefs = [NSMutableDictionary dictionary];
    
	[defaultPrefs setObject: [NSNumber numberWithBool:YES] forKey: @"pathInFilter"];
	[defaultPrefs setObject: [NSNumber numberWithBool:NO] forKey: @"filenameInFilter"];
	[defaultPrefs setObject: [NSNumber numberWithInt: 0] forKey: @"scanToolIndex"];
	[defaultPrefs setObject: [NSNumber numberWithFloat: 0.5] forKey: @"iconDisplaySize"];
	// load tool cmd dictionary
	NSDictionary *scanToolsDict = [NSDictionary dictionaryWithContentsOfFile: [[NSBundle mainBundle] pathForResource: @"ScanTools" ofType:@"plist"]];
	[defaultPrefs setObject: [scanToolsDict objectForKey: @"ScanTools"] forKey: @"ScanTools"];
	
    // register the dictionary of defaults
    [[NSUserDefaults standardUserDefaults] registerDefaults: defaultPrefs];
}

- (void)applicationDidFinishLaunching:(NSNotification *)aNotification 
{	
	[[NSNotificationCenter defaultCenter] addObserver:self
											 selector:@selector(foundFiles)
												 name:@"IconScannerFilesFoundNotification"
											   object:NULL];
}

// -------------------------------------------------------------------------
//	dealloc:
// -------------------------------------------------------------------------
- (void)dealloc
{
    [images release];
    [importedImages release];
	[activeSet release];
	[imagesSubset release];
	[super dealloc];
}

// -------------------------------------------------------------------------
//	awakeFromNib:
// -------------------------------------------------------------------------
- (void)awakeFromNib
{
	// Create two arrays : The first is for the data source representation.
	// The second one contains temporary imported images  for thread safeness.
    images = [[NSMutableArray alloc] init];
    importedImages = [[NSMutableArray alloc] init];
    
    // Allow reordering, animations and set the dragging destination delegate.
    [imageBrowser setAllowsReordering:YES];
    [imageBrowser setAnimates:YES];
    [imageBrowser setDraggingDestinationDelegate:self];
	[imageBrowser setAllowsMultipleSelection: NO];
	[imageBrowser setZoomValue: [[[NSUserDefaults standardUserDefaults] objectForKey: @"iconDisplaySize"] floatValue]];
	imagesSubset = NULL;
	filterTimer = NULL;
}

// -------------------------------------------------------------------------
//	updateDatasource:
//
//	This is the entry point for reloading image browser data and triggering setNeedsDisplay.
// -------------------------------------------------------------------------
- (void)updateDatasource
{
    // Update the datasource, add recently imported items.
    [images addObjectsFromArray:importedImages];
	
	// Empty the temporary array.
    [importedImages removeAllObjects];
    
    // Reload the image browser, which triggers setNeedsDisplay.
    [imageBrowser reloadData];
}


#pragma mark -
#pragma mark import images from file system

// -------------------------------------------------------------------------
//	isImageFile:filePath
//
//	This utility method indicates if the file located at 'filePath' is
//	an image file based on the UTI. It relies on the ImageIO framework for the
//	supported type identifiers.
//
// -------------------------------------------------------------------------
- (BOOL)isImageFile:(NSString*)filePath
{
	BOOL				isImageFile = NO;
	LSItemInfoRecord	info;
	CFStringRef			uti = NULL;
	
	CFURLRef url = CFURLCreateWithFileSystemPath(NULL, (CFStringRef)filePath, kCFURLPOSIXPathStyle, FALSE);
	
	if (LSCopyItemInfoForURL(url, kLSRequestExtension | kLSRequestTypeCreator, &info) == noErr)
	{
		// Obtain the UTI using the file information.
		
		// If there is a file extension, get the UTI.
		if (info.extension != NULL)
		{
			uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, info.extension, kUTTypeData);
			CFRelease(info.extension);
		}
		
		// No UTI yet
		if (uti == NULL)
		{
			// If there is an OSType, get the UTI.
			CFStringRef typeString = UTCreateStringForOSType(info.filetype);
			if ( typeString != NULL)
			{
				uti = UTTypeCreatePreferredIdentifierForTag(kUTTagClassOSType, typeString, kUTTypeData);
				CFRelease(typeString);
			}
		}
		
		// Verify that this is a file that the ImageIO framework supports.
		if (uti != NULL)
		{
			CFArrayRef  supportedTypes = CGImageSourceCopyTypeIdentifiers();
			CFIndex		i, typeCount = CFArrayGetCount(supportedTypes);
			
			for (i = 0; i < typeCount; i++)
			{
				if (UTTypeConformsTo(uti, (CFStringRef)CFArrayGetValueAtIndex(supportedTypes, i)))
				{
					isImageFile = YES;
					break;
				}
			}
		}
	}
	
	return isImageFile;
}

// -------------------------------------------------------------------------
//	addAnImageWithPath:path
// -------------------------------------------------------------------------
- (void)addAnImageWithPath:(NSString*)path
{   
	if ([self isImageFile:path])
	{
		// Add a path to the temporary images array.
		myImageObject* p = [[myImageObject alloc] init];
		[p setPath:path];
		[importedImages addObject:p];
		[p release];
	}
}

-(IBAction)scan:(id)sender
{
	if ([[sender title] isEqualToString: @"Cancel"])
	{
		[task terminate];
		[output release];
		[progressIndicator stopAnimation: self];
		[sender setTitle: @"Scan"];
		return;
	}
	
	itemsFound = 0;
	[self foundFiles];
	[sender setTitle: @"Cancel"];
	
	[progressIndicator setUsesThreadedAnimation: YES];
	[progressIndicator startAnimation: self];
	
	[images removeAllObjects];
	output = @"";
	
	task = [[NSTask alloc] init];
	
	outputPipe = [NSPipe pipe];
	[task setStandardOutput: outputPipe];
	readHandle = [outputPipe fileHandleForReading];
	[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(getTextData:) name: NSFileHandleReadCompletionNotification object:readHandle];
	[readHandle readInBackgroundAndNotify];
	
	int selectedTool = [[[NSUserDefaults standardUserDefaults] objectForKey: @"scanToolIndex"] intValue];
	NSString *cmd = [[[NSUserDefaults standardUserDefaults] objectForKey: @"ScanTools"] objectAtIndex: selectedTool];
	
	NSArray *cmdComponents = [cmd componentsSeparatedByString: @" "];
	[task setLaunchPath: [cmdComponents objectAtIndex: 0]];
	 NSIndexSet *indexSet = [NSIndexSet indexSetWithIndexesInRange: NSMakeRange(1, [cmdComponents count]-1)];
	 [task setArguments: [cmdComponents objectsAtIndexes: indexSet]];
	
	
	if ([[searchToolPopupButton titleOfSelectedItem] isEqualToString: @"locate"])
	{
		[task setLaunchPath: @"/usr/bin/locate"];
		[task setArguments: [NSArray arrayWithObject: @"*.icns"]];
	}
	else if ([[searchToolPopupButton titleOfSelectedItem] isEqualToString: @"mdfind"])
	{
		[task setLaunchPath: @"/usr/bin/mdfind"];
		[task setArguments: [NSArray arrayWithObjects: @"-name", @".icns", nil]];
	}
	else if ([[searchToolPopupButton titleOfSelectedItem] isEqualToString: @"find"])
	{
//find / \! \( -path "/bin/*" -or -path "/dev/*" -or -path "/sbin/*" -or -path "/private/*" -or -path "/usr/*" -or -name ".*" \) -name *.icns -print
		[task setLaunchPath: @"/usr/bin/find"];
		[task setArguments: [NSArray arrayWithObjects: @"/", @"-name", @"*.icns", nil]];
	}
	else
	{
		[STUtil fatalAlert: @"Illegal search tool" subText:@"No search tool specified"];
	}

	[task launch];
	
	[progressBar setUsesThreadedAnimation: YES];
	[progressBar startAnimation: self];
	
	[NSApp beginSheet: progressWindow
	   modalForWindow: window
		modalDelegate: nil
	   didEndSelector: nil
		  contextInfo: nil];
	
	//set off timer that checks task status, i.e. when it's done 
	checkStatusTimer = [NSTimer scheduledTimerWithTimeInterval: 0.25 target: self selector:@selector(checkTaskStatus) userInfo: nil repeats: YES];
}

// read from the file handle and append it to the text window
- (void) getTextData: (NSNotification *)aNotification
{
	//get the data
	NSData *data = [[aNotification userInfo] objectForKey:NSFileHandleNotificationDataItem];
	
	//make sure there's actual data
	if ([data length]) 
	{
		//append the output to the text field
		NSString *outputStr = [[[NSString alloc] initWithData: data encoding: NSASCIIStringEncoding] autorelease];
		
		output = [[output stringByAppendingString: outputStr] retain];
		
		itemsFound += [[outputStr componentsSeparatedByString: @"\n"] count]-1;
		[[NSNotificationCenter defaultCenter] postNotificationName: @"IconScannerFilesFoundNotification" object:self];
		
		// we schedule the file handle to go and read more data in the background again.
		[[aNotification object] readInBackgroundAndNotify];
	}
}


// check if task is running
- (void)checkTaskStatus
{
	if (![task isRunning])//if it's no longer running, we do clean up
	{
		[checkStatusTimer invalidate];
		[self taskFinished];
	}
}

-(void)taskFinished
{		
	NSMutableArray *appPaths = [NSMutableArray arrayWithArray: [output componentsSeparatedByString: @"\n"]];
	[appPaths removeLastObject];
	[self addImagesWithPaths: appPaths];
	
	[output release];
	[progressIndicator stopAnimation: self];
	[self filterResults];
	[self updateDatasource];
	[numItemsLabel setStringValue: [NSString stringWithFormat: @"%d items", [activeSet count]]];
	[searchFilterTextField setEnabled: YES];
	task == NULL;
	[scanButton setTitle: @"Scan"];
	
	// Dialog ends here.
    [NSApp endSheet: progressWindow];
    [progressWindow orderOut: self];
}

// creates a subset of the list of files based on our filtering criterion
- (void)filterResults
{
	NSEnumerator *e = [images objectEnumerator];
	id object;
	
	if (imagesSubset != NULL)
		[imagesSubset release];
	
	imagesSubset = [[NSMutableArray alloc] init];
	
	NSString *regex = [[NSString alloc] initWithString: [searchFilterTextField stringValue]];
	
	while ( object = [e nextObject] )
	{
		BOOL filtered = NO;
		
		// see if regex in search field filters it out
		if (!filtered && [[searchFilterTextField stringValue] length] > 0)
		{
			if ([[NSUserDefaults standardUserDefaults] boolForKey: @"pathInFilter"] &&
				[[object imageRepresentation] isMatchedByRegex: regex] == YES) 
				[imagesSubset addObject:object];
			else if ([[NSUserDefaults standardUserDefaults] boolForKey: @"filenameInFilter"] &&
				[[[object imageRepresentation] lastPathComponent] isMatchedByRegex: regex] == YES) 
				[imagesSubset addObject:object];
			else
			{
				filtered = YES;
			}

		}
		else if (!filtered)
			[imagesSubset addObject:object];
	}
	
	[regex release];
	
	activeSet = imagesSubset;
		
	[numItemsLabel setStringValue: [NSString stringWithFormat: @"%d items", [activeSet count]]];
}

- (void)controlTextDidChange:(NSNotification *)aNotification
{
	if (filterTimer != NULL)
	{
		[filterTimer invalidate];
		filterTimer = NULL;
	}
	filterTimer = [NSTimer scheduledTimerWithTimeInterval: 0.3 target: self selector:@selector(updateListing) userInfo: nil repeats: NO];
}

-(IBAction)searchCatSet:(id)sender
{
	[sender setState: ![sender state]];

	[[NSUserDefaults standardUserDefaults] setBool: [sender state] forKey: @"pathInFilter"];
	[[NSUserDefaults standardUserDefaults] setBool: ![sender state] forKey: @"filenameInFilter"];
	
	[self updateListing];
}

-(void)updateListing
{
	[self filterResults];
	[self updateDatasource];
	[filterTimer invalidate];
	filterTimer = NULL;
}

-(NSString *)selectedFilePath
{
	int sel = [[imageBrowser selectionIndexes] firstIndex];
	if (sel == -1)
		return @"";
	NSString *path =  [[activeSet objectAtIndex: sel] imageRepresentation];
	return path;
}

-(void)foundFiles
{
	[progressTextField setStringValue: [NSString stringWithFormat: @"Found %d icons", itemsFound]];
}

// -------------------------------------------------------------------------
//	addImagesWithPaths:paths
//
//	Performed in an independent thread, parse all paths in "paths" and
//	add these paths in the temporary images array.
// -------------------------------------------------------------------------
- (void)addImagesWithPaths:(NSArray*)paths
{   
    NSAutoreleasePool* pool = [[NSAutoreleasePool alloc] init];
    [paths retain];
	
    NSInteger i, n;
	n = [paths count];
    for (i = 0; i < n; i++)
	{
        NSString* path = [paths objectAtIndex:i];
		
	    BOOL dir;
		[[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&dir];
		if (!dir)
			[self addAnImageWithPath:path];
    }
	
	// Update the data source in the main thread.
    [self performSelectorOnMainThread:@selector(updateDatasource) withObject:nil waitUntilDone:YES];
	
    [paths release];
    [pool release];
}


#pragma mark -
#pragma mark actions


// -------------------------------------------------------------------------
//	addImageButtonClicked:sender
//
//	Action called when the zoom slider changes.
// ------------------------------------------------------------------------- 
- (IBAction)zoomSliderDidChange:(id)sender
{
	// update the zoom value to scale images
    [imageBrowser setZoomValue:[sender floatValue]];
	
	// redisplay
    [imageBrowser setNeedsDisplay:YES];
}


#pragma mark -
#pragma mark IKImageBrowserDataSource

// Implement the image browser  data source protocol .
// The data source representation is a simple mutable array.

// -------------------------------------------------------------------------
//	numberOfItemsInImageBrowser:view
// ------------------------------------------------------------------------- 
- (int)numberOfItemsInImageBrowser:(IKImageBrowserView*)view
{
	// The item count to display is the datadsource item count.
    return [activeSet count];
}

// -------------------------------------------------------------------------
//	imageBrowser:view:index:
// ------------------------------------------------------------------------- 
- (id)imageBrowser:(IKImageBrowserView *) view itemAtIndex:(int) index
{
    return [activeSet objectAtIndex:index];
}


// Implement some optional methods of the image browser  datasource protocol to allow for removing and reodering items.

// -------------------------------------------------------------------------
//	removeItemsAtIndexes:
//
//	The user wants to delete images, so remove these entries from the data source.	
// ------------------------------------------------------------------------- 
- (void)imageBrowser:(IKImageBrowserView*)view removeItemsAtIndexes: (NSIndexSet*)indexes
{
	//[images removeObjectsAtIndexes:indexes];
}

// -------------------------------------------------------------------------
//	moveItemsAtIndexes:
//
//	The user wants to reorder images, update the datadsource and the browser
//	will reflect our changes.
// ------------------------------------------------------------------------- 
- (BOOL)imageBrowser:(IKImageBrowserView*)view moveItemsAtIndexes: (NSIndexSet*)indexes toIndex:(unsigned int)destinationIndex
{
/*	NSInteger		index;
	NSMutableArray*	temporaryArray;
	
	temporaryArray = [[[NSMutableArray alloc] init] autorelease];
	
	// First remove items from the data source and keep them in a temporary array.
	for (index = [indexes lastIndex]; index != NSNotFound; index = [indexes indexLessThanIndex:index])
	{
		if (index < destinationIndex)
			destinationIndex --;
		
		id obj = [images objectAtIndex:index];
		[temporaryArray addObject:obj];
		[images removeObjectAtIndex:index];
	}
	
	// Then insert the removed items at the appropriate location.
	NSInteger n = [temporaryArray count];
	for (index = 0; index < n; index++)
	{
		[images insertObject:[temporaryArray objectAtIndex:index] atIndex:destinationIndex];
	}*/
	
	return NO;
}


#pragma mark -
#pragma mark drag n drop 

// -------------------------------------------------------------------------
//	draggingEntered:sender
// ------------------------------------------------------------------------- 
- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender
{
    return NSDragOperationCopy;
}

// -------------------------------------------------------------------------
//	draggingUpdated:sender
// ------------------------------------------------------------------------- 
- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender
{
    return NSDragOperationCopy;
}

// -------------------------------------------------------------------------
//	performDragOperation:sender
// ------------------------------------------------------------------------- 
- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender
{
    /*NSData*			data = nil;
    NSPasteboard*	pasteboard = [sender draggingPasteboard];
	
	// Look for paths on the pasteboard.
    if ([[pasteboard types] containsObject:NSFilenamesPboardType]) 
        data = [pasteboard dataForType:NSFilenamesPboardType];
	
    if (data)
	{
		NSString* errorDescription;
		
		// Retrieve  paths.
        NSArray* filenames = [NSPropertyListSerialization propertyListFromData:data 
															  mutabilityOption:kCFPropertyListImmutable 
																		format:nil 
															  errorDescription:&errorDescription];
		
		// Add paths to the data source.
        NSInteger i, n;
        n = [filenames count];
        for (i = 0; i < n; i++)
		{
            [self addAnImageWithPath:[filenames objectAtIndex:i]];
        }
		
		// Make the image browser reload the data source.
        [self updateDatasource];
    }
		// Accept the drag operation.
	return YES;*/
	return NO;
}


#pragma mark Delegate for browser
- (void) imageBrowserSelectionDidChange:(IKImageBrowserView *) aBrowser
{
	int i;
	int highestRep = 0;
	
	NSString *path =  [self selectedFilePath];
	[selectedIconPathLabel setStringValue: path];
	[selectedIconFileSizeLabel setStringValue: [STUtil fileOrFolderSizeAsHumanReadable: path]];
	
	
	NSImage *img = [[[NSImage alloc] initByReferencingFile: path] autorelease];
	[selectedIconImageView setImage: img];
	[selectedIconBox setTitle: [path lastPathComponent]];
	
	NSArray *reps = [img representations];
	for (i = 0; i < [reps count]; i++)
	{
		int height = [[reps objectAtIndex: i] pixelsHigh];
		if (height > highestRep)
			highestRep = height;
	}	
	
	NSString *iconSizeStr = [NSString stringWithFormat: @"%d x %d", highestRep, highestRep];
	[selectedIconSizeLabel setStringValue: iconSizeStr];
	[selectedIconRepsLabel setStringValue: [NSString stringWithFormat: @"%d", [reps count]]];
}

@end
