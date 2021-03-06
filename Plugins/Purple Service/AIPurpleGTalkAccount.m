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

#import "AIPurpleGTalkAccount.h"
#import "auth_gtalk.h"
#import "AIKeychain.h"

#import "JSONKit.h"

#import "AIService.h"

#import <Adium/AIAccountControllerProtocol.h>
#import <Adium/AIInterfaceControllerProtocol.h>

#import "NSData+Base64.h"

@implementation AIPurpleGTalkAccount

- (const char *)purpleAccountName
{
	NSString	 *userNameWithGmailDotCom = nil;

	/*
	 * Purple stores the username in the format username@server/resource.  We need to pass it a username in this format
	 *
	 * Append @gmail.com if no domain is specified.
	 * Valid domains include gmail.com, googlemail.com, and google-hosted domains like e.co.za.
	 */
	if ([UID rangeOfString:@"@"].location == NSNotFound) {
		userNameWithGmailDotCom = [UID stringByAppendingString:@"@gmail.com"];
	} else {
		userNameWithGmailDotCom = UID;
	}

	NSString *completeUserName = [NSString stringWithFormat:@"%@/%@",userNameWithGmailDotCom, [self resourceName]];

	return [completeUserName UTF8String];
}

- (void)dealloc {
	[response release];
	[conn release];
	
	[super dealloc];
}

- (NSString *)serverSuffix
{
	return @"@gmail.com";
}

/*!
 * @brief Allow a file transfer with an object?
 *
 * As of July 28th, 2006, GTalk allows transfers.
 */
- (BOOL)allowFileTransferWithListObject:(AIListObject *)inListObject
{
	return YES;
}

- (AIReconnectDelayType)shouldAttemptReconnectAfterDisconnectionError:(NSString **)disconnectionError
{
	AIReconnectDelayType shouldAttemptReconnect = [super shouldAttemptReconnectAfterDisconnectionError:disconnectionError];
	
	if (disconnectionError && *disconnectionError) {
		if (([*disconnectionError rangeOfString:@"401"].location != NSNotFound) ||
			([*disconnectionError rangeOfString:@"Authentication Failure"].location != NSNotFound) ||
			([*disconnectionError rangeOfString:@"Not Authorized"].location != NSNotFound)) {
			[self setLastDisconnectionError:AILocalizedString(@"Incorrect username or password","Error message displayed when the server reports username or password as being incorrect.")];
			[self serverReportedInvalidPassword];
			shouldAttemptReconnect = AIReconnectImmediately;
		}
	}

	return shouldAttemptReconnect;
}

- (void)configurePurpleAccount
{
	[super configurePurpleAccount];
	
	// force connect server
	purple_account_set_string(account, "connect_server", "talk.google.com");
}

- (BOOL)allowAccountUnregistrationIfSupportedByLibpurple
{
	return NO;
}

/* Add the authentication mechanism for X-OAUTH2. Note that if the server offers it,
 * it will be used preferentially over any other mechanism e.g. PLAIN. */
- (void)setGTalkMechEnabled:(BOOL)inEnabled
{
	static BOOL enabledGTalkMech = NO;
	if (inEnabled != enabledGTalkMech) {
		if (inEnabled)
			jabber_auth_add_mech(jabber_auth_get_gtalk_mech());
		else
			jabber_auth_remove_mech(jabber_auth_get_gtalk_mech());
		
		enabledGTalkMech = inEnabled;
	}
}

- (void)promptUpgrade:(NSNumber *)number userInfo:(id)info suppression:(NSNumber *)suppressed {
	if ([number integerValue] == 1) {
		[adium.accountController editAccount:self onWindow:nil notifyingTarget:self];
	}
}

- (void)connect
{
	if (!self.UID.length) {
		[self requestAccessToken];
	} else {
		NSString *refresh_token = [[AIKeychain defaultKeychain_error:NULL] findGenericPasswordForService:self.service.serviceID
																								 account:self.UID
																							keychainItem:NULL error:NULL];
		
		if (refresh_token && refresh_token.length) {
			[self useRefreshToken:refresh_token];
		} else {
			if ([self preferenceForKey:KEY_GTALK_CODE group:GROUP_ACCOUNT_STATUS] ||
				[[self preferenceForKey:KEY_GTALK_UPGRADED_OAUTH2 group:GROUP_ACCOUNT_STATUS] boolValue]) {
				[self requestAccessToken];
			} else {
				[adium.interfaceController displayQuestion:AILocalizedString(@"Upgrade Google Talk account", nil)
										   withDescription:[NSString stringWithFormat:AILocalizedString(@"Adium uses a new, more secure way to sign in to Google Talk. To use this, you must authorize your account.", nil)]
										   withWindowTitle:nil
											 defaultButton:AILocalizedString(@"OK", nil)
										   alternateButton:AILocalizedString(@"Later", nil)
											   otherButton:nil
											   suppression:nil
													target:self
												  selector:@selector(promptUpgrade:userInfo:suppression:)
												  userInfo:nil];
			}
		}
	}
}

- (void)didConnect
{
	[self setGTalkMechEnabled:NO];
	[super didConnect];
}

- (void)didDisconnect
{
	[self setGTalkMechEnabled:NO];
	[super didDisconnect];
}

- (void)useRefreshToken:(NSString *)token {
	NSString *body = [NSString stringWithFormat:@"refresh_token=%@&client_id=" ADIUM_GTALK_CLIENT_ID
					  @"&client_secret=" ADIUM_GTALK_SECRET
					  @"&redirect_uri=urn:ietf:wg:oauth:2.0:oob"
					  @"&grant_type=refresh_token", token];
	
	NSData *data = [body dataUsingEncoding:NSUTF8StringEncoding];
	
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://www.googleapis.com/oauth2/v3/token"]];
	[request setHTTPMethod:@"POST"];
	[request setValue:@"application/x-www-form-urlencoded ; charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
	[request setValue:[NSString stringWithFormat:@"%u", (unsigned int)[data length]] forHTTPHeaderField:@"Content-Length"];
	[request setHTTPBody:data];
	
	AILogWithSignature(@"%@", request);
	
	conn = [[NSURLConnection connectionWithRequest:request delegate:self] retain];
	
	response = [[NSMutableData alloc] init];
}

- (void)requestAccessToken {
	NSString *body = [NSString stringWithFormat:@"code=%@&client_id=" ADIUM_GTALK_CLIENT_ID
					  @"&client_secret=" ADIUM_GTALK_SECRET
					  @"&redirect_uri=urn:ietf:wg:oauth:2.0:oob"
					  @"&grant_type=authorization_code", [self preferenceForKey:KEY_GTALK_CODE group:GROUP_ACCOUNT_STATUS]];
	
	NSData *data = [body dataUsingEncoding:NSUTF8StringEncoding];
	
	NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://www.googleapis.com/oauth2/v3/token"]];
	[request setHTTPMethod:@"POST"];
	[request setValue:@"application/x-www-form-urlencoded ; charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
	[request setValue:[NSString stringWithFormat:@"%u", (unsigned int)[data length]] forHTTPHeaderField:@"Content-Length"];
	[request setHTTPBody:data];
	
	AILogWithSignature(@"%@", request);
	
	conn = [[NSURLConnection connectionWithRequest:request delegate:self] retain];
	
	response = [[NSMutableData alloc] init];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)urlResponse {
	AILogWithSignature(@"%@", urlResponse);
}

- (void)connection:(NSURLConnection *)inConnection didReceiveData:(NSData *)data {
	[response appendData:data];
}

- (void)connectionDidFinishLoading:(NSURLConnection *)inConnection {
	NSDictionary *responseDict = [response objectFromJSONData];
	
	AILogWithSignature(@"");
	
	if ([responseDict objectForKey:@"error"]) {
		// Delete the refresh token, so we don't use it again.
		[[AIKeychain defaultKeychain_error:NULL] deleteGenericPasswordForService:self.service.serviceID
																		 account:self.UID
																		   error:NULL];
		
		[self setLastDisconnectionError:[NSString stringWithFormat:AILocalizedString(@"Retrieving OAuth token failed: %@", nil), [responseDict objectForKey:@"error_description"]]];
		[self serverReportedInvalidPassword];
		return;
	}
	
	if (!self.UID.length) {
		NSString *jsonWebToken = [responseDict objectForKey:@"id_token"];
		
		if (!jsonWebToken) {
			AILogWithSignature(@"id_token missing, can't set JID!");
		} else {
			NSArray *components = [jsonWebToken componentsSeparatedByString:@"."];
		
			if (components.count == 3) {
				NSString *base64EncodedIdentity = [components objectAtIndex:1];
				
				// Restore the padding
				switch (base64EncodedIdentity.length % 4) {
					case 2: {
						base64EncodedIdentity = [base64EncodedIdentity stringByAppendingString:@"=="];
						break;
					}
					case 3: {
						base64EncodedIdentity = [base64EncodedIdentity stringByAppendingString:@"="];
						break;
					}
					default: {
					}
				}
				
				NSData *identityData = [NSData dataFromBase64String:base64EncodedIdentity];
				NSDictionary *identity = [identityData objectFromJSONData];
				
				AILogWithSignature(@"");
				
				[self filterAndSetUID:[identity objectForKey:@"email"]];
			}
		}
	}
	
	if (!self.UID.length) {
		[self setLastDisconnectionError:AILocalizedString(@"Obtaining your JID failed", nil)];
		return;
	}
	
	[self setPreference:nil forKey:KEY_GTALK_CODE group:GROUP_ACCOUNT_STATUS];
	[self setPreference:@(YES) forKey:KEY_GTALK_UPGRADED_OAUTH2 group:GROUP_ACCOUNT_STATUS];
	
	if ([responseDict objectForKey:@"refresh_token"]) {
		[[AIKeychain defaultKeychain_error:NULL] deleteGenericPasswordForService:self.service.serviceID
																		 account:self.UID
																		   error:NULL];
		[[AIKeychain defaultKeychain_error:NULL] addGenericPassword:[responseDict objectForKey:@"refresh_token"]
														 forService:self.service.serviceID
															account:self.UID
													   keychainItem:NULL
															  error:NULL];
	}
	
	[password release];
	password = [[responseDict objectForKey:@"access_token"] retain];
	
	[conn release]; conn = nil;
	[response release]; response = nil;
	
	if (password) {
		[self setGTalkMechEnabled:YES];
		[super connect];
	} else {
		[self serverReportedInvalidPassword];
	}
}

-(void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
	[self setLastDisconnectionError:[NSString stringWithFormat:AILocalizedString(@"OAuth authentication failed: %@", nil), error.description]];
}

- (void)retrievePasswordThenConnect
{
	if ([self boolValueForProperty:@"Prompt For Password On Next Connect"] ||
		[self boolValueForProperty:@"mustPromptForPasswordOnNextConnect"]) {
		[adium.accountController editAccount:self onWindow:nil notifyingTarget:self];
		
	} else {
		/* Retrieve the user's password. Never prompt for a password, as we'll implement our own authorization handling
		 * if the password can't be retrieved.
		 */
		[adium.accountController passwordForAccount:self
									   promptOption:AIPromptNever
									notifyingTarget:self
										   selector:@selector(passwordReturnedForConnect:returnCode:context:)
											context:nil];
	}
}

- (void)editAccountSheetDidEndForAccount:(AIAccount *)inAccount withSuccess:(BOOL)successful {
	if (successful) {
		[self connect];
	}
}

@end
