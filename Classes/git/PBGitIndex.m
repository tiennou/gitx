//
//  PBGitIndex.m
//  GitX
//
//  Created by Pieter de Bie on 9/12/09.
//  Copyright 2009 Pieter de Bie. All rights reserved.
//

#import "PBGitIndex.h"
#import "PBGitRepository.h"
#import "PBGitRepository_PBGitBinarySupport.h"
#import "PBGitBinary.h"
#import "PBTask.h"
#import "PBChangedFile.h"
#import "PBError.h"

NSString *PBGitIndexIndexRefreshStatus = @"PBGitIndexIndexRefreshStatus";
NSString *PBGitIndexIndexRefreshFailed = @"PBGitIndexIndexRefreshFailed";
NSString *PBGitIndexFinishedIndexRefresh = @"PBGitIndexFinishedIndexRefresh";

NSString *PBGitIndexIndexUpdated = @"PBGitIndexIndexUpdated";

NSString *PBGitIndexAmendMessageAvailable = @"PBGitIndexAmendMessageAvailable";

NS_ENUM(NSUInteger, PBGitIndexOperation) {
	PBGitIndexStageFiles,
	PBGitIndexUnstageFiles,
};

@interface PBGitIndex (IndexRefreshMethods)

- (NSMutableDictionary *)dictionaryForLines:(NSArray *)lines;
- (void)addFilesFromDictionary:(NSMutableDictionary *)dictionary staged:(BOOL)staged tracked:(BOOL)tracked;

- (NSArray *)linesFromData:(NSData *)data;

@end

@interface PBGitIndex () {
	dispatch_queue_t _indexRefreshQueue;
	dispatch_group_t _indexRefreshGroup;
	BOOL _amend;
}

@property (retain) NSDictionary *amendEnvironment;
@property (retain) NSMutableArray <PBChangedFile *> *files;
@end

@implementation PBGitIndex

- (id)initWithRepository:(PBGitRepository *)theRepository
{
	if (!(self = [super init]))
		return nil;

	NSAssert(theRepository, @"PBGitIndex requires a repository");

	_repository = theRepository;

	_files = [NSMutableArray array];

	_indexRefreshGroup = dispatch_group_create();

	return self;
}

- (NSArray *)indexChanges
{
	return self.files;
}

- (void)setAmend:(BOOL)newAmend
{
	if (newAmend == _amend)
		return;
	
	_amend = newAmend;
	self.amendEnvironment = nil;

	[self refresh];

	if (!newAmend)
		return;

	// If we amend, we want to keep the author information for the previous commit
	// We do this by reading in the previous commit, and storing the information
	// in a dictionary. This dictionary will then later be read by [self commit:]
	GTReference *headRef = [self.repository.gtRepo headReferenceWithError:NULL];
	GTCommit *commit = [headRef resolvedTarget];
	if (commit)
		self.amendEnvironment = @{
								  @"GIT_AUTHOR_NAME":  commit.author.name,
								  @"GIT_AUTHOR_EMAIL": commit.author.email,
								  @"GIT_AUTHOR_DATE":  commit.commitDate,
								  };

	NSDictionary *notifDict = nil;
	if (commit.message) {
		notifDict = @{@"message": commit.message};
	}
	[[NSNotificationCenter defaultCenter] postNotificationName:PBGitIndexAmendMessageAvailable
														object:self
													  userInfo:notifDict];
}

- (BOOL)isAmend
{
	return _amend;
}


- (void)postIndexRefreshFinished {
	dispatch_async(dispatch_get_main_queue(), ^{
		[[NSNotificationCenter defaultCenter] postNotificationName:PBGitIndexFinishedIndexRefresh object:self];
	});
}

// A multi-purpose notification sender for a refresh operation
// TODO: make -refresh take a completion handler, an NSError or *anything else*
- (void)postIndexRefreshSuccess:(BOOL)success message:(nullable NSString *)message {
	dispatch_async(dispatch_get_main_queue(), ^{
		if (!success) {
			[[NSNotificationCenter defaultCenter] postNotificationName:PBGitIndexIndexRefreshFailed
																object:self
															  userInfo:@{@"description": message}];
		} else {
			[[NSNotificationCenter defaultCenter] postNotificationName:PBGitIndexIndexRefreshStatus
																object:self
															  userInfo:@{@"description": message}];
		}
	});

	[self postIndexUpdated];
}

- (void)postIndexUpdated {
	dispatch_async(dispatch_get_main_queue(), ^{
		[[NSNotificationCenter defaultCenter] postNotificationName:PBGitIndexIndexUpdated object:self];
	});
}

- (void)refresh
{
	dispatch_group_enter(_indexRefreshGroup);

	// Ask Git to refresh the index
	[PBTask launchTask:[PBGitBinary path]
			 arguments:@[@"update-index", @"-q", @"--unmerged", @"--ignore-missing", @"--refresh"]
		   inDirectory:self.repository.workingDirectoryURL.path
	 completionHandler:^(NSData *readData, NSError *error) {
				 if (error) {
					 [self postIndexRefreshSuccess:NO message:@"update-index failed"];
				 } else {
					 [self postIndexRefreshSuccess:YES message:@"update-index success"];
				 }

				 dispatch_group_leave(self->_indexRefreshGroup);
			 }];


	// This block is called when each of the other blocks scheduled are done,
	// which means we can delete all files previously marked as deletable.
	// Note, there are scheduled blocks *below* this one ;-).
	dispatch_group_notify(_indexRefreshGroup, dispatch_get_main_queue(), ^{

		// At this point, all index operations have finished.
		// We need to find all files that don't have either
		// staged or unstaged files, and delete them

		NSMutableArray *deleteFiles = [NSMutableArray array];
		for (PBChangedFile *file in self.files) {
			if (!file.hasStagedChanges && !file.hasUnstagedChanges)
				[deleteFiles addObject:file];
		}

		if ([deleteFiles count]) {
			[self willChangeValueForKey:@"indexChanges"];
			for (PBChangedFile *file in deleteFiles)
				[self.files removeObject:file];
			[self didChangeValueForKey:@"indexChanges"];
		}

		[self postIndexRefreshFinished];
	});

	if ([self.repository isBareRepository])
	{
		return;
	}

	// Other files
	dispatch_group_enter(_indexRefreshGroup);
	[PBTask launchTask:[PBGitBinary path]
			 arguments:@[@"ls-files", @"--others", @"--exclude-standard", @"-z"]
		   inDirectory:self.repository.workingDirectoryURL.path
	 completionHandler:^(NSData *readData, NSError *error) {
		 if (error) {
			 [self postIndexRefreshSuccess:NO message:@"ls-files failed"];
		 } else {
			 NSArray *lines = [self linesFromData:readData];
			 NSMutableDictionary *dictionary = [[NSMutableDictionary alloc] initWithCapacity:[lines count]];
			 // Other files are untracked, so we don't have any real index information. Instead, we can just fake it.
			 // The line below is not used at all, as for these files the commitBlob isn't set
			 NSArray *fileStatus = [NSArray arrayWithObjects:@":000000", @"100644", @"0000000000000000000000000000000000000000", @"0000000000000000000000000000000000000000", @"A", nil];
			 for (NSString *path in lines) {
				 if ([path length] == 0)
					 continue;
				 [dictionary setObject:fileStatus forKey:path];
			 }

			 [self addFilesFromDictionary:dictionary staged:NO tracked:NO];
		 }

		 [self postIndexRefreshSuccess:YES message:@"ls-files success"];
		 dispatch_group_leave(self->_indexRefreshGroup);
	 }];

	// Staged files
	dispatch_group_enter(_indexRefreshGroup);
	[PBTask launchTask:[PBGitBinary path]
			 arguments:@[@"diff-index", @"--cached", @"-z", [self parentTree]]
		   inDirectory:self.repository.workingDirectoryURL.path
	 completionHandler:^(NSData *readData, NSError *error) {
		 if (error) {
			 [self postIndexRefreshSuccess:NO message:@"diff-index failed"];
		 } else {
			 NSArray *lines = [self linesFromData:readData];
			 NSMutableDictionary *dic = [self dictionaryForLines:lines];
			 [self addFilesFromDictionary:dic staged:YES tracked:YES];
		 }

		 [self postIndexRefreshSuccess:YES message:@"diff-index success"];

		 dispatch_group_leave(self->_indexRefreshGroup);
	 }];


	// Unstaged files
	dispatch_group_enter(_indexRefreshGroup);
	[PBTask launchTask:[PBGitBinary path]
			 arguments:@[@"diff-files", @"-z"]
		   inDirectory:self.repository.workingDirectoryURL.path
	 completionHandler:^(NSData *readData, NSError *error) {
		 if (error) {
			 [self postIndexRefreshSuccess:NO message:@"diff-files failed"];
		 } else {
			 NSArray *lines = [self linesFromData:readData];
			 NSMutableDictionary *dic = [self dictionaryForLines:lines];
			 [self addFilesFromDictionary:dic staged:NO tracked:YES];
		 }
		 [self postIndexRefreshSuccess:YES message:@"diff-files success"];

		 dispatch_group_leave(self->_indexRefreshGroup);
	 }];
}

// Returns the tree to compare the index to, based
// on whether amend is set or not.
- (NSString *) parentTree
{
	NSString *parent = self.amend ? @"HEAD^" : @"HEAD";
	
	if (![self.repository revisionExists:parent])
		// We don't have a head ref. Return the empty tree.
		return @"4b825dc642cb6eb9a060e54bf8d69288fbee4904";

	return parent;
}

- (void)performCommitWithMessage:(NSString *)commitMessage force:(BOOL)force progressHandler:(void (^)(NSString *))aProgressHandler completionHandler:(void (^)(NSError *error, GTOID *oid))aCompletionHandler
{
	NSParameterAssert(commitMessage != nil && commitMessage.length);
	NSError *repoError = nil;

	void (^progressHandler)(NSString *) = ^(NSString *msg) {
		if (aProgressHandler)
			aProgressHandler(msg);
	};

	void (^errorHandler)(NSError *) = ^(NSError *error) {
		if (aCompletionHandler)
			aCompletionHandler(error, nil);
	};

	NSMutableString *commitSubject = [@"commit: " mutableCopy];
	NSRange newLine = [commitMessage rangeOfString:@"\n"];
	if (newLine.location == NSNotFound)
		[commitSubject appendString:commitMessage];
	else
		[commitSubject appendString:[commitMessage substringToIndex:newLine.location]];
	
	NSString *commitMessageFile;
	commitMessageFile = [self.repository.gitURL.path stringByAppendingPathComponent:@"COMMIT_EDITMSG"];
	[commitMessage writeToFile:commitMessageFile atomically:YES encoding:NSUTF8StringEncoding error:nil];

	progressHandler(NSLocalizedString(@"Creating tree", @"PBGitIndex commit - status message"));

	NSString *tree = [self.repository outputOfTaskWithArguments:@[@"write-tree"] error:&repoError];
	tree = [tree stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!tree || tree.length != 40) {
		NSString *desc = NSLocalizedString(@"Creating tree failed", @"PBGitIndex commit - write-tree error description");
		NSString *reason = NSLocalizedString(@"There was an error creating the new commits' tree", @"PBGitIndex commit - write-tree error reason");
		NSError *error = [NSError pb_errorWithDescription:desc
											failureReason:reason
										  underlyingError:repoError];
		errorHandler(error);
		return;
	}

	/* Are we amending ? */
	NSMutableArray *arguments = [NSMutableArray arrayWithObjects:@"commit-tree", tree, nil];
	NSString *parent = self.amend ? @"HEAD^" : @"HEAD";
	if ([self.repository revisionExists:parent]) {
		[arguments addObject:@"-p"];
		[arguments addObject:parent];
	}

    if (!force) {
		progressHandler(NSLocalizedString(@"Running hooks", @"PBGitIndex commit - status message"));

		NSError *hookError = nil;
		BOOL success = [self.repository executeHook:@"pre-commit" error:&hookError];
        if (!success) {
			errorHandler(hookError);
			return;
		}

		success = [self.repository executeHook:@"commit-msg" arguments:@[commitMessageFile] error:&hookError];
		if (!success) {
			errorHandler(hookError);
			return;
        }
	}
	
	progressHandler(NSLocalizedString(@"Creating commit", @"PBGitIndex commit - status message"));

	commitMessage = [NSString stringWithContentsOfFile:commitMessageFile encoding:NSUTF8StringEncoding error:nil];

	PBTask *commitTask = [self.repository taskWithArguments:arguments];
	commitTask.standardInputData = [commitMessage dataUsingEncoding:NSUTF8StringEncoding];
	commitTask.additionalEnvironment = self.amendEnvironment;

	BOOL success = [commitTask launchTask:&repoError];
	NSString *commitSHA = [commitTask.standardOutputString stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
	if (!success || !commitSHA || commitSHA.length != 40) {

		NSString *desc = NSLocalizedString(@"Creating commit failed", @"PBGitIndex commit - commit-tree error description");
		NSString *reason = NSLocalizedString(@"There was an error creating the new commits' object", @"PBGitIndex commit - commit-tree error reason");
		NSError *error = [NSError pb_errorWithDescription:desc
											failureReason:reason
										  underlyingError:repoError];
		errorHandler(error);
		return;
	}

	progressHandler(NSLocalizedString(@"Updating HEAD", @"PBGitIndex commit - status message"));

	success = [self.repository launchTaskWithArguments:@[@"update-ref", @"-m", commitSubject, @"HEAD", commitSHA] error:&repoError];
	if (!success) {
		NSString *desc = NSLocalizedString(@"Failed to update HEAD", @"PBGitIndex commit - update-ref error description");
		NSString *reason = NSLocalizedString(@"There was an error while moving the HEAD reference to point to the new commit.", @"PBGitIndex commit - update-ref error reason");
		NSError *error = [NSError pb_errorWithDescription:desc
											failureReason:reason
										  underlyingError:repoError];
		errorHandler(error);
		return;
	}
	
	progressHandler(NSLocalizedString(@"Running post-commit hook", @"PBGitIndex commit - status message"));

	success = [self.repository executeHook:@"post-commit" error:&repoError];

	self.repository.hasChanged = YES;

	self.amendEnvironment = nil;
	if (self.amend)
		self.amend = NO;
	else
		[self refresh];

	if (aCompletionHandler)
		aCompletionHandler(repoError, [GTOID oidWithSHA:commitSHA]);
}

- (BOOL)performStageOrUnstage:(BOOL)stage withFiles:(NSArray *)files error:(NSError **)error
{
	// Do staging files by chunks of 1000 files each, to prevent program freeze (because NSPipe has limited capacity)

	NSUInteger filesCount = files.count;
	const NSUInteger MAX_FILES_PER_STAGE = 1000;

	// Prepare first iteration
	NSUInteger loopFrom = 0;
	NSUInteger loopTo = MAX_FILES_PER_STAGE;
	if (loopTo > filesCount)
		loopTo = filesCount;
	NSUInteger loopCount = 0;

	// Staging
	while (loopCount < filesCount) {
		// Input string for update-index
		// This will be a list of filenames that
		// should be updated. It's similar to
		// "git add -- <files>
		NSMutableString *input = [NSMutableString string];

		for (NSUInteger i = loopFrom; i < loopTo; i++) {
			loopCount++;

			PBChangedFile *file = [files objectAtIndex:i];

			if (stage) {
				[input appendFormat:@"%@\0", file.path];
			} else {
				NSString *indexInfo = [file indexInfo];
				[input appendString:indexInfo];
			}
		}

		NSArray *arguments = nil;
		if (stage) {
			arguments = @[@"update-index", @"--add", @"--remove", @"-z", @"--stdin"];
		} else {
			arguments = @[@"update-index", @"-z", @"--index-info"];
		}

		NSError *gitError = nil;
		BOOL success = [self.repository launchTaskWithArguments:arguments input:input error:&gitError];
		if (!success && stage) {
			return PBReturnErrorWithBuilder(error, ^{
				NSString *desc = @"Staging files failed";
				NSString *failure = @"";
				return [NSError pb_errorWithDescription:desc failureReason:failure underlyingError:gitError];
			});
		} else if (!success && !stage) {
			return PBReturnErrorWithBuilder(error, ^{
				NSString *desc = @"Unstaging files failed";
				NSString *failure = @"";
				return [NSError pb_errorWithDescription:desc failureReason:failure underlyingError:gitError];
			});
		}

		for (NSUInteger i = loopFrom; i < loopTo; i++) {
			PBChangedFile *file = [files objectAtIndex:i];
			file.hasStagedChanges = stage;
			file.hasUnstagedChanges = !stage;
		}

		// Prepare next iteration
		loopFrom = loopCount;
		loopTo = loopFrom + MAX_FILES_PER_STAGE;
		if (loopTo > filesCount)
			loopTo = filesCount;
	}

	[self postIndexUpdated];
	
	return YES;
}

- (BOOL)stageFiles:(NSArray<PBChangedFile *> *)stageFiles error:(NSError **)error
{
	return [self performStageOrUnstage:YES withFiles:stageFiles error:error];
}

- (BOOL)unstageFiles:(NSArray<PBChangedFile *> *)unstageFiles error:(NSError **)error
{
	return [self performStageOrUnstage:NO withFiles:unstageFiles error:error];
}

- (BOOL)discardChangesForFiles:(NSArray<PBChangedFile *> *)discardFiles error:(NSError **)error
{
	NSArray *paths = [discardFiles valueForKey:@"path"];
	NSString *input = [paths componentsJoinedByString:@"\0"];

	NSArray *arguments = @[@"checkout-index", @"--index", @"--quiet", @"--force", @"-z", @"--stdin"];
	PBTask *task = [self.repository taskWithArguments:arguments];
	task.standardInputData = [input dataUsingEncoding:NSUTF8StringEncoding];

	NSError *gitError = nil;
	BOOL success = [task launchTask:&gitError];
	if (!success) {
		return PBReturnErrorWithBuilder(error, ^{
			NSString *desc = @"Failed to discard changes";
			NSString *failure = [NSString stringWithFormat:@"Discarding changes failed with return value %@", gitError.userInfo[PBTaskTerminationStatusKey]];

			return [NSError pb_errorWithDescription:desc failureReason:failure underlyingError:gitError];
		});
	}

	for (PBChangedFile *file in discardFiles)
		if (file.isUntracked)
			file.hasUnstagedChanges = NO;

	[self postIndexUpdated];

	return YES;
}

- (BOOL)applyPatch:(NSString *)hunk stage:(BOOL)stage reverse:(BOOL)reverse error:(NSError **)error
{
	NSMutableArray *arguments = [NSMutableArray arrayWithObjects:@"apply", @"--unidiff-zero", nil];
	if (stage)
		[arguments addObject:@"--cached"];
	if (reverse)
		[arguments addObject:@"--reverse"];

	NSError *gitError = nil;
	BOOL success = [self.repository launchTaskWithArguments:arguments input:hunk error:&gitError];
	if (!success) {
		return PBReturnErrorWithBuilder(error, ^{
			NSString *desc = NSLocalizedString(@"Patch application failed", @"PBGitIndex - apply patch error description");
			NSString *failure = NSLocalizedString(@"The following patch failed to apply:", @"PBGitIndex - apply patch error description");
			failure = [failure stringByAppendingFormat:@"\n%@", hunk];
			return [NSError pb_errorWithDescription:desc failureReason:failure underlyingError:gitError];
		});
	}

	// TODO: Try to be smarter about what to refresh
	[self refresh];
	return YES;
}


- (NSString *)diffForFile:(PBChangedFile *)file staged:(BOOL)staged contextLines:(NSUInteger)context error:(NSError **)error
{
	NSString *parameter = [NSString stringWithFormat:@"-U%lu", context];
	if (staged) {
		NSString *indexPath = [@":0:" stringByAppendingString:file.path];

		if (file.isUntracked) {
			return [self.repository outputOfTaskWithArguments:@[@"show", indexPath] error:error];
		}

		NSArray *arguments = @[@"diff-index", parameter, @"--cached", self.parentTree, @"--", file.path];
		return [self.repository outputOfTaskWithArguments:arguments error:error];
	}

	// unstaged
	if (file.isUntracked) {
		NSStringEncoding encoding;
		NSError *error = nil;
		NSURL *fileURL = [self.repository.workingDirectoryURL URLByAppendingPathComponent:file.path];
		NSString *contents = [NSString stringWithContentsOfURL:fileURL
                                                  usedEncoding:&encoding
                                                         error:&error];
		return contents;
	}

	return [self.repository outputOfTaskWithArguments:@[@"diff-files", parameter, @"--", file.path] error:error];
}

/* This is called from JS */
- (NSString *)diffForFile:(PBChangedFile *)file staged:(BOOL)staged contextLines:(NSUInteger)context {
	return [self diffForFile:file staged:staged contextLines:context error:NULL];
}

# pragma mark WebKit Accessibility

+ (BOOL)isSelectorExcludedFromWebScript:(SEL)aSelector
{
	return NO;
}

@end

@implementation PBGitIndex (IndexRefreshMethods)

- (void) addFilesFromDictionary:(NSMutableDictionary *)dictionary staged:(BOOL)staged tracked:(BOOL)tracked
{
	// Iterate over all existing files
	for (PBChangedFile *file in self.files) {
		NSArray *fileStatus = [dictionary objectForKey:file.path];
		// Object found, this is still a cached / uncached thing
		if (fileStatus) {
			if (tracked) {
				NSString *mode = [[fileStatus objectAtIndex:0] substringFromIndex:1];
				NSString *sha = [fileStatus objectAtIndex:2];
				file.commitBlobSHA = sha;
				file.commitBlobMode = mode;
				
				if (staged)
					file.hasStagedChanges = YES;
				else
					file.hasUnstagedChanges = YES;
				if ([[fileStatus objectAtIndex:4] isEqualToString:@"D"])
					file.status = PBChangedFileStatusDeleted;
			} else {
				// Untracked file, set status to NEW, only unstaged changes
				file.hasStagedChanges = NO;
				file.hasUnstagedChanges = YES;
				file.status = PBChangedFileStatusUntracked;
			}

			// We handled this file, remove it from the dictionary
			[dictionary removeObjectForKey:file.path];
		} else {
			// Object not found in the dictionary, so let's reset its appropriate
			// change (stage or untracked) if necessary.

			// Staged dictionary, so file does not have staged changes
			if (staged)
				file.hasStagedChanges = NO;
			// Tracked file does not have unstaged changes, file is not new,
			// so we can set it to No. (If it would be new, it would not
			// be in this dictionary, but in the "other dictionary").
			else if (tracked && !file.isUntracked)
				file.hasUnstagedChanges = NO;
			// Unstaged, untracked dictionary ("Other" files), and file
			// is indicated as new (which would be untracked), so let's
			// remove it
			else if (!tracked && file.isUntracked && file.commitBlobSHA == nil)
				file.hasUnstagedChanges = NO;
		}
	}

	// Do new files only if necessary
	if (![[dictionary allKeys] count])
		return;

	// All entries left in the dictionary haven't been accounted for
	// above, so we need to add them to the "files" array
	[self willChangeValueForKey:@"indexChanges"];
	for (NSString *path in [dictionary allKeys]) {
		NSArray *fileStatus = [dictionary objectForKey:path];

		PBChangedFile *file = [[PBChangedFile alloc] initWithPath:path];
		if ([[fileStatus objectAtIndex:4] isEqualToString:@"D"])
			file.status = PBChangedFileStatusDeleted;
		else if([[fileStatus objectAtIndex:0] isEqualToString:@":000000"])
			file.status = PBChangedFileStatusUntracked;
		else
			file.status = PBChangedFileStatusModified;

		if (tracked) {
			file.commitBlobMode = [[fileStatus objectAtIndex:0] substringFromIndex:1];
			file.commitBlobSHA = [fileStatus objectAtIndex:2];
		}

		file.hasStagedChanges = staged;
		file.hasUnstagedChanges = !staged;

		[self.files addObject:file];
	}
	[self didChangeValueForKey:@"indexChanges"];
}

# pragma mark Utility methods
- (NSArray *)linesFromData:(NSData *)data
{
	if (!data)
		return [NSArray array];

	NSString *string = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	// FIXME: throw an error?
	if (!string)
		return [NSArray array];

	// Strip trailing null
	if ([string hasSuffix:@"\0"])
		string = [string substringToIndex:[string length]-1];

	if ([string length] == 0)
		return [NSArray array];

	return [string componentsSeparatedByString:@"\0"];
}

- (NSMutableDictionary *)dictionaryForLines:(NSArray *)lines
{
	NSMutableDictionary *dictionary = [NSMutableDictionary dictionaryWithCapacity:[lines count]/2];
	
	// Fill the dictionary with the new information. These lines are in the form of:
	// :00000 :0644 OTHER INDEX INFORMATION
	// Filename

	NSAssert1([lines count] % 2 == 0, @"Lines must have an even number of lines: %@", lines);

	NSEnumerator *enumerator = [lines objectEnumerator];
	NSString *fileStatus;
	while (fileStatus = [enumerator nextObject]) {
		NSString *fileName = [enumerator nextObject];
		[dictionary setObject:[fileStatus componentsSeparatedByString:@" "] forKey:fileName];
	}

	return dictionary;
}

@end
