//
//  Line.m
//  Writer / Beat
//
//  Created by Hendrik Noeller on 01.04.16.
//  Copyright © 2016 Hendrik Noeller. All rights reserved.
//  Parts copyright © 2019-2020 KAPITAN! / Lauri-Matti Parppei. All Rights reserved.

//  Heavily modified for Beat

#import "Line.h"
#import "RegExCategories.h"
#import "FountainRegexes.h"

#define FORMATTING_CHARACTERS @[@"/*", @"*/", @"*", @"_", @"[[", @"]]"]

#define ITALIC_PATTERN @"*"
#define BOLD_PATTERN @"**"
#define UNDERLINE_PATTERN @"_"

@implementation Line

+ (Line*)withString:(NSString*)string type:(LineType)type {
	return [[Line alloc] initWithString:string type:type];
}
+ (Line*)withString:(NSString*)string type:(LineType)type pageSplit:(bool)pageSplit {
	return [[Line alloc] initWithString:string type:type pageSplit:YES];
}
+ (NSArray*)markupCharacters {
	return @[@".", @"@", @"~", @"!"];
}
- (Line*)clone {
	Line* newLine = [Line withString:self.string type:self.type];
	newLine.position = self.position;
	
	newLine.isSplitParagraph = self.isSplitParagraph;
	newLine.numberOfPreceedingFormattingCharacters = self.numberOfPreceedingFormattingCharacters;
	
	if (self.italicRanges.count) newLine.italicRanges = [self.italicRanges copy];
	if (self.boldRanges.count) newLine.boldRanges = [self.boldRanges copy];
	if (self.noteRanges.count) newLine.noteRanges = [self.noteRanges copy];
	if (self.omitedRanges.count) newLine.omitedRanges = [self.omitedRanges copy];
	if (self.sceneNumber) newLine.sceneNumber = [NSString stringWithString:self.sceneNumber];
	if (self.color) newLine.color = [NSString stringWithString:self.color];
	
	return newLine;
}

- (Line*)initWithString:(NSString*)string position:(NSUInteger)position
{
    self = [super init];
    if (self) {
        _string = string;
        _type = 0;
        _position = position;
    }
    return self;
}

// For non-continuous parsing
- (Line*)initWithString:(NSString *)string type:(LineType)type {
	self = [super init];
	if (self) {
		_string = string;
		_type = type;
	}
	return self;
}
- (Line*)initWithString:(NSString *)string type:(LineType)type pageSplit:(bool)pageSplit {
	self = [super init];
	if (self) {
		_string = string;
		_type = type;
		_unsafeForPageBreak = YES;
	}
	return self;
}
- (Line*)initWithString:(NSString *)string type:(LineType)type position:(NSUInteger)position {
	self = [super init];
	if (self) {
		_string = string;
		_type = type;
		_position = position;
	}
	return self;
}


- (NSString *)toString
{
    return [[[[self typeAsString] stringByAppendingString:@": \"" ] stringByAppendingString:self.string] stringByAppendingString:@"\""];
}

// See if whole block is omited
// Btw, this is me writing from the future. I love you, past me!!!
- (bool)omited {
	__block NSUInteger omitLength = 0;
	[self.omitedRanges enumerateRangesUsingBlock:^(NSRange range, BOOL * _Nonnull stop) {
		omitLength += range.length;
	}];
	
	// Also take notes into account here
	__block NSUInteger noteLength = 0;
	[self.noteRanges enumerateRangesUsingBlock:^(NSRange range, BOOL * _Nonnull stop) {
		noteLength += range.length;
	}];
	
	// This returns YES also for empty lines, which SHOULD NOT be a problem for anything, but yeah, we could check it:
	//if (omitLength == [self.string length] && self.type != empty) {
	if (omitLength + noteLength >= [self.string length]) {
		return true;
	} else {
		return false;
	}
}

- (bool)note {
	// This should be used only in conjuction with .omited to check that, yeah, it's omited but it's a note:
	// if (line.omited && !line.note) ...
	if (self.string.length >= 2) {
		if ([[self.string substringWithRange:NSMakeRange(0, 2)] isEqualToString:@"[["]) return YES;
		else return NO;
	} else {
		return NO;
	}
}

- (bool)centered {
	if (self.string.length < 2) return NO;

	if ([self.string characterAtIndex:0] == '>' &&
		[self.string characterAtIndex:self.string.length - 1] == '<') return YES;
	else return NO;
}

+ (NSString*)removeMarkUpFrom:(NSString*)rawString line:(Line*)line {
	NSMutableString *string = [NSMutableString stringWithString:rawString];
	
	if (string.length > 0 && line.numberOfPreceedingFormattingCharacters > 0 && line.type != centered) {
		if (line.type == character) [string setString:[string replace:RX(@"^@") with:@""]];
		else if (line.type == heading) [string setString:[string replace:RX(@"^\\.") with:@""]];
		else if (line.type == action) [string setString:[string replace:RX(@"^!") with:@""]];
		else if (line.type == lyrics) [string setString:[string replace:RX(@"^~") with:@""]];
		else if (line.type == section) [string setString:[string replace:RX(@"^#") with:@""]];
		else if (line.type == synopse) [string setString:[string replace:RX(@"^=") with:@""]];
		else if (line.type == transitionLine) [string setString:[string replace:RX(@"^>") with:@""]];
	}

	if (line.type == centered) {
		// Let's not clean any formatting characters in case they are cleaned already.
		if (line.string.length > 0 && [string characterAtIndex:0] == '>') {
			string = [NSMutableString stringWithString:[string substringFromIndex:1]];
			string = [NSMutableString stringWithString:[string substringToIndex:string.length - 1]];
		}
	}
	
	// Clean up scene headings
	// Note that the scene number can still be read from the element itself (.sceneNumber) when needed.
	if (line.type == heading && line.sceneNumber) {
		[string replaceOccurrencesOfString:[NSString stringWithFormat:@"#%@#", line.sceneNumber] withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, string.length)];
	}
	
	
	return string;
}

- (NSString*)cleanedString {
	// Return empty string for invisible blocks
	if (self.type == section || self.type == synopse || self.omited) return @"";
		
	NSMutableString *string = [NSMutableString stringWithString:[Line removeMarkUpFrom:[self stripInvisible] line:self]];
	
	return string;
}
- (NSString*)stringForDisplay {
	NSString *string = [Line removeMarkUpFrom:[self stripInvisible] line:self];
	return [string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];

}

- (NSString*)stripFormattingCharacters {
	NSMutableString *string = [NSMutableString stringWithString:self.string];

	// Remove force characters
	if (string.length > 0 && self.numberOfPreceedingFormattingCharacters > 0 && self.type != centered) {
		if (self.type == character) [string setString:[string replace:RX(@"^@") with:@""]];
		else if (self.type == heading) [string setString:[string replace:RX(@"^\\.") with:@""]];
 		else if (self.type == action) [string setString:[string replace:RX(@"^!") with:@""]];
		else if (self.type == lyrics) [string setString:[string replace:RX(@"^~") with:@""]];
		else if (self.type == transitionLine) [string setString:[string replace:RX(@"^>") with:@""]];
		else {
			if (self.numberOfPreceedingFormattingCharacters > 0 && self.string.length >= self.numberOfPreceedingFormattingCharacters) {
				[string setString:[string substringFromIndex:self.numberOfPreceedingFormattingCharacters]];
			}
		}
	}
	
	// Replace formatting characters
	for (NSString* formattingCharacters in FORMATTING_CHARACTERS) {
		[string setString:[string stringByReplacingOccurrencesOfString:formattingCharacters withString:@""]];
	}

	return string;
}
- (NSString*)stripInvisible {
	__block NSMutableString *string = [NSMutableString stringWithString:self.string];
	__block NSUInteger offset = 0;
	
	// To remove any omitted ranges, we need to combine the index sets
	NSMutableIndexSet *indexes = [NSMutableIndexSet indexSet];
	[indexes addIndexes:self.omitedRanges];
	[indexes addIndexes:self.noteRanges];
	
	[indexes enumerateRangesUsingBlock:^(NSRange range, BOOL * _Nonnull stop) {
		if (range.location - offset + range.length > string.length) {
			range = NSMakeRange(range.location, string.length - range.location - offset);
		}
		
		@try {
			[string replaceCharactersInRange:NSMakeRange(range.location - offset, range.length) withString:@""];
		}
		@catch (NSException* exception) {
			NSLog(@"cleaning out of range: %@ / (%lu, %lu) / offset %lu", self.string, range.location, range.length, offset);
		}
		@finally {
			offset += range.length;
		}
	}];
	
	return string;
}
- (NSString*)stripNotes {
	__block NSMutableString *string = [NSMutableString stringWithString:self.string];
	__block NSUInteger offset = 0;
	
	[self.noteRanges enumerateRangesUsingBlock:^(NSRange range, BOOL * _Nonnull stop) {
		if (range.location - offset + range.length > string.length) {
			range = NSMakeRange(range.location, string.length - range.location - offset);
		}
		
		@try {
			[string replaceCharactersInRange:NSMakeRange(range.location - offset, range.length) withString:@""];
		}
		@catch (NSException* exception) {
			NSLog(@"cleaning out of range: %@ / (%lu, %lu) / offset %lu", self.string, range.location, range.length, offset);
		}
		@finally {
			offset += range.length;
		}
	}];
	
	return string;
}

- (NSString*)stripSceneNumber {
	NSString *result = [self.string stringByReplacingOccurrencesOfString:[NSString stringWithFormat:@"#%@#", self.sceneNumber] withString:@"" options:NSCaseInsensitiveSearch range:NSMakeRange(0, self.string.length)];
	return [result stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
}
 
- (NSString*)typeAsString
{
    switch (self.type) {
        case empty:
            return @"Empty";
        case section:
            return @"Section";
        case synopse:
            return @"Synopse";
        case titlePageTitle:
            return @"Title Page Title";
        case titlePageAuthor:
            return @"Title Page Author";
        case titlePageCredit:
            return @"Title Page Credit";
        case titlePageSource:
            return @"Title Page Source";
        case titlePageContact:
            return @"Title Page Contact";
        case titlePageDraftDate:
            return @"Title Page Draft Date";
        case titlePageUnknown:
            return @"Title Page Unknown";
        case heading:
            return @"Heading";
        case action:
            return @"Action";
        case character:
            return @"Character";
        case parenthetical:
            return @"Parenthetical";
        case dialogue:
            return @"Dialogue";
        case dualDialogueCharacter:
            return @"DD Character";
        case dualDialogueParenthetical:
            return @"DD Parenthetical";
        case dualDialogue:
            return @"Double Dialogue";
        case transitionLine:
            return @"Transition";
        case lyrics:
            return @"Lyrics";
        case pageBreak:
            return @"Page Break";
        case centered:
            return @"Centered";
		case more:
			return @"More";
    }
}

- (bool)isTitlePage {
	if (self.type == titlePageTitle ||
		self.type == titlePageCredit ||
		self.type == titlePageAuthor ||
		self.type == titlePageDraftDate ||
		self.type == titlePageContact ||
		self.type == titlePageSource ||
		self.type == titlePageUnknown) return YES;
	else return NO;
}
- (bool)isInvisible {
	if (self.omited ||
		self.type == section ||
		self.type == synopse ||
		self.isTitlePage) return YES;
	else return NO;
}
-(bool)isBoldedAt:(NSInteger)index {
	__block bool inRange = NO;
	[self.boldRanges enumerateRangesUsingBlock:^(NSRange range, BOOL * _Nonnull stop) {
		if (NSLocationInRange(index, range)) inRange = YES;
	}];
	
	return inRange;
}
-(bool)isItalicAt:(NSInteger)index {
	__block bool inRange = NO;
	[self.italicRanges enumerateRangesUsingBlock:^(NSRange range, BOOL * _Nonnull stop) {
		if (NSLocationInRange(index, range)) inRange = YES;
	}];
	
	return inRange;
}

-(bool)isUnderlinedAt:(NSInteger)index {
	__block bool inRange = NO;
	[self.underlinedRanges enumerateRangesUsingBlock:^(NSRange range, BOOL * _Nonnull stop) {
		if (NSLocationInRange(index, range)) inRange = YES;
	}];
	
	return inRange;
}

-(NSRange)range {
	return NSMakeRange(self.position, self.string.length + 1);
}

- (NSString*)typeAsFountainString
{
	// This returns the type as an FNElement compliant string,
	// for convoluted backwards compatibility reasons :----)

	switch (self.type) {
        case empty:
            return @"Empty";
        case section:
            return @"Section";
        case synopse:
            return @"Synopse";
        case titlePageTitle:
            return @"Title Page Title";
        case titlePageAuthor:
            return @"Title Page Author";
        case titlePageCredit:
            return @"Title Page Credit";
        case titlePageSource:
            return @"Title Page Source";
        case titlePageContact:
            return @"Title Page Contact";
        case titlePageDraftDate:
            return @"Title Page Draft Date";
        case titlePageUnknown:
            return @"Title Page Unknown";
        case heading:
            return @"Scene Heading";
        case action:
            return @"Action";
        case character:
            return @"Character";
        case parenthetical:
            return @"Parenthetical";
        case dialogue:
            return @"Dialogue";
        case dualDialogueCharacter:
            return @"Character";
        case dualDialogueParenthetical:
            return @"Parenthetical";
        case dualDialogue:
            return @"Dialogue";
        case transitionLine:
            return @"Transition";
        case lyrics:
            return @"Lyrics";
        case pageBreak:
            return @"Page Break";
        case centered:
            return @"Centered";
		case more:
			return @"More";
    }
}
- (bool)isDialogueElement {
	if (self.type == parenthetical || self.type == dialogue) return YES;
	else return NO;
}
- (bool)isDualDialogueElement {
	if (self.type == dualDialogueParenthetical || self.type == dualDialogue) return YES;
	else return NO;
}

@end
