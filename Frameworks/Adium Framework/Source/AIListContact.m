/* 
 * Adium is the legal property of its developers, whose names are listed in the copyright file included
 * with this source distribution.
 * 
 * This program is free software; you can redistribute it and/or modify it under the terms of the GNU
 * General Public License as published by the Free Software Foundation; either version 2 of the License,
 * or (at your option) any later version.
 * 
 * This program is distributed in the hope that it will be useful, but WITHOUT ANY WARRANTY; without even
 * the implied warranty of MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU General
 * Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License along with this program; if not,
 * write to the Free Software Foundation, Inc., 59 Temple Place - Suite 330, Boston, MA  02111-1307, USA.
 */

#import <Adium/AIContactControllerProtocol.h>
#import <Adium/AIChatControllerProtocol.h>
#import <Adium/AIContentControllerProtocol.h>
#import <Adium/AIStatusControllerProtocol.h>
#import <Adium/AIContentMessage.h>
#import <Adium/AIListContact.h>
#import <Adium/AIContactList.h>
#import <Adium/AIListGroup.h>
#import <Adium/AIMetaContact.h>
#import <Adium/AIService.h>
#import <Adium/AIUserIcons.h>
#import <Adium/ESFileTransfer.h>
#import <Adium/AIStatus.h>
#import <Adium/AIHTMLDecoder.h>

#import <AIUtilities/AIMutableOwnerArray.h>
#import <AIUtilities/AIMutableStringAdditions.h>

#import <AvailabilityMacros.h>

#import "AIAddressBookController.h"

#define KEY_BASE_WRITING_DIRECTION		@"Base Writing Direction"
#define PREF_GROUP_WRITING_DIRECTION	@"Writing Direction"

#define CONTACT_SIGN_ON_OR_OFF_PERSISTENCE_DELAY 15

@interface AIListObject ()
- (void)setContainingObject:(AIListObject <AIContainingObject> *)inGroup;
@end

@interface AIListContact ()
@property (readwrite, nonatomic, assign) AIMetaContact *metaContact;
- (void) remoteGroupingChanged;
@end

@implementation AIListContact

//Init with an account
- (id)initWithUID:(NSString *)inUID account:(AIAccount *)inAccount service:(AIService *)inService
{
	if ((self = [self initWithUID:inUID service:inService])) {
		account = [inAccount retain];
	}
	
	return self;
}

//Standard init
- (id)initWithUID:(NSString *)inUID service:(AIService *)inService
{
	if ((self = [super initWithUID:inUID service:inService])) {
		account = nil;
		m_remoteGroupNames = [[NSMutableSet alloc] initWithCapacity:1];
		internalUniqueObjectID = nil;
	}

	return self;
}

- (void)dealloc
{
	[account release]; account = nil;
	[m_remoteGroupNames release]; m_remoteGroupNames = nil;
	[internalUniqueObjectID release]; internalUniqueObjectID = nil;
	
	[textColor release]; textColor = nil;
	[invertedTextColor release]; invertedTextColor = nil;
	[labelColor release]; labelColor = nil;
	[imageOpacity release]; imageOpacity = nil;
	[ABUniqueID release]; ABUniqueID = nil;
	[textProfile release]; textProfile = nil;
	[idleSince release]; idleSince = nil;
	[idleReadable release]; idleReadable = nil;
	[serverDisplayName release]; serverDisplayName = nil;
	[formattedUID release]; formattedUID = nil;
	
	[super dealloc];
}

//The account that owns this contact
@synthesize account;

/*!
 * @brief Set the UID of this contact
 *
 * The UID for an AIListContact generally shouldn't change... if the contact is actually renamed serverside, however,
 * it is useful to change the UID without having to change everything else associated with it.
 */
- (void)setUID:(NSString *)inUID
{
	if (UID != inUID) {
		[UID release]; UID = [inUID retain];
		[internalObjectID release]; internalObjectID = nil;
		[internalUniqueObjectID release]; internalUniqueObjectID = nil;		
	}
}

//An object ID generated by Adium that is completely unique to this contact.  This ID is generated from the service ID, 
//UID, and account UID.  Adium will not allow multiple contacts with the same internalUniqueObjectID to be created.
- (NSString *)internalUniqueObjectID
{
	if (!internalUniqueObjectID) {
		internalUniqueObjectID = [[AIListContact internalUniqueObjectIDForService:self.service
																		  account:self.account
																			  UID:self.UID] retain];
	}
	return internalUniqueObjectID;
}

//Generate a unique object ID for the passed object
+ (NSString *)internalUniqueObjectIDForService:(AIService *)inService account:(AIAccount *)inAccount UID:(NSString *)inUID
{
	return [NSString stringWithFormat:@"%@.%@.%@", inService.serviceClass, inAccount.UID, inUID];
}


//Remote Grouping ------------------------------------------------------------------------------------------------------
#pragma mark Remote Grouping

- (NSSet *) remoteGroupNames
{
	return [[m_remoteGroupNames copy] autorelease];
}

- (void) setRemoteGroupNames:(NSSet *)inGroupNames
{
	NSParameterAssert(inGroupNames != nil);
	[m_remoteGroupNames setSet:inGroupNames];
	[self remoteGroupingChanged];
}

- (void) addRemoteGroupName:(NSString *)inName
{
	NSParameterAssert(inName != nil);
	if ([m_remoteGroupNames containsObject:inName])
		return;
	
	[m_remoteGroupNames addObject:inName];
	[self remoteGroupingChanged];
}

- (void) removeRemoteGroupName:(NSString *)inName
{
	NSParameterAssert(inName != nil);
	if (![m_remoteGroupNames containsObject:inName])
		return;
	
	[m_remoteGroupNames removeObject:inName];
	[self remoteGroupingChanged];
}

- (NSUInteger) countOfRemoteGroupNames
{
	return m_remoteGroupNames.count;
}

- (NSSet *)remoteGroups
{
	NSMutableSet *groups = [NSMutableSet set];
	for (NSString *remoteGroup in m_remoteGroupNames) {
		[groups addObject:[adium.contactController groupWithUID:remoteGroup]];
	}
	return groups;
}

- (void) remoteGroupingChanged
{
	NSUInteger remoteGroupCount = m_remoteGroupNames.count;
	if (remoteGroupCount == 0)
		[AIUserIcons flushCacheForObject:self];
	
	[self restoreGrouping];
	
	if (self.isStranger != (remoteGroupCount == 0)) {
		[self setValue:[NSNumber numberWithBool:remoteGroupCount > 0]
		   forProperty:@"notAStranger"
				notify:NotifyLater];
		[self notifyOfChangedPropertiesSilently:YES];
	}
}

//An AIListContact normally groups based on its remoteGroupNames (if it is not within a metaContact). 
//Restore this grouping.
- (void)restoreGrouping
{
	if (self.metaContact) {
		[self.metaContact updateRemoteGroupingOfContact:self];		
		return;
	}
	
	//Create a group for the contact even if contact list groups aren't on,
	//otherwise requests for all the contact list groups will return nothing
	NSMutableSet *groups = [NSMutableSet set];
	for (NSString *remoteGroupName in m_remoteGroupNames) {
		AIListGroup *localGroup = [adium.contactController groupWithUID:remoteGroupName];
		
		if (!adium.contactController.useContactListGroups)
			localGroup = adium.contactController.contactList;
		else if (adium.contactController.useOfflineGroup && !self.online && !self.alwaysVisible)
			localGroup = adium.contactController.offlineGroup;
		
		[groups addObject:localGroup];
	}
	[adium.contactController _moveContactLocally:self fromGroups:self.groups toGroups:groups];
}

#pragma mark Names
/*!
 * @brief Display name
 *
 * Display name, drawing first from any externally-provided display name, then falling back to 
 * the formatted UID.
 *
 * A listContact attempts to have the same displayName as its containing contact (potentially its metaContact).
 * If it is not in a metaContact, its display name is returned by super.displayName
 */
- (NSString *)displayName
{
	AIMetaContact	*meta = self.metaContact;

	NSString *displayName = meta ? meta.displayName : super.displayName;

	//If a display name was found, return it; otherwise, return the formattedUID  
	return displayName ? displayName : self.formattedUID;
}

/*!
 * @brief Own display name
 *
 * Returns the display name without trying to account for a metaContact. Exists for use by AIMetaContact to avoid
 * infinite recursion by its displayName calling our displayName calling its displayName and so on.
 */
- (NSString *)ownDisplayName
{
	return super.displayName;
}

/*!
 * @brief This contact's serverside display name, which is generally specificed by the contact remotely
 *
 * @result The serverside display name, or nil if none is set
 */
- (NSString *)serversideDisplayName
{
	return [self valueForProperty:@"serverDisplayName"];	
}

- (void)setServersideAlias:(NSString *)alias 
				  silently:(BOOL)silent
{
	BOOL changes = NO;
	BOOL displayNameChanges = NO;
	
	//This is the server display name.  Set it as such.
	if (![alias isEqualToString:[self valueForProperty:@"serverDisplayName"]]) {
		//Set the server display name property as the full display name
		[self setValue:alias
					   forProperty:@"serverDisplayName"
					   notify:NotifyLater];
		
		changes = YES;
	}

	NSMutableString *cleanedAlias;
	
	//Remove any newlines, since we won't want them anywhere below
	cleanedAlias = [alias mutableCopy];
	[cleanedAlias convertNewlinesToSlashes];

	AIMutableOwnerArray	*displayNameArray = [self displayArrayForKey:@"Display Name"];
	NSString			*oldDisplayName = [displayNameArray objectValue];
	
	//If the mutableOwnerArray's current value isn't identical to this alias, we should set it
	if (![[displayNameArray objectWithOwner:self.account] isEqualToString:cleanedAlias]) {
		[displayNameArray setObject:cleanedAlias
						  withOwner:self.account
					  priorityLevel:Low_Priority];
		
		//If this causes the object value to change, we need to request a manual update of the display name
		if (oldDisplayName != [displayNameArray objectValue]) {
			displayNameChanges = YES;
		}
	}
	
	if (changes) {
		//Apply any changes
		[self notifyOfChangedPropertiesSilently:silent];
	}
	
	if (displayNameChanges) {
		//Request an alias change
		[[NSNotificationCenter defaultCenter] postNotificationName:Contact_ApplyDisplayName
												  object:self
												userInfo:[NSDictionary dictionaryWithObject:[NSNumber numberWithBool:YES]
																					 forKey:@"Notify"]];
	}
	
	[cleanedAlias release];
}

/*!
 * @brief The way this object's name should be spoken
 *
 * If not found, the display name is returned.
 */
- (NSString *)phoneticName
{
	AIMetaContact *meta = self.metaContact;
	NSString		*phoneticName;

	phoneticName = meta ? meta.phoneticName : super.phoneticName;;
	
	//If a display name was found, return it; otherwise, return the formattedUID
	return phoneticName ? phoneticName : self.displayName;
}

/*!
 * @brief Own phonetic name
 *
 * Returns the phonetic name without trying to account for a metaContact. Exists for use by AIMetaContact to avoid
 * infinite recursion by its phoneticName calling our phoneticName calling its phoneticName and so on.
 */
- (NSString *)ownPhoneticName
{
	return super.phoneticName;
}

#pragma mark Properties

/*!
 * @brief Set online
 */
- (void)setOnline:(BOOL)online notify:(NotifyTiming)notify silently:(BOOL)silent
{
	if (online != self.online) {
		[self setValue:[NSNumber numberWithBool:online]
					   forProperty:@"isOnline"
					   notify:notify];
		
		if (!silent) {
			[self setValue:[NSNumber numberWithBool:YES] 
						   forProperty:(online ? @"signedOn" : @"signedOff")
						   notify:notify];
			[self setValue:nil 
						   forProperty:(online ? @"signedOff" : @"signedOn")
						   notify:notify];
			[self setValue:nil
						   forProperty:(online ? @"signedOn" : @"signedOff")
					   afterDelay:CONTACT_SIGN_ON_OR_OFF_PERSISTENCE_DELAY];
		}
		
		if (online) {
			if (notify == NotifyNow) {
				[self notifyOfChangedPropertiesSilently:silent];
			}
			
		} else {
			//Will always notify
			[self.account removePropertyValuesFromContact:self
												  silently:silent];	
		}
	}
}

/*!
 * @brief Set the sign on date
 */
- (void)setSignonDate:(NSDate *)signonDate notify:(NotifyTiming)notify
{
	[self setValue:signonDate
				   forProperty:@"Signon Date"
				   notify:notify];
}
/*!
 * @brief Date this contact signed on, if available
 */
- (NSDate *)signonDate
{
	return [self valueForProperty:@"Signon Date"];
}

/*!
 * @brief Set the idle state
 *
 * @param isIdle YES if the contact is idle
 * @param idleSinceDate The date this contact went idle. Only relevant if isIdle is YES
 * @param notify The NotifyTiming
 */
- (void)setIdle:(BOOL)inIsIdle sinceDate:(NSDate *)idleSinceDate notify:(NotifyTiming)notify
{
	if (inIsIdle) {
		if (idleSinceDate) {
			[self setValue:idleSinceDate
						   forProperty:@"idleSince"
						   notify:NotifyLater];
		} else {
			//No idleSinceDate means we are Idle but don't know how long, so set to -1
			[self setValue:[NSNumber numberWithInt:-1]
						   forProperty:@"idle"
						   notify:NotifyLater];
		}
	} else {
		[self setValue:nil
					   forProperty:@"idleSince"
					   notify:NotifyLater];
		[self setValue:nil
					   forProperty:@"idle"
					   notify:NotifyLater];
	}
	
	/* @"idle", for a contact with an IdleSince date, will be changing every minute.  @"isIdle" provides observers a way
	* to perform an action when the contact becomes/comes back from idle, regardless of whether an IdleSince is available,
	* without having to do that action every minute for other contacts.
	*/
	[self setValue:[NSNumber numberWithBool:inIsIdle]
				   forProperty:@"isIdle"
				   notify:NotifyLater];
	
	//Apply any changes
	if (notify == NotifyNow) {
		[self notifyOfChangedPropertiesSilently:NO];
	}
}

- (void)setServersideIconData:(NSData *)iconData notify:(NotifyTiming)notify
{
	[AIUserIcons setServersideIconData:iconData forObject:self notify:notify];
}

/*!
 * @brief Set the warning level
 *
 * @param warningLevel The warning level, an integer between 0 and 100
 * @param notify The NotifyTiming
 */
- (void)setWarningLevel:(NSInteger)warningLevel notify:(NotifyTiming)notify
{
	if (warningLevel != self.warningLevel) {
		[self setValue:[NSNumber numberWithInteger:warningLevel]
					   forProperty:@"Warning"
					   notify:notify];
	}
}

/*!
 * @brief Warning level
 *
 * @result The warning level, an integer between 0 and 100
 */
- (NSInteger)warningLevel
{
	return [self integerValueForProperty:@"Warning"];
}

/*!
 * @brief Set the profile array
 */
- (void)setProfileArray:(NSArray *)array notify:(NotifyTiming)notify
{
	[self setValue:array
	   forProperty:@"ProfileArray"
			notify:notify];
}

/*!
 * @brief The profile array
 */
- (NSArray *)profileArray
{
	return [self valueForProperty:@"ProfileArray"];	
}

/*!
 * @brief Set the profile
 */
- (void)setProfile:(NSAttributedString *)profile notify:(NotifyTiming)notify
{
	[self setValue:profile
				   forProperty:@"textProfile" 
				   notify:notify];
}

/*!
 * @brief Profile
 */
- (NSAttributedString *)profile
{
	return [self valueForProperty:@"textProfile"];
}

/*!
 * @brief Is this contact a stranger?
 * 
 * A listContact is a stranger if it has a nil remoteGroupName
 */
- (BOOL)isStranger
{
	return ![self boolValueForProperty:@"notAStranger"];
}

/*!
 * @brief If this contact intentionally on the contact list?
 */
- (BOOL)isIntentionallyNotAStranger
{
	return !self.isStranger && [self.account isContactIntentionallyListed:self];
}

/*!
 * @brief Is this object connected via a mobile device?
 */
- (BOOL)isMobile
{
	return [self boolValueForProperty:@"isMobile"];
}

/*!
 * @brief Set if this contact is mobile
 */
- (void)setIsMobile:(BOOL)inIsMobile notify:(NotifyTiming)notify
{
	[self setValue:[NSNumber numberWithBool:inIsMobile]
				   forProperty:@"isMobile"
				   notify:notify];
}

/*!
 * @brief Is this contact blocked?
 *
 * @result A boolean indicating if the contact is blocked or not
 */
- (BOOL)isBlocked
{
	return [self boolValueForProperty:KEY_IS_BLOCKED];
}

- (void)setIsBlocked:(BOOL)yesOrNo updateList:(BOOL)addToPrivacyLists
{
	[self setIsOnPrivacyList:yesOrNo updateList:addToPrivacyLists privacyType:AIPrivacyTypeDeny];
}

- (void)setIsAllowed:(BOOL)yesOrNo updateList:(BOOL)addToPrivacyLists
{
	[self setIsOnPrivacyList:yesOrNo updateList:addToPrivacyLists privacyType:AIPrivacyTypePermit];
}

/*!
 * @brief Set if this contact is on the privacy list
 */
- (void)setIsOnPrivacyList:(BOOL)shouldBeBlocked updateList:(BOOL)addToPrivacyLists privacyType:(AIPrivacyType)privType
{
	if (addToPrivacyLists) {		//caller of this method wants to actually block or unblock the contact, rather than just update the property
		
		if (![self.account conformsToProtocol:@protocol(AIAccount_Privacy)]) {
			NSLog(@"Privacy is not supported on contacts for the account: %@", self.account);
			return;
		}
		
		id<AIAccount_Privacy> contactAccount = (id<AIAccount_Privacy>)self.account;
		
		BOOL contactIsBlocked = [[contactAccount listObjectsOnPrivacyList:privType] containsObject:self];
		
		if (shouldBeBlocked == contactIsBlocked)
			return;
		
		BOOL	result = NO;

		if (shouldBeBlocked)
			result = [contactAccount addListObject:self toPrivacyList:privType];
		else
			result = [contactAccount removeListObject:self fromPrivacyList:privType];
		
		//Don't update the property if we didn't change anything
		if (!result)
			return;
	} 

	[self setValue:[NSNumber numberWithBool:((privType == AIPrivacyTypeDeny) == shouldBeBlocked)]
				   forProperty:KEY_IS_BLOCKED
				   notify:NotifyNow];
}

- (AIEncryptedChatPreference)encryptedChatPreferences {
	AIEncryptedChatPreference	pref = EncryptedChat_Default;
	
	//Get the contact's preference (or metacontact's)
	NSNumber *prefNumber = [self.parentContact preferenceForKey:KEY_ENCRYPTED_CHAT_PREFERENCE group:GROUP_ENCRYPTION];
	
	//If that turned up nothing, check all the groups it's in
	if (!prefNumber || [prefNumber integerValue] == EncryptedChat_Default) {
		for (AIListGroup *group in self.parentContact.groups)
		{
			if ((prefNumber = [group preferenceForKey:KEY_ENCRYPTED_CHAT_PREFERENCE group:GROUP_ENCRYPTION]))
				break;
		}	
	}
	
	//If that turned up nothing, check global prefs
	if (!prefNumber)
		prefNumber = [adium.preferenceController preferenceForKey:KEY_ENCRYPTED_CHAT_PREFERENCE group:GROUP_ENCRYPTION];
	
	//If no contact preference or the contact is set to use the default, use the account preference
	if (!prefNumber || ([prefNumber integerValue] == EncryptedChat_Default)) {
		prefNumber = [self.account preferenceForKey:KEY_ENCRYPTED_CHAT_PREFERENCE
					  group:GROUP_ENCRYPTION];		
	}
	
	if (prefNumber)
		pref = [prefNumber intValue];
	
	return pref;
}

- (void)setAlwaysVisible:(BOOL)inVisible
{
	[super setAlwaysVisible:inVisible];
	
	[self restoreGrouping];
}

- (BOOL)alwaysVisible
{
	if (self.metaContact) {
		return self.metaContact.alwaysVisible;
	}
	
	return [super alwaysVisible];
}

#pragma mark Status

/*!
* @brief Determine the status message to be displayed in the contact list
 *
 * Look at the contact's status message.
 * Failing that, look for a statusName, which might be something like "DND" or "Free for Chat"
 * and look up the localized description of it.
 */
- (NSAttributedString *)contactListStatusMessage
{
	NSAttributedString	*contactListStatusMessage = self.statusMessage;

	if (!contactListStatusMessage) {
		NSString			*statusName = self.statusName;
		
		if (statusName) {
			NSString *descriptionOfStatus = [adium.statusController localizedDescriptionForStatusName:statusName
											 statusType:self.statusType];
			
			if (descriptionOfStatus)
				contactListStatusMessage = [[[NSAttributedString alloc] initWithString:descriptionOfStatus] autorelease];			
		}
	}

	return contactListStatusMessage;	
}

/*!
 * @brief Are sounds for this contact muted?
 */
- (BOOL)soundsAreMuted
{
	return [self.account.statusState mutesSound];
}

#pragma mark Parents

/*!
 * @brief This object's parent AIListContact
 *
 * The parent AIListContact is the appropriate place to apply preferences specific to this contact so that such
 * preferences are also applied to other AIListContacts in the same meta contact, if necessary.
 *
 * @result Either this contact or some more-encompassing contact which ultimately contains it.
 */
- (AIListContact *)parentContact
{
	return self.metaContact ?: self;
}

- (BOOL)containsObject:(AIListObject*)object
{
    return NO;
}

- (NSSet *) containingObjects {
	if (metaContact)
		return [NSSet setWithObject:metaContact];
	return super.containingObjects;
}

/*!
 * @brief Can this object be part of a metacontact?
 */
- (BOOL)canJoinMetaContacts
{
	return YES;
}

- (AIMetaContact *)metaContact
{
	return metaContact;
}

- (void) setMetaContact:(AIMetaContact *)meta
{
	metaContact = meta;
	
	/* Ugly: Subclass accessing superclass's ivar */
	[m_groups removeAllObjects];
}

- (BOOL) existsServerside
{
	return YES;
}

- (void)removeFromGroup:(AIListObject <AIContainingObject> *)group
{
	if (self.account.online) {
		if (group == adium.contactController.contactList
			|| group == adium.contactController.offlineGroup) {
			[self.account removeContacts:[NSArray arrayWithObject:self]
							  fromGroups:[self.remoteGroups allObjects]];	
		} else {			
			[self.account removeContacts:[NSArray arrayWithObject:self]
							  fromGroups:[NSArray arrayWithObject:group]];	
		}
	}
}

#pragma mark Equality
/*
- (BOOL)isEqual:(id)anObject
{
	return ([anObject isMemberOfClass:[self class]] &&
			[[(AIListContact *)anObject internalUniqueObjectID] isEqualToString:[self internalUniqueObjectID]]);
}
*/
//AppleScript ----------------------------------------------------------------------------------------------------------
#pragma mark AppleScript

- (id)sendScriptCommand:(NSScriptCommand *)command {
	NSDictionary	*evaluatedArguments = [command evaluatedArguments];
	NSString			*message = [evaluatedArguments objectForKey:@"message"];
	AIAccount		*targetAccount = [evaluatedArguments objectForKey:@"account"];
	NSString			*filePath = [evaluatedArguments objectForKey:@"filePath"];
	
	AIListContact   *targetMessagingContact = self;
	AIListContact   *targetFileTransferContact = nil;

	if (targetAccount) {
		if (self.account != account)
			targetMessagingContact = [adium.contactController contactWithService:self.service account:account UID:self.UID];

		targetFileTransferContact = targetMessagingContact;
	}
	
	//Send any message we were told to send
	if (message && [message length]) {
		AIChat			*chat;
		BOOL			autoreply = [[evaluatedArguments objectForKey:@"autoreply"] boolValue];
		
		//Make sure we know where we are sending the message - if we don't have a target yet, find the best contact for
		//sending CONTENT_MESSAGE_TYPE.
		if (!targetMessagingContact) {
			//Get the target contact.  This could be the same contact, an identical contact on another account, 
			//or a subcontact (if we're talking about a metaContact, for example)
			targetMessagingContact = [adium.contactController preferredContactForContentType:CONTENT_MESSAGE_TYPE
																				forListContact:self];
			targetAccount = targetMessagingContact.account;	
		}
		
		if (targetMessagingContact) {
			chat = [adium.chatController openChatWithContact:targetMessagingContact
											onPreferredAccount:NO];
			
			//Take the string and turn it into an attributed string (in case we were passed HTML)
			NSAttributedString  *attributedMessage = [AIHTMLDecoder decodeHTML:message];
			AIContentMessage	*messageContent;
			messageContent = [AIContentMessage messageInChat:chat
												  withSource:targetAccount
												 destination:targetMessagingContact
														date:nil
													 message:attributedMessage
												   autoreply:autoreply];
			
			[adium.contentController sendContentObject:messageContent];
		} else {
			AILogWithSignature(@"No contact available to receive a message to %@", self);
		}
	}
	
	//Send any file we were told to send
	if (filePath && [filePath length]) {
		//Make sure we know where we are sending the file - if we don't have a target yet, find the best contact for
		//sending CONTENT_FILE_TRANSFER_TYPE.
		if (!targetFileTransferContact) {
			//Get the target contact.  This could be the same contact, an identical contact on another account, 
			//or a subcontact (if we're talking about a metaContact, for example)
			targetFileTransferContact = [adium.contactController preferredContactForContentType:CONTENT_FILE_TRANSFER_TYPE
																				   forListContact:self];
		}
		
		if (targetFileTransferContact) {
			[adium.fileTransferController sendFile:filePath toListContact:targetFileTransferContact];
		} else {
			AILogWithSignature(@"No contact available to receive files to %@", self);
			NSBeep();
		}
	}
		
	return nil;
}

//Writing Direction ----------------------------------------------------------------------------------------------------------
#pragma mark Writing Direction

- (NSWritingDirection)defaultBaseWritingDirection
{
	static NSWritingDirection defaultBaseWritingDirection;
	static BOOL determinedDefaultBaseWritingDirection = NO;
	
	if (!determinedDefaultBaseWritingDirection) {
		/* Use  the default writing direction of the language of the user's locale (and not the language
		 * of the active localization). By that, we assume most users are mostly talking to their local friends.
		 */
		NSString	*lang = [[NSLocale currentLocale] objectForKey:NSLocaleLanguageCode];		
		defaultBaseWritingDirection = [NSParagraphStyle defaultWritingDirectionForLanguage:lang];
		determinedDefaultBaseWritingDirection = YES;
	}
	
	return defaultBaseWritingDirection;
}

- (NSWritingDirection)baseWritingDirection {
	NSNumber	*dir = [self preferenceForKey:KEY_BASE_WRITING_DIRECTION group:PREF_GROUP_WRITING_DIRECTION];

	return (dir ? [dir intValue] : [self defaultBaseWritingDirection]);
}

- (void)setBaseWritingDirection:(NSWritingDirection)direction {
	[self setPreference:[NSNumber numberWithInteger:direction]
				 forKey:KEY_BASE_WRITING_DIRECTION
				  group:PREF_GROUP_WRITING_DIRECTION];
}

#pragma mark Address Book
- (ABPerson *)addressBookPerson
{
	return [AIAddressBookController personForListObject:self.parentContact];	
}
- (void)setAddressBookPerson:(ABPerson *)inPerson
{
	[self.parentContact setPreference:[inPerson uniqueId]
								 forKey:KEY_AB_UNIQUE_ID
								  group:PREF_GROUP_ADDRESSBOOK];
}

#pragma mark Applescript

- (NSScriptObjectSpecifier *)objectSpecifier
{
	NSScriptObjectSpecifier *containerRef = self.account.objectSpecifier;
	return [[[NSNameSpecifier allocWithZone:[self zone]]
		initWithContainerClassDescription:[containerRef keyClassDescription]
		containerSpecifier:containerRef key:@"contacts" name:self.UID] autorelease];
}

- (BOOL)scriptingBlocked
{
	return [self isBlocked];
}
- (void)setScriptingBlocked:(BOOL)b
{
	[self setIsBlocked:b updateList:YES];
}

@dynamic containingObject;

@end
