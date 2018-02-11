//
//  PBRemoteProgressSheetController.m
//  GitX
//
//  Created by Nathan Kinsinger on 12/6/09.
//  Copyright 2009 Nathan Kinsinger. All rights reserved.
//

#import "PBRemoteProgressSheet.h"
#import "PBGitWindowController.h"
#import "PBGitRepositoryDocument.h"
#import "PBGitRepository.h"
#import "PBGitBinary.h"
#import "PBTask.h"
#import "PBError.h"



NSString * const kGitXProgressDescription        = @"PBGitXProgressDescription";
NSString * const kGitXProgressSuccessDescription = @"PBGitXProgressSuccessDescription";
NSString * const kGitXProgressSuccessInfo        = @"PBGitXProgressSuccessInfo";
NSString * const kGitXProgressErrorDescription   = @"PBGitXProgressErrorDescription";
NSString * const kGitXProgressErrorInfo          = @"PBGitXProgressErrorInfo";

@interface PBRemoteProgressSheet () {
	NSArray  *arguments;
	NSString *title;
	NSString *description;
	bool hideSuccessScreen;

	NSInteger  returnCode;

	NSTextField         *progressDescription;
	NSProgressIndicator *progressIndicator;
}

@end



@implementation PBRemoteProgressSheet


@synthesize progressDescription;
@synthesize progressIndicator;



#pragma mark -
#pragma mark PBRemoteProgressSheet

+ (void) beginRemoteProgressSheetWithTitle:(NSString *)theTitle
							   description:(NSString *)theDescription
								 arguments:(NSArray *)args
						  windowController:(PBGitWindowController *)windowController
{
	[self beginRemoteProgressSheetWithTitle:theTitle
								description:theDescription
								  arguments:args
									  inDir:nil
						   windowController:windowController];
}

+ (void) beginRemoteProgressSheetWithTitle:(NSString *)theTitle
							   description:(NSString *)theDescription
								 arguments:(NSArray *)args
									 inDir:(NSString *)dir
						  windowController:(PBGitWindowController *)windowController
{
	PBRemoteProgressSheet *sheet = [[self alloc] initWithWindowNibName:@"PBRemoteProgressSheet"
												windowController:windowController];
	[sheet beginRemoteProgressSheetWithTitle:theTitle
								 description:theDescription
								   arguments:args
									   inDir:dir
						   hideSuccessScreen:NO];
}

+ (void) beginRemoteProgressSheetWithTitle:(NSString *)theTitle
							   description:(NSString *)theDescription
								 arguments:(NSArray *)args
						 hideSuccessScreen:(BOOL)hideSucc
						  windowController:(PBGitWindowController *)windowController

{
	PBRemoteProgressSheet *sheet = [[self alloc] initWithWindowNibName:@"PBRemoteProgressSheet"
												windowController:windowController];
	[sheet beginRemoteProgressSheetWithTitle:theTitle
								 description:theDescription
								   arguments:args
									   inDir:nil
						   hideSuccessScreen:hideSucc];
}

- (void) beginRemoteProgressSheetWithTitle:(NSString *)theTitle
							   description:(NSString *)theDescription
								 arguments:(NSArray *)args
									 inDir:(NSString *)dir
						 hideSuccessScreen:(BOOL)hideSucc
{
	arguments   = args;
	title       = theTitle;
	description = theDescription;
	hideSuccessScreen = hideSucc;

	[self window]; // loads the window (if it wasn't already)

	// resize window if the description is larger than the default text field
	NSRect originalFrame = [self.progressDescription frame];
	[self.progressDescription setStringValue:[self progressTitle]];
	NSAttributedString *attributedTitle = [self.progressDescription attributedStringValue];
	NSSize boundingSize = originalFrame.size;
	boundingSize.height = 0.0f;
	NSRect boundingRect = [attributedTitle boundingRectWithSize:boundingSize
														options:NSStringDrawingUsesLineFragmentOrigin];
	CGFloat heightDelta = boundingRect.size.height - originalFrame.size.height;
	if (heightDelta > 0.0f) {
		NSRect windowFrame = [[self window] frame];
		windowFrame.size.height += heightDelta;
		[[self window] setFrame:windowFrame display:NO];
	}

	[self.progressIndicator startAnimation:nil];
	[self show];

	if (dir == nil)
		dir = [[(PBGitRepositoryDocument *)self.windowController.document repository] workingDirectory];

	[PBTask launchTask:[PBGitBinary path] arguments:arguments inDirectory:dir completionHandler:^(NSData * _Nullable readData, NSError * _Nullable error) {
		[self.progressIndicator stopAnimation:nil];

		PBRemoteProgressSheet* ownRef = self;
		[self hide];

		[ownRef showMessageWithTaskData:readData taskError:error];
		[ownRef.repository reloadRefs];
	}];
}


#pragma mark Messages


- (void) showMessageWithTaskData:(NSData *)data taskError:(NSError *)error
{
	if (error) {
		NSMutableString *info = [NSMutableString string];
		[info appendString:[self errorDescription]];
		[info appendString:[self commandDescription]];

		if (data) {
			[info appendString:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
		}

		[self.windowController showErrorSheet:error];
	} else if (!hideSuccessScreen) {
		NSMutableString *info = [NSMutableString string];
		[info appendString:[self successDescription]];
		[info appendString:[self commandDescription]];

		if (data) {
			[info appendString:[[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding]];
		}

		[self.windowController showMessageSheet:self.successTitle infoText:info];
	}
}


#pragma mark Display Strings

- (NSString *) progressTitle
{
	NSString *progress = description;
	if (!progress)
		progress = @"Operation in progress.";

	return progress;
}


- (NSString *) successTitle
{
	NSString *success = title;
	if (!success)
		success = @"Operation";

	return [success stringByAppendingString:@" completed."];
}


- (NSString *) successDescription
{
	NSString *info = description;
	if (!info)
		return @"";

	return [info stringByAppendingString:@" completed successfully.\n\n"];
}


- (NSString *) errorTitle
{
	NSString *error = title;
	if (!error)
		error = @"Operation";

	return [error stringByAppendingString:@" failed."];
}


- (NSString *) errorDescription
{
	NSString *info = description;
	if (!info)
		return @"";

	return [info stringByAppendingString:@" encountered an error.\n\n"];
}


- (NSString *) commandDescription
{
	if (!arguments || ([arguments count] == 0))
		return @"";

	return [NSString stringWithFormat:@"command: git %@", [arguments componentsJoinedByString:@" "]];
}


@end
