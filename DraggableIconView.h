//
//  DraggableIconView.h
//
//  Created by Sveinbjorn Thordarson on 9/7/10.
//  Copyright 2010 Sveinbjorn Thordarson. All rights reserved.
//  Distributed under a 3-clause BSD License
//

#import <Cocoa/Cocoa.h>

@protocol DraggableIconViewDelegate <NSObject>
- (NSString *)selectedFilePath;
- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender;
- (void)draggingExited:(id <NSDraggingInfo>)sender;
- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender;
- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender;
- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender;
- (void)concludeDragOperation:(id <NSDraggingInfo>)sender;
@end

@interface DraggableIconView : NSImageView 
{
    NSEvent *downEvent;
}

@property (nonatomic, assign) id <DraggableIconViewDelegate>delegate;

@end
