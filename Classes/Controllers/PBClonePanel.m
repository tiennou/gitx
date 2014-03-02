//
//  PBClonePanel.m
//  GitX
//
//  Created by Etienne on 02/03/2014.
//
//

#import "PBClonePanel.h"

@interface PBClonePanel () <NSOpenSavePanelDelegate>
@property (strong) IBOutlet NSTextField *remoteURLField;
@property (strong) IBOutlet NSPathControl *localURLPath;
@property (strong) IBOutlet NSView *accessoryView;
@property NSURL *localURL;

- (IBAction)chooseLocation:(id)sender;
@end

@implementation PBClonePanel

+ (instancetype)clonePanel
{
	return [[self alloc] init];
}

- (void)awakeFromNib
{
    [self.localURLPath setHidden:YES];
}

- (BOOL)runModal
{
	NSNib *accessoryNib = [[NSNib alloc] initWithNibNamed:@"PBClonePanelAccessoryView" bundle:[NSBundle mainBundle]];
	[accessoryNib instantiateWithOwner:self topLevelObjects:nil];

	NSSavePanel *panel = [NSSavePanel savePanel];
	[panel setTitle:@"Clone Repository"];
	[panel setMessage:@"Choose the repository to clone and where to put it"];
	[panel setNameFieldLabel:@"Repository name:"];
	[panel setPrompt:@"Clone"];
	[panel setAccessoryView:self.accessoryView];

	BOOL success = ([panel runModal] == NSFileHandlingPanelOKButton);
	if (!success) return NO;

	self.localURL = panel.URL;

	return YES;
}

- (IBAction)chooseLocation:(id)sender
{
    NSOpenPanel *panel = [NSOpenPanel openPanel];

    [panel setDelegate:self];
    [panel setAllowsMultipleSelection:NO];
	[panel setCanChooseDirectories:YES];
    [panel setAllowedFileTypes:@[@"git"]];

    if ([panel runModal] == NSFileHandlingPanelOKButton) {
        if ([panel.URL isFileURL]) {
            self.localURLPath.URL = panel.URL;
            [self.localURLPath setHidden:NO];
            self.remoteURLField.stringValue = @"";
            [self.remoteURLField setHidden:YES];
        } else {
            self.localURLPath.URL = nil;
            [self.localURLPath setHidden:YES];
            self.remoteURLField.stringValue = panel.URL.absoluteString;
            [self.remoteURLField setHidden:NO];
        }
    }
}

- (NSURL *)cloneURL
{
    NSString *location = self.remoteURLField.stringValue;
    if (![location isEqualToString:@""])
        return [NSURL URLWithString:location];

    return self.localURLPath.URL;
}

#pragma mark -
#pragma mark NSOpenSavePanelDelegate

- (BOOL)panel:(id)sender validateURL:(NSURL *)url error:(NSError **)outError
{
	git_buf buf = GIT_BUF_INIT_CONST("", 0);
    int res = git_repository_discover(&buf, url.fileSystemRepresentation, 0, url.fileSystemRepresentation);
    if (res != GIT_OK) {
        if (outError) *outError = [NSError git_errorFor:res];
        return NO;
    }
    return YES;
}

@end
