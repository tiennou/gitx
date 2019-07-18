//
//  PBGitIndex.h
//  GitX
//
//  Created by Pieter de Bie on 9/12/09.
//  Copyright 2009 Pieter de Bie. All rights reserved.
//

#import <Cocoa/Cocoa.h>

@class PBGitRepository;
@class PBChangedFile;

NS_ASSUME_NONNULL_BEGIN

/*
 * Notifications this class will send
 */

// The "indexChanges" array has changed
extern NSString *PBGitIndexIndexUpdated;

// Changing to amend
extern NSString *PBGitIndexAmendMessageAvailable;

// Represents a git index for a given work tree.
// As a single git repository can have multiple trees,
// the tree has to be given explicitly, even though
// multiple trees is not yet supported in GitX
@interface PBGitIndex : NSObject

// Whether we want the changes for amending,
// or for making a new commit.
@property (assign, getter=isAmend) BOOL amend;
@property (weak, readonly) PBGitRepository *repository;

// A list of PBChangedFile's with differences between the work tree and the index
// This method is KVO-aware, so changes when any of the index-modifying methods are called
// (including -refresh)
@property (readonly, retain) NSArray <PBChangedFile *> *indexChanges;

- (instancetype)initWithRepository:(PBGitRepository *)repository;

// Refresh the index
- (void)refresh:(nullable void (^)(NSError *error))completionHandler;

- (void)performCommitWithMessage:(NSString *)commitMessage force:(BOOL)force progressHandler:(void (^)(NSString *))progressHandler completionHandler:(void (^)(NSError *error, GTOID *oid))completionHandler;

// Inter-file changes:
- (BOOL)stageFiles:(NSArray<PBChangedFile *> *)stageFiles error:(NSError **)error;
- (BOOL)unstageFiles:(NSArray<PBChangedFile *> *)unstageFiles error:(NSError **)error;
- (BOOL)discardChangesForFiles:(NSArray<PBChangedFile *> *)discardFiles error:(NSError **)error;

// Intra-file changes
- (BOOL)applyPatch:(NSString *)hunk stage:(BOOL)stage reverse:(BOOL)reverse error:(NSError **)error;
- (NSString *)diffForFile:(PBChangedFile *)file staged:(BOOL)staged contextLines:(NSUInteger)context error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
