//
//  DraggableIconView.m
//
//  Created by Sveinbjorn Thordarson on 9/7/10.
//  Copyright 2010 Sveinbjorn Thordarson. All rights reserved.
//  Distributed under a 3-clause BSD License
//

#import "DraggableIconView.h"

@implementation DraggableIconView

#pragma mark - Dragging

- (NSDragOperation)draggingEntered:(id <NSDraggingInfo>)sender {
    if (_delegate && [_delegate respondsToSelector:@selector(draggingEntered:)])
        return [_delegate draggingEntered:sender];
    else
        return [super draggingEntered:sender];
}

- (void)draggingExited:(id <NSDraggingInfo>)sender {
    if (_delegate && [_delegate respondsToSelector:@selector(draggingExited:)])
        [_delegate draggingExited:sender];
    else
        [super draggingExited:sender];
}

- (NSDragOperation)draggingUpdated:(id <NSDraggingInfo>)sender {
    if (_delegate && [_delegate respondsToSelector:@selector(draggingUpdated:)])
        return [_delegate draggingUpdated:sender];
    else
        return [super draggingUpdated:sender];
}

- (BOOL)prepareForDragOperation:(id <NSDraggingInfo>)sender {
    if (_delegate && [_delegate respondsToSelector:@selector(prepareForDragOperation:)])
        return [_delegate prepareForDragOperation:sender];
    else
        return [super prepareForDragOperation:sender];
}

- (BOOL)performDragOperation:(id <NSDraggingInfo>)sender {
    if (_delegate && [_delegate respondsToSelector:@selector(performDragOperation:)])
        return [_delegate performDragOperation:sender];
    else
        return [super performDragOperation:sender];
}

- (void)concludeDragOperation:(id <NSDraggingInfo>)sender {
    if (_delegate && [_delegate respondsToSelector:@selector(concludeDragOperation:)])
        [_delegate concludeDragOperation:sender];
    else
        [super concludeDragOperation:sender];
}

#pragma mark - Drag source

- (void)mouseDown:(NSEvent*)event {
    //get the Pasteboard used for drag and drop operations
    NSPasteboard *dragPasteboard = [NSPasteboard pasteboardWithName:NSDragPboard];
    
    if ([self image] == nil) {
        return;
    }
    
    //create a new image for our semi-transparent drag image
    NSImage *dragImage = [[NSImage alloc] initWithSize:[[self image] size]];
    if (dragImage == nil) {
        return;
    }
    
    //OK, let's see if we have an icns file behind this
    NSString *path = [_delegate selectedFilePath];
    if (![path isEqualToString:@""]) {
        [dragPasteboard declareTypes:@[NSFilenamesPboardType] owner:self];
        [dragPasteboard setPropertyList:@[path] forType:NSFilenamesPboardType];
    }
    
    //draw our original image as 50% transparent
    [dragImage lockFocus];    
    [[self image] dissolveToPoint:NSZeroPoint fraction:.5];
    [dragImage unlockFocus];//finished drawing
    [dragImage setSize:[self bounds].size];//change to the size we are displaying
    
    //execute the drag
    [self dragImage:dragImage                   //image to be displayed under the mouse
                 at:[self bounds].origin        //point to start drawing drag image
             offset:NSZeroSize                  //no offset, drag starts at mousedown location
              event:event                       //mousedown event
         pasteboard:dragPasteboard              //pasteboard to pass to receiver
             source:self                        //object where the image is coming from
          slideBack:YES];                       //if the drag fails slide the icon back
    
    [dragImage release];
}

- (NSDragOperation)draggingSourceOperationMaskForLocal:(BOOL)flag {
    return flag ? NSDragOperationNone : NSDragOperationCopy;
}

- (BOOL)ignoreModifierKeysWhileDragging {
    return YES;
}

- (BOOL)acceptsFirstMouse:(NSEvent *)event {
    //so source doesn't have to be the active window
    return YES;
}

@end
