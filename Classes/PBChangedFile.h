//
//  PBChangedFile.h
//  GitX
//
//  Created by Pieter de Bie on 22-09-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import <Cocoa/Cocoa.h>

typedef enum {
	PBChangedFileStatusUntracked,
	PBChangedFileStatusModified,
	PBChangedFileStatusDeleted
} PBChangedFileStatus;

NS_ASSUME_NONNULL_BEGIN

@interface PBChangedFile : NSObject

@property (copy) NSString *path;
@property (copy) NSString *commitBlobSHA;
@property (copy) NSString *commitBlobMode;
@property (assign) PBChangedFileStatus status;
@property (assign) BOOL hasStagedChanges;
@property (assign) BOOL hasUnstagedChanges;
@property (assign, getter=isUntracked) BOOL untracked;

- (instancetype)initWithPath:(NSString *)p;

- (NSImage *)icon;
- (NSString *)indexInfo;
@end

NS_ASSUME_NONNULL_END
