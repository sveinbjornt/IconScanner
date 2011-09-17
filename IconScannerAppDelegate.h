//
//  IconScannerAppDelegate.h
//  IconScanner
//
//  Created by Sveinbjorn Thordarson on 9/7/10.
//  Copyright 2010 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>
#import <Quartz/Quartz.h>
#import "RegexKitLite.h"
#import "STUtil.h"

@interface IconScannerAppDelegate : NSObject
{
    NSWindow						*window;
	IBOutlet id						progressIndicator;
	IBOutlet IKImageBrowserView*	imageBrowser;
	NSMutableArray*					images;
	NSMutableArray*					imagesSubset;
	NSMutableArray*					activeSet;
	NSMutableArray*					importedImages;
	NSTask							*task;
	NSTimer							*checkStatusTimer;
	NSTimer							*filterTimer;
	NSString						*output;
	NSPipe							*outputPipe;
	NSFileHandle					*readHandle;
	IBOutlet id						scanButton;
	IBOutlet id						selectedIconPathLabel;
	IBOutlet id						selectedIconSizeLabel;
	IBOutlet id						selectedIconFileSizeLabel;
	IBOutlet id						selectedIconImageView;
	IBOutlet id						selectedIconRepsLabel;
	IBOutlet id						statusLabel;
	IBOutlet id						iconSizeSlider;
	IBOutlet id						selectedIconBox;
	IBOutlet id						numItemsLabel;
	IBOutlet id						searchFilterTextField;
	IBOutlet id						searchToolPopupButton;
	
	int								itemsFound;
	IBOutlet id						progressWindow;
	IBOutlet id						progressBar;
	IBOutlet id						progressTextField;
}
- (IBAction)scan:(id)sender;
- (IBAction)zoomSliderDidChange:(id)sender;
-(IBAction)searchCatSet:(id)sender;

@property (assign) IBOutlet NSWindow *window;

@end
