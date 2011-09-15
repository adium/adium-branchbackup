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

#import "CBPurpleAccount.h"
#import "AIFacebookXMPPOAuthWebViewWindowController.h"

#define AIOAuth2ProgressNotification @"AIOAuth2ProgressNotification"
#define KEY_OAUTH2_STEP @"AuthStep"

typedef enum {
	AIOAuth2ProgressPromptingUser,
	AIOAuth2ProgressContactingServer,
	AIOAuth2ProgressPromotingForChat,
	AIOAuth2ProgressSuccess,
	AIOAuth2ProgressFailure
} AIOAuth2ProgressStep;

@interface AIOAuth2XMPPAccount : CBPurpleAccount {
	AIFacebookXMPPOAuthWebViewWindowController *oAuthWC;
	NSString *oAuthToken;
	
	NSUInteger networkState;
    
    NSURLConnection *connection; // weak
    NSURLResponse *connectionResponse;
    NSMutableData *connectionData;
}

- (void)requestAuthorization;
- (NSString *)oAuthURL;
- (NSString *)tokenFromURL:(NSURL *)url;
- (void)setMechEnabled:(BOOL)enabled;

@property (nonatomic, retain) AIFacebookXMPPOAuthWebViewWindowController *oAuthWC;
@property (nonatomic, copy) NSString *oAuthToken;

@end