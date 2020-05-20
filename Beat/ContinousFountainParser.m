//
//  ContinousFountainParser.m
//  Writer / Beat
//
//  Copyright © 2016 Hendrik Noeller. All rights reserved.
//  Parts copyright © 2019-2020 Lauri-Matti Parppei. All rights reserved.

//  Relased under GPL

/*
 
 This code is mostly based on Hendrik Noeller's work. It is heavily modified for Beat, and is all the time more reliable.
 
 Main differences include:
 - double-checking for all-caps actions mistaken for character cues
 - recursive logic for lookback / lookforward
 - title page parsing (mostly for preview purposes)
 - new data structure called OutlineScene, which contains scene name and length, as well as a reference to original line
 - overall tweaks to parsing here and there
 
 */

#import "ContinousFountainParser.h"
#import "Line.h"
#import "NSString+Whitespace.h"
#import "NSMutableIndexSet+Lowest.h"
#import "OutlineScene.h"

@interface  ContinousFountainParser ()
@property (nonatomic) BOOL changeInOutline;
@end

@implementation ContinousFountainParser

#pragma mark - Parsing

#pragma mark Bulk Parsing

- (ContinousFountainParser*)initWithString:(NSString*)string
{
    self = [super init];
    
    if (self) {
        _lines = [[NSMutableArray alloc] init];
		_outline = [[NSMutableArray alloc] init];
        _changedIndices = [[NSMutableArray alloc] init];
		_titlePage = [[NSMutableArray alloc] init];
		
        [self parseText:string];
    }
    
    return self;
}

- (void)parseText:(NSString*)text
{
    NSArray *lines = [text componentsSeparatedByString:@"\n"];
    
    NSUInteger position = 0; //To track at which position every line begins
    
	Line *previousLine;
	
    for (NSString *rawLine in lines) {
        NSInteger index = [self.lines count];
        Line* line = [[Line alloc] initWithString:rawLine position:position];
        [self parseTypeAndFormattingForLine:line atIndex:index];
        
		// Quick fix for mistaking an ALL CAPS action to character cue
		if (previousLine.type == character && (line.string.length < 1 || line.type == empty)) {
			previousLine.type = [self parseLineType:previousLine atIndex:index - 1 recursive:NO currentlyEditing:NO];
			if (previousLine.type == character) previousLine.type = action;
		}
		
        //Add to lines array
        [self.lines addObject:line];
        //Mark change in buffered changes
        [self.changedIndices addObject:@(index)];
        
        position += [rawLine length] + 1; // +1 for newline character
		previousLine = line;
    }
    _changeInOutline = YES;
}

// This sets EVERY INDICE as changed.
// Used to perform lookback when loading a screenplay.
- (void)resetParsing {
	NSInteger index = 0;
	while (index < [self.lines count]) {
		[self.changedIndices addObject:@(index)];
		index++;
	}
}

#pragma mark Continuous Parsing

- (void)parseChangeInRange:(NSRange)range withString:(NSString*)string
{
    NSMutableIndexSet *changedIndices = [[NSMutableIndexSet alloc] init];
    if (range.length == 0) { //Addition
        for (int i = 0; i < string.length; i++) {
            NSString* character = [string substringWithRange:NSMakeRange(i, 1)];
            [changedIndices addIndexes:[self parseCharacterAdded:character
                                                      atPosition:range.location+i]];
        }
    } else if ([string length] == 0) { //Removal
        for (int i = 0; i < range.length; i++) {
            [changedIndices addIndexes:[self parseCharacterRemovedAtPosition:range.location]];
        }
    } else { //Replacement
//        [self parseChangeInRange:range withString:@""];
        //First remove
        for (int i = 0; i < range.length; i++) {
            [changedIndices addIndexes:[self parseCharacterRemovedAtPosition:range.location]];
        }
//        [self parseChangeInRange:NSMakeRange(range.location, 0)
//                      withString:string];
        // Then add
        for (int i = 0; i < string.length; i++) {
            NSString* character = [string substringWithRange:NSMakeRange(i, 1)];
            [changedIndices addIndexes:[self parseCharacterAdded:character
                                                      atPosition:range.location+i]];
        }
    }
    
    [self correctParsesInLines:changedIndices];
}

- (NSIndexSet*)parseCharacterAdded:(NSString*)character atPosition:(NSUInteger)position
{
    NSUInteger lineIndex = [self lineIndexAtPosition:position];
    Line* line = self.lines[lineIndex];
    NSUInteger indexInLine = position - line.position;
	
	if (line.type == heading || line.type == synopse || line.type == section) _changeInOutline = true;
	
    if ([character isEqualToString:@"\n"]) {
        NSString* cutOffString;
        if (indexInLine == [line.string length]) {
            cutOffString = @"";
        } else {
            cutOffString = [line.string substringFromIndex:indexInLine];
            line.string = [line.string substringToIndex:indexInLine];
        }
        
        Line* newLine = [[Line alloc] initWithString:cutOffString
                                            position:position+1];
        [self.lines insertObject:newLine atIndex:lineIndex+1];
        
        [self incrementLinePositionsFromIndex:lineIndex+2 amount:1];
        
        return [NSIndexSet indexSetWithIndexesInRange:NSMakeRange(lineIndex, 2)];
    } else {   
        NSArray* pieces = @[[line.string substringToIndex:indexInLine],
                            character,
                            [line.string substringFromIndex:indexInLine]];
        
        line.string = [pieces componentsJoinedByString:@""];
        [self incrementLinePositionsFromIndex:lineIndex+1 amount:1];
        
        return [[NSIndexSet alloc] initWithIndex:lineIndex];
        
    }
}

- (NSIndexSet*)parseCharacterRemovedAtPosition:(NSUInteger)position
{
    NSUInteger lineIndex = [self lineIndexAtPosition:position];
    Line* line = self.lines[lineIndex];
    NSUInteger indexInLine = position - line.position;
    
    if (indexInLine == [line.string length]) {
        //Get next line an put together
        if (lineIndex == [self.lines count] - 1) {
            return nil; //Removed newline at end of document without there being an empty line - should never happen but be sure...
        }
        Line* nextLine = self.lines[lineIndex+1];
        line.string = [line.string stringByAppendingString:nextLine.string];
        if (nextLine.type == heading || nextLine.type == section || nextLine.type == synopse) {
            _changeInOutline = YES;
        }
        [self.lines removeObjectAtIndex:lineIndex+1];
        [self decrementLinePositionsFromIndex:lineIndex+1 amount:1];
        
        return [[NSIndexSet alloc] initWithIndex:lineIndex];
    } else {
        NSArray* pieces = @[[line.string substringToIndex:indexInLine],
                            [line.string substringFromIndex:indexInLine+1]];
        
        line.string = [pieces componentsJoinedByString:@""];
        [self decrementLinePositionsFromIndex:lineIndex+1 amount:1];
        
        
        return [[NSIndexSet alloc] initWithIndex:lineIndex];
    }
}

- (NSUInteger)lineIndexAtPosition:(NSUInteger)position
{
    for (int i = 0; i < [self.lines count]; i++) {
        Line* line = self.lines[i];
        
        if (line.position > position) {
            return i-1;
        }
    }
    return [self.lines count] - 1;
}

- (void)incrementLinePositionsFromIndex:(NSUInteger)index amount:(NSUInteger)amount
{
    for (; index < [self.lines count]; index++) {
        Line* line = self.lines[index];
        
        line.position += amount;
    }
}

- (void)decrementLinePositionsFromIndex:(NSUInteger)index amount:(NSUInteger)amount
{
    for (; index < [self.lines count]; index++) {
        Line* line = self.lines[index];
        
        line.position -= amount;
    }
}

- (void)correctParsesInLines:(NSMutableIndexSet*)lineIndices
{
    while ([lineIndices count] > 0) {
        [self correctParseInLine:[lineIndices lowestIndex] indicesToDo:lineIndices];
    }
}

- (void)correctParseInLine:(NSUInteger)index indicesToDo:(NSMutableIndexSet*)indices
{
    //Remove index as done from array if in array
    if ([indices count]) {
        NSUInteger lowestToDo = [indices lowestIndex];
        if (lowestToDo == index) {
            [indices removeIndex:index];
        }
    }
    
    //Correct type on this line
    Line* currentLine = self.lines[index];
    LineType oldType = currentLine.type;
    bool oldOmitOut = currentLine.omitOut;
    [self parseTypeAndFormattingForLine:currentLine atIndex:index];
    
    if (!self.changeInOutline && (oldType == heading || oldType == section || oldType == synopse ||
        currentLine.type == heading || currentLine.type == section || currentLine.type == synopse)) {
        self.changeInOutline = YES;
    }
    
    [self.changedIndices addObject:@(index)];
    
    if (oldType != currentLine.type || oldOmitOut != currentLine.omitOut) {
        //If there is a next element, check if it might need a reparse because of a change in type or omit out
        if (index < [self.lines count] - 1) {
            Line* nextLine = self.lines[index+1];
            if (currentLine.type == titlePageTitle ||       //if the line became a title page,
                currentLine.type == titlePageCredit ||      //it may cause the next one to be
                currentLine.type == titlePageAuthor ||      //a title page
                currentLine.type == titlePageDraftDate ||
                currentLine.type == titlePageContact ||
                currentLine.type == titlePageSource ||
                currentLine.type == titlePageUnknown ||
                currentLine.type == section ||
                currentLine.type == synopse ||
                currentLine.type == character ||            //if the line became anythign to
                currentLine.type == parenthetical ||        //do with dialogue, it might cause
                currentLine.type == dialogue ||             //the next lines to be dialogue
                currentLine.type == dualDialogueCharacter ||
                currentLine.type == dualDialogueParenthetical ||
                currentLine.type == dualDialogue ||
                currentLine.type == empty ||                //If the line became empty, it might
                                                            //enable the next on to be a heading
                                                            //or character
                
                nextLine.type == titlePageTitle ||          //if the next line is a title page,
                nextLine.type == titlePageCredit ||         //it might not be anymore
                nextLine.type == titlePageAuthor ||
                nextLine.type == titlePageDraftDate ||
                nextLine.type == titlePageContact ||
                nextLine.type == titlePageSource ||
                nextLine.type == titlePageUnknown ||
                nextLine.type == section ||
                nextLine.type == synopse ||
                nextLine.type == heading ||                 //If the next line is a heading or
                nextLine.type == character ||               //character or anything dialogue
                nextLine.type == dualDialogueCharacter || //related, it might not be anymore
                nextLine.type == parenthetical ||
                nextLine.type == dialogue ||
                nextLine.type == dualDialogueParenthetical ||
                nextLine.type == dualDialogue ||
                nextLine.omitIn != currentLine.omitOut) { //If the next line expected the end
                                                            //of the last line to end or not end
                                                            //with an open omit other than the
                                                            //line actually does, omites changed
                
                [self correctParseInLine:index+1 indicesToDo:indices];
            }
        }
    }
}


#pragma mark Parsing Core

#define BOLD_PATTERN "**"
#define ITALIC_PATTERN "*"
#define UNDERLINE_PATTERN "_"
#define NOTE_OPEN_PATTERN "[["
#define NOTE_CLOSE_PATTERN "]]"
#define OMIT_OPEN_PATTERN "/*"
#define OMIT_CLOSE_PATTERN "*/"

#define BOLD_PATTERN_LENGTH 2
#define ITALIC_PATTERN_LENGTH 1
#define UNDERLINE_PATTERN_LENGTH 1
#define NOTE_PATTERN_LENGTH 2
#define OMIT_PATTERN_LENGTH 2

#define COLOR_PATTERN "color"
#define STORYLINE_PATTERN "storyline"

- (void)parseTypeAndFormattingForLine:(Line*)line atIndex:(NSUInteger)index
{
    line.type = [self parseLineType:line atIndex:index];
    
    NSUInteger length = line.string.length;
    unichar charArray[length];
    [line.string getCharacters:charArray];
    
    NSMutableIndexSet* starsInOmit = [[NSMutableIndexSet alloc] init];
    if (index == 0) {
        line.omitedRanges = [self rangesOfOmitChars:charArray
                                             ofLength:length
                                               inLine:line
                                     lastLineOmitOut:NO
                                          saveStarsIn:starsInOmit];
    } else {
        Line* previousLine = self.lines[index-1];
        line.omitedRanges = [self rangesOfOmitChars:charArray
                                             ofLength:length
                                               inLine:line
                                     lastLineOmitOut:previousLine.omitOut
                                          saveStarsIn:starsInOmit];
    }
    
    line.boldRanges = [self rangesInChars:charArray
                                 ofLength:length
                                  between:BOLD_PATTERN
                                      and:BOLD_PATTERN
                               withLength:BOLD_PATTERN_LENGTH
                         excludingIndices:starsInOmit];
    line.italicRanges = [self rangesInChars:charArray
                                   ofLength:length
                                    between:ITALIC_PATTERN
                                        and:ITALIC_PATTERN
                                 withLength:ITALIC_PATTERN_LENGTH
                           excludingIndices:starsInOmit];
    line.underlinedRanges = [self rangesInChars:charArray
                                       ofLength:length
                                        between:UNDERLINE_PATTERN
                                            and:UNDERLINE_PATTERN
                                     withLength:UNDERLINE_PATTERN_LENGTH
                               excludingIndices:nil];
    line.noteRanges = [self rangesInChars:charArray
                                 ofLength:length
                                  between:NOTE_OPEN_PATTERN
                                      and:NOTE_CLOSE_PATTERN
                               withLength:NOTE_PATTERN_LENGTH
                         excludingIndices:nil];
	
    if (line.type == heading) {
		NSRange sceneNumberRange = [self sceneNumberForChars:charArray ofLength:length];
        if (sceneNumberRange.length == 0) {
            line.sceneNumber = nil;
        } else {
            line.sceneNumber = [line.string substringWithRange:sceneNumberRange];
        }
		
		line.color = [self colorForHeading:line];
    }	
}

- (LineType)parseLineType:(Line*)line atIndex:(NSUInteger)index
{
	return [self parseLineType:line atIndex:index recursive:NO currentlyEditing:NO];
}

- (LineType)parseLineType:(Line*)line atIndex:(NSUInteger)index recursive:(bool)recursive
{
	return [self parseLineType:line atIndex:index recursive:recursive currentlyEditing:NO];
}

- (LineType)parseLineType:(Line*)line atIndex:(NSUInteger)index currentlyEditing:(bool)currentLine {
	return [self parseLineType:line atIndex:index recursive:NO currentlyEditing:currentLine];
}

- (LineType)parseLineType:(Line*)line atIndex:(NSUInteger)index recursive:(bool)recursive currentlyEditing:(bool)currentLine
{
    NSString* string = line.string;
    NSUInteger length = [string length];
	
	// So we need to pull all sorts of tricks out of our sleeve here. Usually Fountain files are parsed from bottom to up, but here we are parsing in a linear manner. That's why we need some extra pointers, which kinda sucks.
	// I have no idea how I got this to work but it does.
	
    // Check if empty.
    if (length == 0) {
		// If previous line is part of dialogue block, this line becomes dialogue right away
		// Else it's just empty.
		Line* preceedingLine = (index == 0) ? nil : (Line*) self.lines[index-1];
		
		if (preceedingLine.type == character || preceedingLine.type == parenthetical || preceedingLine.type == dialogue) {
			
			// If preceeding line is formatted as dialogue BUT it's empty, we'll just return empty. OMG IT WORKS!
			if ([preceedingLine.string length] > 0) {
				// If preceeded by character cue, return dialogue
				if (preceedingLine.type == character) return dialogue;
				// If its a parenthetical line, return dialogue
				else if (preceedingLine.type == parenthetical) return dialogue;
				// AND if its just dialogue, return action.
				else return action;
			} else {
				return empty;
			}
		} else {
			return empty;
		}
    }
	
    char firstChar = [string characterAtIndex:0];
    char lastChar = [string characterAtIndex:length-1];
    
    bool containsOnlyWhitespace = [string containsOnlyWhitespace]; //Save to use again later
    bool twoSpaces = (length == 2 && firstChar == ' ' && lastChar == ' ');
    //If not empty, check if contains only whitespace. Exception: two spaces indicate a continued whatever, so keep them
    if (containsOnlyWhitespace && !twoSpaces) {
        return empty;
    }
    
    //Check for forces (the first character can force a line type)
    if (firstChar == '!') {
        line.numberOfPreceedingFormattingCharacters = 1;
        return action;
    }
    if (firstChar == '@') {
        line.numberOfPreceedingFormattingCharacters = 1;
        return character;
    }
    if (firstChar == '~') {
        line.numberOfPreceedingFormattingCharacters = 1;
        return lyrics;
    }
    if (firstChar == '>' && lastChar != '<') {
        line.numberOfPreceedingFormattingCharacters = 1;
        return transitionLine;
    }
	if (firstChar == '>' && lastChar == '<') {
        //line.numberOfPreceedingFormattingCharacters = 1;
        return centered;
    }
    if (firstChar == '#') {
		// Thanks, Jacob Relkin
		NSUInteger len = [string length];
		NSInteger depth = 0;

		char character;
		for (int c = 0; c < len; c++) {
			character = [string characterAtIndex:c];
			if (character == '#') depth++; else break;
		}
		
		line.sectionDepth = depth;
		line.numberOfPreceedingFormattingCharacters = depth;
        return section;
    }
    if (firstChar == '=' && (length >= 2 ? [string characterAtIndex:1] != '=' : YES)) {
        line.numberOfPreceedingFormattingCharacters = 1;
        return synopse;
    }
	
	// '.' forces a heading. Because our American friends love to shoot their guns like we Finnish people love our booze, screenwriters might start dialogue blocks with such "words" as '.44'
	// So, let's NOT return a scene heading IF the previous line is not empty OR is a character OR is a parenthetical...
    if (firstChar == '.' && length >= 2 && [string characterAtIndex:1] != '.') {
		Line* preceedingLine = (index == 0) ? nil : (Line*) self.lines[index-1];
		if (preceedingLine) {
			if (preceedingLine.type == character) return dialogue;
			if (preceedingLine.type == parenthetical) return dialogue;
			if ([preceedingLine.string length] > 0) return action;
		}
		
		line.numberOfPreceedingFormattingCharacters = 1;
		return heading;
    }
	

	Line* preceedingLine = (index == 0) ? nil : (Line*) self.lines[index-1];
	
    //Check for scene headings (lines beginning with "INT", "EXT", "EST",  "I/E"). "INT./EXT" and "INT/EXT" are also inside the spec, but already covered by "INT".
    if (preceedingLine.type == empty || [preceedingLine.string length] == 0 || line.position == 0) {
        if (length >= 3) {
            NSString* firstChars = [[string substringToIndex:3] lowercaseString];
            if ([firstChars isEqualToString:@"int"] ||
                [firstChars isEqualToString:@"ext"] ||
                [firstChars isEqualToString:@"est"] ||
                [firstChars isEqualToString:@"i/e"]) {
                return heading;
            }
        }
    }
	
	//Check for title page elements. A title page element starts with "Title:", "Credit:", "Author:", "Draft date:" or "Contact:"
	//it has to be either the first line or only be preceeded by title page elements.
	if (!preceedingLine ||
		preceedingLine.type == titlePageTitle ||
		preceedingLine.type == titlePageAuthor ||
		preceedingLine.type == titlePageCredit ||
		preceedingLine.type == titlePageSource ||
		preceedingLine.type == titlePageContact ||
		preceedingLine.type == titlePageDraftDate ||
		preceedingLine.type == titlePageUnknown) {
		
		//Check for title page key: value pairs
		// - search for ":"
		// - extract key
		NSRange firstColonRange = [string rangeOfString:@":"];
		
		if (firstColonRange.length != 0 && firstColonRange.location != 0) {
			NSUInteger firstColonIndex = firstColonRange.location;
			
			NSString* key = [[string substringToIndex:firstColonIndex] lowercaseString];
			
			NSString* value = @"";
			if (string.length > firstColonIndex + 1) value = [string substringFromIndex:firstColonIndex + 1];
			
			// Store title page data
			NSDictionary *titlePageData = @{ key: [NSMutableArray arrayWithObject:value] };
			[_titlePage addObject:titlePageData];
			
			// Set this key as open
			if (value.length < 1) _openTitlePageKey = key; else _openTitlePageKey = nil;
			
			if ([key isEqualToString:@"title"]) {
				return titlePageTitle;
			} else if ([key isEqualToString:@"author"] || [key isEqualToString:@"authors"]) {
				return titlePageAuthor;
			} else if ([key isEqualToString:@"credit"]) {
				return titlePageCredit;
			} else if ([key isEqualToString:@"source"]) {
				return titlePageSource;
			} else if ([key isEqualToString:@"contact"]) {
				return titlePageContact;
			} else if ([key isEqualToString:@"contacts"]) {
				return titlePageContact;
			} else if ([key isEqualToString:@"contact info"]) {
				return titlePageContact;
			} else if ([key isEqualToString:@"draft date"]) {
				return titlePageDraftDate;
			} else {
				return titlePageUnknown;
			}
		} else {
			// This is an additional line
			/*
			 if (length >= 2 && [[string substringToIndex:2] isEqualToString:@"  "]) {
			 line.numberOfPreceedingFormattingCharacters = 2;
			 return preceedingLine.type;
			 } else if (length >= 1 && [[string substringToIndex:1] isEqualToString:@"\t"]) {
			 line.numberOfPreceedingFormattingCharacters = 1;
			 return preceedingLine.type;
			 } */
			if (_openTitlePageKey) {
				NSMutableDictionary* dict = [_titlePage lastObject];
				[(NSMutableArray*)dict[_openTitlePageKey] addObject:line.string];
			}
			
			return preceedingLine.type;
		}
		
	}
	    
    //Check for transitionLines and page breaks
    if (length >= 3) {
        //transitionLine happens if the last three chars are "TO:"
        NSRange lastThreeRange = NSMakeRange(length-3, 3);
        NSString *lastThreeChars = [[string substringWithRange:lastThreeRange] lowercaseString];
        if ([lastThreeChars isEqualToString:@"to:"]) {
            return transitionLine;
        }
        
        //Page breaks start with "==="
        NSString *firstChars;
        if (length == 3) {
            firstChars = lastThreeChars;
        } else {
            firstChars = [string substringToIndex:3];
        }
        if ([firstChars isEqualToString:@"==="]) {
            return pageBreak;
        }
    }
    
    //Check if all uppercase (and at least 3 characters to not indent every capital leter before anything else follows) = character name.
    if (preceedingLine.type == empty || [preceedingLine.string length] == 0) {
        if (length >= 3 && [string containsOnlyUppercase] && !containsOnlyWhitespace) {
            // A character line ending in ^ is a double dialogue character
            if (lastChar == '^') {
				
				// PLEASE NOTE:
				// nextElementIsDualDialogue is ONLY used while staticly parsing for printing,
				// and SHOULD NOT be used anywhere else, as it won't be updated.
				NSUInteger i = index - 1;
				while (i >= 0) {
					Line *prevLine = [self.lines objectAtIndex:i];

					if (prevLine.type == character) {
						prevLine.nextElementIsDualDialogue = YES;
						break;
					}
					if (prevLine.type == heading) break;
					i--;
				}
				
                return dualDialogueCharacter;
            } else {
				// It is possible that this IS NOT A CHARACTER anyway, so let's see.
				// WIP
				
				if (index + 2 < self.lines.count && currentLine) {
					Line* nextLine = (Line*)self.lines[index+1];
					Line* twoLinesOver = (Line*)self.lines[index+2];
					
					if (recursive && [nextLine.string length] == 0 && [twoLinesOver.string length] > 0) {
						return action;
					}
				}
                return character;
            }
        }
    }
    
    //Check for centered text
    if (firstChar == '>' && lastChar == '<') {
        return centered;
    }

    //If it's just usual text, see if it might be (double) dialogue or a parenthetical, or seciton/synopsis
    if (preceedingLine) {
        if (preceedingLine.type == character || preceedingLine.type == dialogue || preceedingLine.type == parenthetical) {
            //Text in parentheses after character or dialogue is a parenthetical, else its dialogue
			if (firstChar == '(' && [preceedingLine.string length] > 0) {
                return parenthetical;
            } else {
				if ([preceedingLine.string length] > 0) {
					return dialogue;
				} else {
					return action;
				}
            }
        } else if (preceedingLine.type == dualDialogueCharacter || preceedingLine.type == dualDialogue || preceedingLine.type == dualDialogueParenthetical) {
            //Text in parentheses after character or dialogue is a parenthetical, else its dialogue
            if (firstChar == '(' && lastChar == ')') {
                return dualDialogueParenthetical;
            } else {
                return dualDialogue;
            }
        } else if (preceedingLine.type == section) {
            return section;
        } else if (preceedingLine.type == synopse) {
            return synopse;
        }
    }
    
    return action;
}

- (NSMutableIndexSet*)rangesInChars:(unichar*)string ofLength:(NSUInteger)length between:(char*)startString and:(char*)endString withLength:(NSUInteger)delimLength excludingIndices:(NSIndexSet*)excludes
{
    NSMutableIndexSet* indexSet = [[NSMutableIndexSet alloc] init];
    
    NSInteger lastIndex = length - delimLength; //Last index to look at if we are looking for start
    NSInteger rangeBegin = -1; //Set to -1 when no range is currently inspected, or the the index of a detected beginning
    
    for (int i = 0;;i++) {
        if (i > lastIndex) break;
        if ([excludes containsIndex:i]) continue;
        if (rangeBegin == -1) {
            bool match = YES;
            for (int j = 0; j < delimLength; j++) {
                if (string[j+i] != startString[j]) {
                    match = NO;
                    break;
                }
            }
            if (match) {
                rangeBegin = i;
                i += delimLength - 1;
            }
        } else {
            bool match = YES;
            for (int j = 0; j < delimLength; j++) {
                if (string[j+i] != endString[j]) {
                    match = NO;
                    break;
                }
            }
            if (match) {
                [indexSet addIndexesInRange:NSMakeRange(rangeBegin, i - rangeBegin + delimLength)];
                rangeBegin = -1;
                i += delimLength - 1;
            }
        }
    }
    return indexSet;
}

- (NSMutableIndexSet*)rangesOfOmitChars:(unichar*)string ofLength:(NSUInteger)length inLine:(Line*)line lastLineOmitOut:(bool)lastLineOut saveStarsIn:(NSMutableIndexSet*)stars
{
    NSMutableIndexSet* indexSet = [[NSMutableIndexSet alloc] init];
    
    NSInteger lastIndex = length - OMIT_PATTERN_LENGTH; //Last index to look at if we are looking for start
    NSInteger rangeBegin = lastLineOut ? 0 : -1; //Set to -1 when no range is currently inspected, or the the index of a detected beginning
    line.omitIn = lastLineOut;
    
    for (int i = 0;;i++) {
        if (i > lastIndex) break;
        if (rangeBegin == -1) {
            bool match = YES;
            for (int j = 0; j < OMIT_PATTERN_LENGTH; j++) {
                if (string[j+i] != OMIT_OPEN_PATTERN[j]) {
                    match = NO;
                    break;
                }
            }
            if (match) {
                rangeBegin = i;
                [stars addIndex:i+1];
            }
        } else {
            bool match = YES;
            for (int j = 0; j < OMIT_PATTERN_LENGTH; j++) {
                if (string[j+i] != OMIT_CLOSE_PATTERN[j]) {
                    match = NO;
                    break;
                }
            }
            if (match) {
                [indexSet addIndexesInRange:NSMakeRange(rangeBegin, i - rangeBegin + OMIT_PATTERN_LENGTH)];
                rangeBegin = -1;
                [stars addIndex:i];
            }
        }
    }
    
    //Terminate any open ranges at the end of the line so that this line is omited untill the end
    if (rangeBegin != -1) {
        NSRange rangeToAdd = NSMakeRange(rangeBegin, length - rangeBegin);
        [indexSet addIndexesInRange:rangeToAdd];
        line.omitOut = YES;
    } else {
        line.omitOut = NO;
    }
    
    return indexSet;
}

- (NSRange)sceneNumberForChars:(unichar*)string ofLength:(NSUInteger)length
{
	// Uh, Beat scene coloring (ie. note ranges) messed this unichar array lookup.
	
    NSUInteger backNumberIndex = NSNotFound;
	int note = 0;
	
    for(NSInteger i = length - 1; i >= 0; i--) {
        char c = string[i];
		
		// Exclude note ranges: [[ Note ]]
		if (c == ' ') continue;
		if (c == ']' && note < 2) { note++; continue; }
		if (c == '[' && note > 0) { note--; continue; }
		
		// Inside a note range
		if (note == 2) continue;
		
        if (backNumberIndex == NSNotFound) {
            if (c == '#') backNumberIndex = i;
            else break;
        } else {
            if (c == '#') {
                return NSMakeRange(i+1, backNumberIndex-i-1);
            }
        }
    }
	
    return NSMakeRange(0, 0);
}

- (NSString *)colorForHeading:(Line *)line
{
	__block NSString *color = @"";
	
	[line.noteRanges enumerateRangesUsingBlock:^(NSRange range, BOOL * _Nonnull stop) {
		NSString * note = [line.string substringWithRange:range];

		NSRange noteRange = NSMakeRange(NOTE_PATTERN_LENGTH, [note length] - NOTE_PATTERN_LENGTH * 2);
		note =  [note substringWithRange:noteRange];
        
		if ([note localizedCaseInsensitiveContainsString:@COLOR_PATTERN] == true) {
			if ([note length] > [@COLOR_PATTERN length] + 1) {
				NSRange colorRange = [note rangeOfString:@COLOR_PATTERN options:NSCaseInsensitiveSearch];
				color = [note substringWithRange:NSMakeRange(colorRange.length, [note length] - colorRange.length)];
				color = [color stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
			}
		}
	}];

	return color;
}




#pragma mark - Data access

- (NSString*)stringAtLine:(NSUInteger)line
{
    if (line >= [self.lines count]) {
        return @"";
    } else {
        Line* l = self.lines[line];
        return l.string;
    }
}

- (LineType)typeAtLine:(NSUInteger)line
{
    if (line >= [self.lines count]) {
        return NSNotFound;
    } else {
        Line* l = self.lines[line];
        return l.type;
    }
}

- (NSUInteger)positionAtLine:(NSUInteger)line
{
    if (line >= [self.lines count]) {
        return NSNotFound;
    } else {
        Line* l = self.lines[line];
        return l.position;
    }
}

- (NSString*)sceneNumberAtLine:(NSUInteger)line
{
    if (line >= [self.lines count]) {
        return nil;
    } else {
        Line* l = self.lines[line];
        return l.sceneNumber;
    }
}


#pragma mark - Outline Dat

- (NSUInteger)numberOfOutlineItems
{
	/*
	// This is the old way. Outline used to be only Line objects.
	 
	NSUInteger result = 0;
	for (Line* line in self.lines) {
		
		if (line.type == section || line.type == synopse || line.type == heading) {
			result++;
		}
	}
	return result;
	 */
	
	[self createOutline];
	return [_outline count];
}

- (OutlineScene*) getOutlineForLine: (Line *) line {
	for (OutlineScene * item in _outline) {
		if (item.line == line) {
			return item;
		}
		else if ([item.scenes count]) {
			for (OutlineScene * subItem in item.scenes) {
				if (subItem.line == line) {
					return subItem;
				}
			}
		}
	}
	return nil;
}

/*
 
 This is super inefficient, I guess. Sorry.
 
 */

- (void) createOutline
{
	[_outline removeAllObjects];
	
	NSUInteger result = 0;
	NSUInteger sceneNumber = 1;

	// We will store a section depth to adjust depth for scenes that come after a section
	NSUInteger sectionDepth = 0;
	
	OutlineScene *previousScene;
	OutlineScene *currentScene;
	
	for (Line* line in self.lines) {
		if (line.type == section || line.type == synopse || line.type == heading) {
			
			OutlineScene *item;
			item = [[OutlineScene alloc] init];

			currentScene = item;
			
			item.string = line.string;
			item.type = line.type;
			item.omited = line.omited;
			item.line = line;
			
			if (item.type == section) {
				// Save section depth
				sectionDepth = line.sectionDepth;
				item.sectionDepth = sectionDepth;
			} else {
				item.sectionDepth = sectionDepth;
			}
			
			// Remove formatting characters from the outline item string if needed
			if ([item.string characterAtIndex:0] == '#' && [item.string length] > 1) {
				item.string = [item.string stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:@""];
			}
			if ([item.string characterAtIndex:0] == '=' && [item.string length] > 1) {
				item.string = [item.string stringByReplacingCharactersInRange:NSMakeRange(0, 1) withString:@""];
			}
			
			// Check if this heading contains a note. We can use notes to have colors etc. in the headings.
			[line.noteRanges enumerateRangesUsingBlock:^(NSRange range, BOOL * _Nonnull stop) {
								NSString * note = [line.string substringWithRange:range];
				if (range.location) {
					item.string = [line.string substringWithRange:NSMakeRange(0, range.location - 1)];
				}
				
				NSRange noteRange = NSMakeRange(NOTE_PATTERN_LENGTH, [note length] - NOTE_PATTERN_LENGTH * 2);
				note = [note substringWithRange:noteRange];
				
				if ([note localizedCaseInsensitiveContainsString:@COLOR_PATTERN] == true) {
					if ([note length] > [@COLOR_PATTERN length] + 1) {
						NSRange colorRange = [note rangeOfString:@COLOR_PATTERN options:NSCaseInsensitiveSearch];
						item.color = [note substringWithRange:NSMakeRange(colorRange.length, [note length] - colorRange.length)];
						item.color = [item.color stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
					}
				}
			}];
			
			if (line.type == heading) {
				// Check if the scene is omited (inside omit block: /* */)
				__block bool omited = false;
				[line.omitedRanges enumerateRangesUsingBlock:^(NSRange range, BOOL * _Nonnull stop) {
					//NSString * omitedLine = [line.string substringWithRange:range];
					if (range.location == 0) omited = true;
				}];
			
				if (line.sceneNumber) { item.sceneNumber = line.sceneNumber; }
				else {
					// If the scene is omited, let's not increment scene number for it.
					if (!omited) {
						item.sceneNumber = [NSString stringWithFormat:@"%lu", sceneNumber];
						sceneNumber++;
					} else {
						item.sceneNumber = @"";
					}
				}
			}
			
			// Get in / out points
			item.sceneStart = line.position;
			
			// If this scene is omited, we need to figure out where the omission starts from.
			if (item.omited) {
				NSUInteger index = [self.lines indexOfObject:line];
				while (index > 0) {
					index--;
					Line* previousLine = [self.lines objectAtIndex:index];
					
					// So, this is kind of brute force, but here's my rationalization:
					// a) The scene heading is already omited
					// b) Somewhere before there NEEDS to be a line which starts the omission
					// c) I mean, if there is omission INSIDE omission, the user can/should blame themself?
					if ([previousLine.string rangeOfString:@OMIT_OPEN_PATTERN].location != NSNotFound) {
						item.sceneStart = previousLine.position;
						
						// Shorten the previous scene accordingly
						if (previousScene) {
							previousScene.sceneLength = item.sceneStart - previousLine.position;
						}
						break;
					// So, what did I say about blaming the user?
					// I remembered that I have myself sometimes omited several scenes at once, so if we come across a scene heading while going through the lines, let's just reset and tell the previous scene that its omission is unterminated. We need this information for swapping the scenes around.
					// btw, I have really learned to code
					// in a shady way
					// but what does it count...
						// the only thing that matters is how you walk through the fire
					} else if (previousLine.type == heading) {
						item.sceneStart = line.position;
						item.noOmitIn = YES;
						if (previousScene) previousScene.noOmitOut = YES;
					}
				}
			}
			
			
			if (previousScene) {
				previousScene.sceneLength = item.sceneStart - previousScene.sceneStart;
			}
			
			// Set previous scene to point to the current one
			previousScene = item;

			result++;
			[_outline addObject:item];
		}
		
		// As the loop has completed, let's set the length for last outline item.
		if (line == [self.lines lastObject]) {
			currentScene.sceneLength = line.position + [line.string length] - currentScene.sceneStart;
		}
	}
}

// Deprecated (why though?)
- (NSInteger)outlineItemIndex:(Line*)item {
	return [self.lines indexOfObject:item];
}

- (BOOL)getAndResetChangeInOutline
{
    if (_changeInOutline) {
        _changeInOutline = NO;
        return YES;
    }
    return NO;
}


#pragma mark - Utility

- (NSString *)description
{
    NSString *result = @"";
    NSUInteger index = 0;
    for (Line *l in self.lines) {
        //For whatever reason, %lu doesn't work with a zero
        if (index == 0) {
            result = [result stringByAppendingString:@"0 "];
        } else {
            result = [result stringByAppendingFormat:@"%lu ", (unsigned long) index];
        }
        result = [[result stringByAppendingString:[l toString]] stringByAppendingString:@"\n"];
        index++;
    }
    //Cut off the last newline
    result = [result substringToIndex:result.length - 1];
    return result;
}

// This returns a pure string with no comments or invisible elements
- (NSString *)cleanedString {
	NSString * result = @"";
	
	for (Line* line in self.lines) {
		// Skip invisible elements
		if (line.type == section || line.type == synopse || line.omited || line.isTitlePage) continue;
		
		result = [result stringByAppendingFormat:@"%@\n", line.cleanedString];
	}
	
	return result;
}

@end
