//
//  RecentFiles.h
//  Beat
//
//  Created by Lauri-Matti Parppei on 13.2.2019.
//  Copyright © 2019 Lauri-Matti Parppei. All rights reserved.
//

@interface RecentFiles : NSObject <NSOutlineViewDelegate, NSOutlineViewDataSource> {
}
@property id selectedRow;
- (IBAction)doubleClickDocument:(id)sender;
@end
