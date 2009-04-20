//
//  AIAdvancedInspectorPane.h
//  Adium
//
//  Created by Elliott Harris on 1/17/08.
//  Copyright 2008 The Adium Team. All rights reserved.
//

#import "AIContactInfoContentController.h"
#import <Adium/AIAccountMenu.h>

@class AIAlternatingRowTableView;

@interface AIAdvancedInspectorPane : NSObject <AIContentInspectorPane, AIAccountMenuDelegate> {
	IBOutlet	NSView							*inspectorContentView;
	
	IBOutlet	AIAlternatingRowTableView		*accountsTableView;
	IBOutlet	NSTableColumn					*contactsColumn;
	
	IBOutlet	NSTextField						*label_account;
	IBOutlet	NSPopUpButton					*popUp_accounts;
	
	IBOutlet	NSTextField						*label_encryption;
	IBOutlet	NSPopUpButton					*popUp_encryption;
	
	IBOutlet	NSButton						*checkBox_alwaysShow;
	IBOutlet	NSButton						*checkBox_autoJoin;
	
	AIAccountMenu	*accountMenu;
	
	AIListObject					*displayedObject;
	NSArray							*accounts;
	NSArray							*contacts;
	BOOL							contactsColumnIsInAccountsTableView;
	
	BOOL							rebuildingContacts;
}

-(NSString *)nibName;
-(NSView *)inspectorContentView;
-(void)updateForListObject:(AIListObject *)inObject;

- (IBAction)selectedEncryptionPreference:(id)sender;
- (IBAction)setVisible:(id)sender;
- (IBAction)setAutoJoin:(id)sender;

@end
