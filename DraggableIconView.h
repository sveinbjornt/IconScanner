//
//  DraggableIconView.h
//
//  Created by Sveinbjorn Thordarson on 9/7/10.
//  Copyright 2010 Sveinbjorn Thordarson. All rights reserved.
//  Distributed under a 3-clause BSD License
//

#import <Cocoa/Cocoa.h>

@interface DraggableIconView : NSImageView 
{
	id delegate;
	NSEvent *downEvent;
}

- (void)setDelegate:(id)theDelegate;
- (id)delegate;

@end
