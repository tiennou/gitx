//
//  PBChangedFile.m
//  GitX
//
//  Created by Pieter de Bie on 22-09-08.
//  Copyright 2008 __MyCompanyName__. All rights reserved.
//

#import "PBChangedFile.h"

NSString *PBStringFromFileStatus(PBChangedFileStatus status)
{
	NSArray *statii = @[@"UNTRACKED", @"MODIFIED", @"DELETED"];
	return statii[status];
}

@implementation PBChangedFile

- (instancetype)initWithPath:(NSString *)p
{
    self = [super init];
	if (!self) return nil;

	_path = p;

	return self;
}

- (NSString *)description
{
	return _path;
}

- (NSString *)debugDescription
{
	return [NSString stringWithFormat:@"<%@:%p path: %@, status: %@, u: %@, s: %@>", NSStringFromClass(self.class), self, self.path, PBStringFromFileStatus(self.status), @(self.hasUnstagedChanges), @(self.hasStagedChanges)];
}

- (NSString *)indexInfo
{
	NSAssert(self.isUntracked || self.commitBlobSHA, @"File is not new, but doesn't have an index entry!");
	if (!self.commitBlobSHA)
		return [NSString stringWithFormat:@"0 0000000000000000000000000000000000000000\t%@\0", self.path];
	else
		return [NSString stringWithFormat:@"%@ %@\t%@\0", self.commitBlobMode, self.commitBlobSHA, self.path];
}

- (NSImage *)icon
{
	NSString *filename;
	switch (_status) {
		case PBChangedFileStatusUntracked:
			filename = @"new_file";
			break;
		case PBChangedFileStatusDeleted:
			filename = @"deleted_file";
			break;
		default:
			filename = @"empty_file";
			break;
	}
	return [NSImage imageNamed:filename];
}

+ (BOOL)isSelectorExcludedFromWebScript:(SEL)aSelector
{
	return NO;
}

+ (BOOL)isKeyExcludedFromWebScript:(const char *)name
{
	return NO;
}

@end
