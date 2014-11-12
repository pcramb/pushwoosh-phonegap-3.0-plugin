//
//  PushNotificationManager.m
//  Pushwoosh SDK
//  (c) Pushwoosh 2012
//

#import "Constants.h"
#import "PushNotificationManager.h"

#import "PWHtmlWebViewController.h"
#import "PWRequestManager.h"
#import "PWRegisterDeviceRequest.h"
#import "PWSetTagsRequest.h"
#import "PWGetTagsRequest.h"
#import "PWSendBadgeRequest.h"
#import "PWAppOpenRequest.h"
#import "PWPushStatRequest.h"
#import "PWGetNearestZoneRequest.h"
#import "PWApplicationEventRequest.h"
#import "PWUnregisterDeviceRequest.h"
#import "PWSendPurchaseRequest.h"
#import "PWGetBeaconsRequest.h"

#import "PWLocationTracker.h"

#include <sys/socket.h> // Per msqr
#include <sys/sysctl.h>
#include <net/if.h>
#include <net/if_dl.h>

#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>

#import "PushRuntime.h"
#import "PWBeaconsTracker.h"

#if ! __has_feature(objc_arc)
#error "ARC is required to compile Pushwoosh SDK"
#endif

static char kDeviceIdKey;

@interface UIApplication(Pushwoosh)
- (void) pw_setApplicationIconBadgeNumber:(NSInteger) badgeNumber;
@end

@implementation PWTags
+ (NSDictionary *) incrementalTagWithInteger:(NSInteger)delta {
	return [NSMutableDictionary dictionaryWithObjectsAndKeys:@"increment", @"operation", [NSNumber numberWithLong:delta], @"value", nil];
}
@end

@interface PushNotificationManager () <HtmlWebViewControllerDelegate, SKProductsRequestDelegate>

@property (nonatomic, strong) PWLocationTracker *locationTracker;

#ifdef USE_IBEACONS
@property (nonatomic, strong) PWBeaconsTracker *beaconsTracker;
#endif

@property (nonatomic, strong) NSString *lastPushMessageHash;

@property (nonatomic, strong) NSMutableArray *transactionsArray;
@property (nonatomic, strong) NSMutableDictionary *productArray;	//productid => SKProduct mapping
@end

@implementation PushNotificationManager

@synthesize appCode, appName, richPushWindow, pushNotifications, delegate, locationTracker;
@synthesize supportedOrientations, showPushnotificationAlert;


////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Private Methods

// Return the local MAC addy
// Courtesy of FreeBSD hackers email list
// Accidentally munged during previous update. Fixed thanks to erica sadun & mlamb.

- (NSString *) macaddress {
    
    int                 mib[6];
    size_t              len;
    char                *buf;
    unsigned char       *ptr;
    struct if_msghdr    *ifm;
    struct sockaddr_dl  *sdl;
    
    mib[0] = CTL_NET;
    mib[1] = AF_ROUTE;
    mib[2] = 0;
    mib[3] = AF_LINK;
    mib[4] = NET_RT_IFLIST;
    
    if ((mib[5] = if_nametoindex("en0")) == 0) {
        printf("Error: if_nametoindex error\n");
        return NULL;
    }
    
    if (sysctl(mib, 6, NULL, &len, NULL, 0) < 0) {
        printf("Error: sysctl, take 1\n");
        return NULL;
    }
    
    if ((buf = malloc(len)) == NULL) {
        printf("Could not allocate memory. error!\n");
        return NULL;
    }
    
    if (sysctl(mib, 6, buf, &len, NULL, 0) < 0) {
        printf("Error: sysctl, take 2");
        free(buf);
        return NULL;
    }
    
    ifm = (struct if_msghdr *)buf;
    sdl = (struct sockaddr_dl *)(ifm + 1);
    ptr = (unsigned char *)LLADDR(sdl);
    NSString *outstring = [NSString stringWithFormat:@"%02X:%02X:%02X:%02X:%02X:%02X",
                           *ptr, *(ptr+1), *(ptr+2), *(ptr+3), *(ptr+4), *(ptr+5)];
    free(buf);
    
    return outstring;
}

- (NSString *) stringFromMD5: (NSString *) val{
    
    if(val == nil || [val length] == 0)
        return nil;
    
    const char *value = [val UTF8String];
    
    unsigned char outputBuffer[CC_MD5_DIGEST_LENGTH];
    CC_MD5(value, (CC_LONG)strlen(value), outputBuffer);
    
    NSMutableString *outputString = [[NSMutableString alloc] initWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for(NSInteger count = 0; count < CC_MD5_DIGEST_LENGTH; count++){
        [outputString appendFormat:@"%02x",outputBuffer[count]];
    }
    
    return outputString;
}

- (NSString *) generateIdentifier {
	if ([[[UIDevice currentDevice].systemVersion substringToIndex:1] integerValue] >= 7) {
		
		//Check if iAd framework connected
		NSString *identifier = nil;
		Class AsindentifiermanagerClass = NSClassFromString(@"ASIdentifierManager");
		if (AsindentifiermanagerClass) {
			NSObject *asimanagerInstance = [AsindentifiermanagerClass performSelector: @selector(sharedManager)];

			SEL selector = NSSelectorFromString(@"advertisingIdentifier");
			IMP imp = [asimanagerInstance methodForSelector:selector];
			id (*func)(id, SEL) = (void *)imp;
			id obj = func(asimanagerInstance, selector);
			identifier = [obj UUIDString];
		}
		
		if(!identifier) {
			identifier = [[[UIDevice currentDevice] identifierForVendor] UUIDString];
		}
		
		return identifier;
	}
	
	//iOS6 code
    NSString *macaddress = [self macaddress];
    NSString *uniqueIdentifier = [self stringFromMD5: macaddress];
    
    return uniqueIdentifier;
}

- (void) writeDeviceID:(NSString *) deviceId {
	if (deviceId == nil)
		return;
	NSString *ident = [[[NSBundle mainBundle] objectForInfoDictionaryKey:(__bridge id)kCFBundleIdentifierKey] stringByAppendingString:@".DeviceId"];
	
	NSMutableDictionary *genericPasswordQuery = [NSMutableDictionary dictionary];
	
	[genericPasswordQuery setObject:(__bridge id)kSecClassGenericPassword forKey:(__bridge id)kSecClass];
	[genericPasswordQuery setObject:ident forKey:(__bridge id)kSecAttrService];
	[genericPasswordQuery setObject:ident forKey:(__bridge id)kSecAttrAccount];
	
	[genericPasswordQuery setObject:(__bridge id)kSecAttrAccessibleAlwaysThisDeviceOnly forKey:(__bridge id)kSecAttrAccessible];
	[genericPasswordQuery setObject:[deviceId dataUsingEncoding:NSUTF8StringEncoding] forKey:(__bridge id)kSecValueData];
	
	NSDictionary *tempQuery = [NSDictionary dictionaryWithDictionary:genericPasswordQuery];
	OSStatus st = SecItemAdd((__bridge CFDictionaryRef)tempQuery, NULL);
	if (st != noErr)
	{
		PWLog(@"error during saving persistent identifier");
	}
}

- (NSString *) readDeviceId {
	NSString *ident = [[[NSBundle mainBundle] objectForInfoDictionaryKey:(__bridge id)kCFBundleIdentifierKey] stringByAppendingString:@".DeviceId"];
	
	NSMutableDictionary *genericPasswordQuery = [[NSMutableDictionary alloc] init];
	
	[genericPasswordQuery setObject:(__bridge id)kSecClassGenericPassword forKey:(__bridge id)kSecClass];
	[genericPasswordQuery setObject:ident forKey:(__bridge id)kSecAttrService];
	[genericPasswordQuery setObject:ident forKey:(__bridge id)kSecAttrAccount];
	
	[genericPasswordQuery setObject:(__bridge id)kSecMatchLimitOne forKey:(__bridge id)kSecMatchLimit];
	[genericPasswordQuery setObject:(__bridge id)kCFBooleanTrue forKey:(__bridge id)kSecReturnData];
	
	NSDictionary *tempQuery = [NSDictionary dictionaryWithDictionary:genericPasswordQuery];
	
	CFDataRef pwdData = NULL;
	if (SecItemCopyMatching((__bridge CFDictionaryRef)tempQuery, (CFTypeRef *)&pwdData) == noErr)
	{
        NSData *result = (__bridge_transfer NSData *)pwdData;
        NSString *password = [[NSString alloc] initWithBytes:[result bytes] length:[result length]
													encoding:NSUTF8StringEncoding];
		return password;
	}
	return nil;
}

- (NSString *) uniqueGlobalDeviceIdentifier{
    NSString *deviceId = objc_getAssociatedObject(self, &kDeviceIdKey);
    
	if (deviceId == nil) {
		deviceId = [self readDeviceId];
		objc_setAssociatedObject(self, &kDeviceIdKey, deviceId, OBJC_ASSOCIATION_RETAIN);
	}
	if (deviceId == nil) {
		deviceId = [self generateIdentifier];
		[self writeDeviceID:deviceId];
		objc_setAssociatedObject(self, &kDeviceIdKey, deviceId, OBJC_ASSOCIATION_RETAIN);
	}
    
	return deviceId;
}

////////////////////////////////////////////////////////////////////////////////
#pragma mark -
#pragma mark Public Methods

- (NSString *) getHWID {
	return [self uniqueGlobalDeviceIdentifier];
}

static PushNotificationManager * instance = nil;

// this method is for backward compatibility
- (id) initWithApplicationCode:(NSString *)_appCode navController:(UIViewController *) _navController appName:(NSString *)_appName {
	return [self initWithApplicationCode:_appCode appName:_appName];
}

- (id) initWithApplicationCode:(NSString *)_appCode appName:(NSString *)_appName{
	if(self = [super init]) {
		self.supportedOrientations = PWOrientationPortrait | PWOrientationPortraitUpsideDown | PWOrientationLandscapeLeft | PWOrientationLandscapeRight;
		self.appCode = _appCode;
		self.appName = _appName;
		self.richPushWindow = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
		self.richPushWindow.windowLevel = UIWindowLevelStatusBar + 1.0f;
		
		internalIndex = 0;
		pushNotifications = [[NSMutableDictionary alloc] init];
		showPushnotificationAlert = YES;

		NSNumber * showAlertObj = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"Pushwoosh_SHOW_ALERT"];
        
		if(showAlertObj && ([showAlertObj isKindOfClass:[NSNumber class]] || [showAlertObj isKindOfClass:[NSString class]])) {
			showPushnotificationAlert = [showAlertObj boolValue];
			PWLog(@"Will show push notifications alert: %d", showPushnotificationAlert);
		}
		else
		{
			PWLog(@"Will show push notifications alert");
		}
		
		[[NSUserDefaults standardUserDefaults] setObject:_appCode forKey:@"Pushwoosh_APPID"];
		if(_appName) {
			[[NSUserDefaults standardUserDefaults] setObject:_appName forKey:@"Pushwoosh_APPNAME"];
		}
		
		//initalize location tracker
		self.locationTracker = [[PWLocationTracker alloc] init];
		
#ifdef USE_IBEACONS
		self.beaconsTracker = [PWBeaconsTracker new];
#endif
		
		[self setProcessBeaconHandler];
        
		//initialize trackers
		[self.locationTracker prepareForLocationUpdates];
		
#ifdef USE_IBEACONS
		[self.beaconsTracker prepareForLocationUpdates];
#endif
		
		instance = self;
		
		// Start observing purchase transactions
		[[SKPaymentQueue defaultQueue] addTransactionObserver:self];
        
		[[NSUserDefaults standardUserDefaults] synchronize];
	}
	
	return self;
}

// handler for sending beacon events to Pushwoosh
- (void)setProcessBeaconHandler {
#ifdef USE_IBEACONS
	__weak typeof (self) wself = self;
	self.beaconsTracker.processBeaconBlock = ^(PWBeaconAction action, NSString *uuid, NSNumber *major, NSNumber *minor) {
		PWProcessBeaconRequest *request = [PWProcessBeaconRequest new];
		
		request.appId = wself.appCode;
		request.hwid = [wself uniqueGlobalDeviceIdentifier];
		request.action = action;
		request.major = major;
		request.minor = minor;
		request.uuid = uuid;
		
		[[PWRequestManager sharedManager] sendRequest:request];
	};
#endif
}

+ (void)initializeWithAppCode:(NSString *)appCode appName:(NSString *)appName {
	[[NSUserDefaults standardUserDefaults] setObject:appCode forKey:@"Pushwoosh_APPID"];
	
	if(appName) {
		[[NSUserDefaults standardUserDefaults] setObject:appName forKey:@"Pushwoosh_APPNAME"];
	}
    
	[[NSUserDefaults standardUserDefaults] synchronize];
}

//something changes in the transaction queue
- (void)paymentQueue:(SKPaymentQueue *)queue updatedTransactions:(NSArray *)transactions {
	
	NSMutableArray * productIdentifiers = [NSMutableArray new];
	self.transactionsArray = [NSMutableArray new];
	
	for (SKPaymentTransaction *transaction in transactions) {

		SKPaymentTransactionState transactionState = transaction.transactionState;
		NSString * productIdentifier = transaction.payment.productIdentifier;
		PWSendPurchaseRequest *purchaseRequest = [[PWSendPurchaseRequest alloc] init];
		purchaseRequest.appId = appCode;
		purchaseRequest.hwid = [self uniqueGlobalDeviceIdentifier];
		purchaseRequest.productIdentifier = productIdentifier;
		purchaseRequest.quantity = transaction.payment.quantity;
		purchaseRequest.transactionDate = transaction.transactionDate;
		
		//we look only for purchased transactions, not restored, not failed
		if (transaction.transactionState == SKPaymentTransactionStatePurchased) {
			//add transaction to the queue
			BOOL addProductId = YES;
			for(NSString * pi in productIdentifiers)
			{
				if([pi isEqualToString:transaction.payment.productIdentifier])
				{
					addProductId = NO;
					break;
				}
			}
			
			//we'll need product identifiers to get the price
			if(addProductId)
				[productIdentifiers addObject:transaction.payment.productIdentifier];

			[self.transactionsArray addObject:transaction];
		}
	}
	
	if(productIdentifiers.count == 0)
		return;

	//request price for product identifiers
	SKProductsRequest *productsRequest = [[SKProductsRequest alloc] initWithProductIdentifiers:[NSSet setWithArray:productIdentifiers]];
	productsRequest.delegate = self;
	[productsRequest start];
}

- (void)productsRequest:(SKProductsRequest *)request didReceiveResponse:(SKProductsResponse *)response
{
	//map the SKProduct for product identifiers
	self.productArray = [NSMutableDictionary new];
	
	for(SKProduct * product in response.products)
	{
		[self.productArray setObject:product forKey:product.productIdentifier];
	}
	
	//now we can process transactions
	[self performSelectorInBackground:@selector(sendPurchaseBackground:) withObject:self.transactionsArray];
}

+ (BOOL) getAPSProductionStatus {
	NSString * provisioning = [[NSBundle mainBundle] pathForResource:@"embedded.mobileprovision" ofType:nil];
	if(!provisioning)
		return YES;	//AppStore
	
	NSString * contents = [NSString stringWithContentsOfFile:provisioning encoding:NSASCIIStringEncoding error:nil];
	if(!contents)
		return YES;

	NSRange start = [contents rangeOfString:@"<?xml"];
	NSRange end = [contents rangeOfString:@"</plist>"];
	start.length = end.location + end.length - start.location;
	
	NSString * profile =[contents substringWithRange:start];
	if(!profile)
		return YES;
	
	NSData * profileData = [profile dataUsingEncoding:NSUTF8StringEncoding];
	NSString *error = nil;
	NSPropertyListFormat format;
	NSDictionary* plist = [NSPropertyListSerialization propertyListFromData:profileData mutabilityOption:NSPropertyListImmutable format:&format errorDescription:&error];
	
	NSDictionary * entitlements = [plist objectForKey:@"Entitlements"];
//	NSNumber * allowNumber = [entitlements objectForKey:@"get-task-allow"];
	
	//could be development or production
	NSString * apsGateway = [entitlements objectForKey:@"aps-environment"];
	
	if(!apsGateway) {
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:@"Pushwoosh Error" message:@"Your provisioning profile does not have APS entry. Please make your profile push compatible." delegate:self cancelButtonTitle:@"OK" otherButtonTitles:nil, nil];
		[alert performSelectorOnMainThread:@selector(show) withObject:nil waitUntilDone:NO];
	}
	
	if([apsGateway isEqualToString:@"development"])
		return NO;
	
	return YES;
}

+ (NSString *) getAppIdFromBundle:(BOOL)productionAPS {
	NSString * appid = nil;
	if(!productionAPS) {
		appid = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"Pushwoosh_APPID_Dev"];
		if(appid)
			return appid;
	}
	
	return [[NSBundle mainBundle] objectForInfoDictionaryKey:@"Pushwoosh_APPID"];
}

+ (PushNotificationManager *)pushManager {
	if (instance == nil) {
		NSString * appid = [self getAppIdFromBundle:[self getAPSProductionStatus]];
		
		if (!appid) {
			appid = [[NSUserDefaults standardUserDefaults] objectForKey:@"Pushwoosh_APPID"];
            
			if(!appid) {
				return nil;
			}
		}
		
		NSString * appname = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"Pushwoosh_APPNAME"];
		
		if(!appname)
			appname = [[NSUserDefaults standardUserDefaults] objectForKey:@"Pushwoosh_APPNAME"];
		
		if(!appname)
			appname = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
		
		if(!appname)
			appname = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
		
		if(!appname) {
			appname = @"";
		}
		
		instance = [[PushNotificationManager alloc] initWithApplicationCode:appid appName:appname];
	}
	
	return instance;
}

int getPushNotificationMode() {
	//default push modes
	int modes = UIRemoteNotificationTypeBadge | UIRemoteNotificationTypeSound | UIRemoteNotificationTypeAlert;
	
	//add newsstand mode if info.plist supports it
	NSArray * backgroundModes = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"UIBackgroundModes"];
	for(NSString *mode in backgroundModes) {
		if([mode isEqualToString:@"newsstand-content"]) {
			modes |= UIRemoteNotificationTypeNewsstandContentAvailability;
			break;
		}
	}
	
	return modes;
}

- (void) registerForPushNotifications {
	int modes = getPushNotificationMode();
	
#ifdef __IPHONE_8_0
	if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0)
	{
		UIUserNotificationType types = UIUserNotificationTypeSound | UIUserNotificationTypeAlert | UIUserNotificationTypeBadge;
		UIUserNotificationSettings * pushSettings = [UIUserNotificationSettings settingsForTypes:types categories:nil];
		
		[[UIApplication sharedApplication] registerUserNotificationSettings:pushSettings];
		[[UIApplication sharedApplication] registerForRemoteNotifications];
	}
	else
#endif
	{
		[[UIApplication sharedApplication] registerForRemoteNotificationTypes:modes];
	}
}

- (void) unregisterForPushNotifications {
	[[UIApplication sharedApplication] unregisterForRemoteNotifications];
	
	[self unregisterDevice];
}

- (void) showPushPage:(NSString *)pageId {
    [self showHTMLViewControllerWithURLString:[NSString stringWithFormat:kServiceHtmlContentFormatUrl, pageId]];
}

- (void) showCustomPushPage:(NSString *)page {
	[self showHTMLViewControllerWithURLString:page];
}

- (void)showHTMLViewControllerWithURLString:(NSString *)urlString {
	PWHtmlWebViewController *vc = [[PWHtmlWebViewController alloc] initWithURLString:urlString];
	vc.delegate = self;
	vc.supportedOrientations = supportedOrientations;
	
	self.richPushWindow.rootViewController = vc;
    [vc view];
}

- (void) showWebView {
	self.richPushWindow.hidden = NO;
    
    CGAffineTransform originalTransform = self.richPushWindow.rootViewController.view.transform;
    self.richPushWindow.rootViewController.view.alpha = 0.0f;
    self.richPushWindow.rootViewController.view.transform = CGAffineTransformConcat(originalTransform, CGAffineTransformMakeScale(0.01f, 0.01f));
    
    [UIView animateWithDuration:0.3
                          delay:0
                        options:UIViewAnimationOptionCurveEaseIn
                     animations:^{
                         self.richPushWindow.rootViewController.view.transform = CGAffineTransformConcat(originalTransform, CGAffineTransformMakeScale(1.0f, 1.0f));
                         self.richPushWindow.rootViewController.view.alpha = 1.0f;
                     }
                     completion:nil];
}

- (void) hidePushWindow {
	[UIView animateWithDuration:0.3
                          delay:0
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
                         self.richPushWindow.rootViewController.view.transform = CGAffineTransformScale(self.richPushWindow.rootViewController.view.transform, 0.01f, 0.01f);
                         self.richPushWindow.rootViewController.view.alpha = 0.0f;
                     }
                     completion:^(BOOL finished) {
                         self.richPushWindow.hidden = YES;
                         self.richPushWindow.rootViewController = nil;
                     }];
}

- (void)htmlWebViewControllerReadyForShow:(PWHtmlWebViewController *)viewController {
    [self showWebView];
}

- (void)htmlWebViewControllerDidClose:(PWHtmlWebViewController *)viewController {
	[self hidePushWindow];
}

- (void) sendDevTokenToServer:(NSString *)deviceID {

	@autoreleasepool {
		NSString * appLocale = @"en";
		NSLocale * locale = (NSLocale *)CFBridgingRelease(CFLocaleCopyCurrent());
		NSString * localeId = [locale localeIdentifier];
	
		if([localeId length] > 2)
			localeId = [localeId stringByReplacingCharactersInRange:NSMakeRange(2, [localeId length]-2) withString:@""];
		
		appLocale = localeId;
		
		NSArray * languagesArr = (NSArray *) CFBridgingRelease(CFLocaleCopyPreferredLanguages());	
		if([languagesArr count] > 0)
		{
			NSString * value = [languagesArr objectAtIndex:0];
		
			if([value length] > 2)
				value = [value stringByReplacingCharactersInRange:NSMakeRange(2, [value length]-2) withString:@""];
			
			appLocale = [value copy];
		}
		
		PWRegisterDeviceRequest *request = [[PWRegisterDeviceRequest alloc] init];
		request.appId = appCode;
		request.hwid = [self uniqueGlobalDeviceIdentifier];
		request.pushToken = deviceID;
		request.language = appLocale;
		request.timeZone = [NSString stringWithFormat:@"%ld", (long)[[NSTimeZone localTimeZone] secondsFromGMT]];
		request.appVersion = [[NSBundle mainBundle] objectForInfoDictionaryKey: @"CFBundleShortVersionString"];
	
		NSError *error = nil;
		if ([[PWRequestManager sharedManager] sendRequest:request error:&error]) {
			PWLog(@"Registered for push notifications: %@", deviceID);

			if([delegate respondsToSelector:@selector(onDidRegisterForRemoteNotificationsWithDeviceToken:)] ) {
				[delegate performSelectorOnMainThread:@selector(onDidRegisterForRemoteNotificationsWithDeviceToken:) withObject:[self getPushToken] waitUntilDone:NO];
			}
		} else {
			PWLog(@"Registered for push notifications failed");

			if([delegate respondsToSelector:@selector(onDidFailToRegisterForRemoteNotificationsWithError:)] ) {
				[delegate performSelectorOnMainThread:@selector(onDidFailToRegisterForRemoteNotificationsWithError:) withObject:error waitUntilDone:NO];
			}
		}
	}
}

- (void) unregisterDevice {
	@autoreleasepool {
		dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
			
			PWUnregisterDeviceRequest *request = [PWUnregisterDeviceRequest new];
			request.appId = appCode;
			request.hwid = [self uniqueGlobalDeviceIdentifier];
			
			NSError *error = nil;
			if ([[PWRequestManager sharedManager] sendRequest:request error:&error]) {
				PWLog(@"Unregistered for push notifications");
			} else {
				PWLog(@"Unregistering for push notifications failed");
			}
		});
	}
}

- (void) handlePushRegistrationString:(NSString *)deviceID {
	
	[[NSUserDefaults standardUserDefaults] setObject:deviceID forKey:@"PWPushUserId"];
	
	[self performSelectorInBackground:@selector(sendDevTokenToServer:) withObject:deviceID];
    
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (void) handlePushRegistration:(NSData *)devToken {
	NSMutableString *deviceID = [NSMutableString stringWithString:[devToken description]];
	
	//Remove <, >, and spaces
	[deviceID replaceOccurrencesOfString:@"<" withString:@"" options:1 range:NSMakeRange(0, [deviceID length])];
	[deviceID replaceOccurrencesOfString:@">" withString:@"" options:1 range:NSMakeRange(0, [deviceID length])];
	[deviceID replaceOccurrencesOfString:@" " withString:@"" options:1 range:NSMakeRange(0, [deviceID length])];
	
	[[NSUserDefaults standardUserDefaults] setObject:deviceID forKey:@"PWPushUserId"];
	
	[self performSelectorInBackground:@selector(sendDevTokenToServer:) withObject:deviceID];
    
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (void) handlePushRegistrationFailure:(NSError *) error {
	if([delegate respondsToSelector:@selector(onDidFailToRegisterForRemoteNotificationsWithError:)] ) {
		[delegate performSelectorOnMainThread:@selector(onDidFailToRegisterForRemoteNotificationsWithError:) withObject:error waitUntilDone:NO];
	}
}

- (NSString *) getPushToken {
	return [[NSUserDefaults standardUserDefaults] objectForKey:@"PWPushUserId"];
}

#pragma mark URL redirect handling flow

//This method is added to work with shorten urls
//According to ios 6, if user isn't logged in appstore, then when safari opens itunes url system will ask permission to run appstore.
//But still if application open appstore url, system will open it without any alerts.
- (void) openUrl: (NSURL *) url {
	//When opening nsurlconnection to some url if it has some redirect, then connection will ask delegate what to do.
	//But if url has no redirects, then THIS CODE WILL NOT WORK.
	//
	//Pushwoosh.com guarantee that any http/https url is shorten URL.
	//Unshort url and open it by usual way.
	if ([[url scheme] hasPrefix:@"http"]) {
		NSURLConnection *connection  = [[NSURLConnection alloc] initWithRequest:[NSMutableURLRequest requestWithURL:url] delegate:self];
		if (!connection) {
			return;
		}
		return;
	}
	
	//If url has cusmtom scheme like facebook:// or itms:// we need to open it directly:
	//small hack to prevent app freeezes on iOS7
	//see: http://stackoverflow.com/questions/19356488/openurl-freezes-app-for-over-10-seconds
	dispatch_async(dispatch_get_main_queue(), ^{
		[[UIApplication sharedApplication] openURL:url];
	});
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)response {
	PWLog(@"Url: %@", [response URL]);

	//as soon as all the redirects finished we can open the final URL
	dispatch_async(dispatch_get_main_queue(), ^{
		[[UIApplication sharedApplication] openURL:[response URL]];
	});
}

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
	NSURL *url = [[error userInfo] objectForKey:@"NSErrorFailingURLKey"];
	
	//maybe itms:// or facebook:// url was shortened, try to open it directly
	if (![[url scheme] hasPrefix:@"http"]) {
		dispatch_async(dispatch_get_main_queue(), ^{
			[[UIApplication sharedApplication] openURL:url];
		});
	}
}

#pragma mark -
- (void)alertView:(UIAlertView *)alertView clickedButtonAtIndex:(NSInteger)buttonIndex {
	if(buttonIndex != 1) {
		if(!alertView.tag)
			return;
		
		[pushNotifications removeObjectForKey:[NSNumber numberWithLong:alertView.tag]];
		return;
	}
	
	NSDictionary *lastPushDict = [pushNotifications objectForKey:[NSNumber numberWithLong:alertView.tag]];
    
	[self processUserInfo:lastPushDict];
    
	if([delegate respondsToSelector:@selector(onPushAccepted: withNotification:)] ) {
		[delegate onPushAccepted:self withNotification:lastPushDict];
	}
	else
		if([delegate respondsToSelector:@selector(onPushAccepted: withNotification: onStart:)] ) {
			[delegate onPushAccepted:self withNotification:lastPushDict onStart:NO];
		}
	
	[pushNotifications removeObjectForKey:[NSNumber numberWithLong:alertView.tag]];
}

- (void)processUserInfo:(NSDictionary *)userInfo {
    NSString *htmlPageId = [userInfo objectForKey:@"h"];
	NSString *linkUrl = [userInfo objectForKey:@"l"];
	NSString *customHtmlPageId = [userInfo objectForKey:@"r"];
    
    if(htmlPageId) {
		[self showPushPage:htmlPageId];
	}
	else if(customHtmlPageId) {
		[self showCustomPushPage:customHtmlPageId];
	}
    
	if (linkUrl) {
		[self openUrl:[NSURL URLWithString:linkUrl]];
	}
}

- (BOOL) handlePushReceived:(NSDictionary *)userInfo {
	BOOL isPushOnStart = NO;
	BOOL needToShowAlert = showPushnotificationAlert;
	NSDictionary *pushDict = [userInfo objectForKey:@"aps"];

	if(!pushDict) {
		if ([userInfo objectForKey:UIApplicationLaunchOptionsLocationKey]) {
			NSNumber * trackingEnabled = [[NSUserDefaults standardUserDefaults] objectForKey:@"Pushwoosh_TrackingEnabled"];
			//Make sure we did track locations before
			if(trackingEnabled != nil && [trackingEnabled integerValue] != 0)
			{
				[self startLocationTracking];
			}
		}
        
		//try as launchOptions dictionary
		userInfo = [userInfo objectForKey:UIApplicationLaunchOptionsRemoteNotificationKey];
		pushDict = [userInfo objectForKey:@"aps"];
		isPushOnStart = YES;
	}
    
	if (!pushDict)
		return NO;
    
	//check if the app transitioning from inactive to active state
	if([[UIApplication sharedApplication] respondsToSelector:@selector(applicationState)]) {
		UIApplicationState appState = [[UIApplication sharedApplication] applicationState];
		switch(appState)
		{
			//transitioning from inactive to active state
			case UIApplicationStateInactive:
				isPushOnStart = YES;
				break;

			//the app is running in background
			case UIApplicationStateBackground:
				isPushOnStart = NO;
				needToShowAlert = NO;	//we cannot display alerts in background anyway
				break;

			default:
				break;
		}
	}
	
	//application:didReceiveRemoteNotification:fetchCompletionHandler: will trigger another
	//the same push notification on start.
	NSString *hash = [userInfo objectForKey:@"p"];
	if([hash isEqualToString:self.lastPushMessageHash])
		return NO;

	self.lastPushMessageHash = hash;
	
	[self performSelectorInBackground:@selector(sendStatsBackground:) withObject:hash];
	
	if([delegate respondsToSelector:@selector(onPushReceived: withNotification: onStart:)] ) {
		[delegate onPushReceived:self withNotification:userInfo onStart:isPushOnStart];
		return YES;
	}

	NSString *alertMsg = [pushDict objectForKey:@"alert"];
	
	bool msgIsString = YES;
	if(![alertMsg isKindOfClass:[NSString class]])
		msgIsString = NO;
    
	//the app is running, display alert only
	if(!isPushOnStart && needToShowAlert && msgIsString) {
		UIAlertView *alert = [[UIAlertView alloc] initWithTitle:self.appName message:alertMsg delegate:self cancelButtonTitle:@"Cancel" otherButtonTitles:@"OK", nil];
		alert.tag = ++internalIndex;
		[pushNotifications setObject:userInfo forKey:[NSNumber numberWithLong:internalIndex]];
		[alert show];
		return YES;
	}
	
	[self processUserInfo:userInfo];
    
	if ([delegate respondsToSelector:@selector(onPushAccepted: withNotification:)] ) {
		[delegate onPushAccepted:self withNotification:userInfo];
	}
	else if ([delegate respondsToSelector:@selector(onPushAccepted: withNotification: onStart:)] ) {
        [delegate onPushAccepted:self withNotification:userInfo onStart:isPushOnStart];
    }
	
	return YES;
}

- (NSDictionary *) getApnPayload:(NSDictionary *)pushNotification {
	return [pushNotification objectForKey:@"aps"];
}

- (NSString *) getCustomPushData:(NSDictionary *)pushNotification {
	return [pushNotification objectForKey:@"u"];
}

- (void) sendStatsBackground:(NSString *)hash {

	@autoreleasepool {
		PWPushStatRequest *request = [[PWPushStatRequest alloc] init];
		request.appId = appCode;
		request.hash = hash;
		request.hwid = [self uniqueGlobalDeviceIdentifier];
	
		if ([[PWRequestManager sharedManager] sendRequest:request]) {
			PWLog(@"sendStats completed");
		} else {
			PWLog(@"sendStats failed");
		}
	}
}

- (void) sendTagsBackground: (NSDictionary *) tags {

	@autoreleasepool {
		PWSetTagsRequest *request = [[PWSetTagsRequest alloc] init];
		request.appId = appCode;
		request.hwid = [self uniqueGlobalDeviceIdentifier];
		request.tags = tags;
	
		if ([[PWRequestManager sharedManager] sendRequest:request]) {
			PWLog(@"setTags completed");
		} else {
			PWLog(@"setTags failed");
		}
	}
}

- (void) sendLocationBackground: (CLLocation *) location {
	@autoreleasepool {
		PWLog(@"Sending location: %@", location);
		PWGetNearestZoneRequest *request = [[PWGetNearestZoneRequest alloc] init];
		request.appId = appCode;
		request.hwid = [self uniqueGlobalDeviceIdentifier];
		request.userCoordinate = location.coordinate;

		if ([[PWRequestManager sharedManager] sendRequest:request]) {
			PWLog(@"getNearestZone completed");
			self.locationTracker.nearestGeozone = request.nearestGeozone;
		} else {
			PWLog(@"getNearestZone failed");
		}
		
		PWLog(@"Location sent");
	}
}

- (void) sendLocation: (CLLocation *) location {
	[self performSelectorInBackground:@selector(sendLocationBackground:) withObject:location];
}

- (void) sendAppOpenBackground {
	//it's ok to call this method without push token
	@autoreleasepool {
		PWAppOpenRequest *request = [[PWAppOpenRequest alloc] init];
		request.appId = appCode;
		request.hwid = [self uniqueGlobalDeviceIdentifier];
	
		if ([[PWRequestManager sharedManager] sendRequest:request]) {
			PWLog(@"sending appOpen completed");
		} else {
			PWLog(@"sending appOpen failed");
		}
	}
}

- (void) sendBadgesBackground: (NSNumber *) badge {
	if([[PushNotificationManager pushManager] getPushToken] == nil)
		return;
	
	@autoreleasepool {

		PWSendBadgeRequest *request = [[PWSendBadgeRequest alloc] init];
		request.appId = appCode;
		request.hwid = [self uniqueGlobalDeviceIdentifier];
		request.badge = [badge intValue];
		
		if ([[PWRequestManager sharedManager] sendRequest:request]) {
			PWLog(@"setBadges completed");
		} else {
			PWLog(@"setBadges failed");
		}
	}
}

- (void) sendGoalBackground: (PWApplicationEventRequest *) request {
	
	@autoreleasepool {
		
		if ([[PWRequestManager sharedManager] sendRequest:request]) {
			PWLog(@"sendGoals completed");
		} else {
			PWLog(@"sendGoals failed");
		}
	}
}

- (void)sendPurchaseBackground:(NSArray *)transactions {
	
	@autoreleasepool {

		for(SKPaymentTransaction * transaction in transactions)
		{
			NSString * productIdentifier = transaction.payment.productIdentifier;
			SKProduct * product = [self.productArray objectForKey:productIdentifier];
			if(!product)
			{
				NSLog(@"Could not find product for transaction: %@", productIdentifier);
				continue;
			}

			NSDecimalNumber * price = product.price;
			if(!price)
				price = [NSDecimalNumber zero];
			
			NSString *currencyCode = [product.priceLocale objectForKey:NSLocaleCurrencyCode];
			if(!currencyCode)
				currencyCode = @"USD";
			
			PWSendPurchaseRequest *purchaseRequest = [[PWSendPurchaseRequest alloc] init];
			purchaseRequest.appId = appCode;
			purchaseRequest.hwid = [self uniqueGlobalDeviceIdentifier];
			purchaseRequest.productIdentifier = productIdentifier;
			purchaseRequest.quantity = transaction.payment.quantity;
			purchaseRequest.transactionDate = transaction.transactionDate;
			purchaseRequest.price = price;
			purchaseRequest.currencyCode = currencyCode;

			if ([[PWRequestManager sharedManager] sendRequest:purchaseRequest]) {
				PWLog(@"sendPurchase completed");
			} else {
				PWLog(@"sendPurchase failed");
			}
		}
	}
}

- (void) sendBadges: (NSInteger) badge {
	[self performSelectorInBackground:@selector(sendBadgesBackground:) withObject:[NSNumber numberWithLong:badge]];
}

- (void) sendAppOpen {
	[self performSelectorInBackground:@selector(sendAppOpenBackground) withObject:nil];
}

- (void) setTags: (NSDictionary *) tags {
	if (![tags isKindOfClass:[NSDictionary class]]) {
		PWLog(@"tags must be NSDictionary");
		return;
	}
    
	[self performSelectorInBackground:@selector(sendTagsBackground:) withObject:tags];
}

- (void) loadTags {
	[self loadTags:nil error:nil];
}

- (void) loadTags: (pushwooshGetTagsHandler) successHandler error:(pushwooshErrorHandler) errorHandler{
	dispatch_queue_t queue = dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0ul);
	dispatch_async(queue, ^{
		PWGetTagsRequest *request = [[PWGetTagsRequest alloc] init];
		request.appId = appCode;
		request.hwid = [self uniqueGlobalDeviceIdentifier];
		
		NSError *error = nil;
		if ([[PWRequestManager sharedManager] sendRequest:request error:&error]) {
			PWLog(@"loadTags completed");
			
			dispatch_async(dispatch_get_main_queue(), ^{
				if([delegate respondsToSelector:@selector(onTagsReceived:)] ) {
					[delegate onTagsReceived:request.tags];
				}
				
				if(successHandler) {
					successHandler(request.tags);
				}
			});
			
		} else {
			PWLog(@"loadTags failed");
			
			dispatch_async(dispatch_get_main_queue(), ^{
				if([delegate respondsToSelector:@selector(onTagsFailedToReceive:)] ) {
					[delegate onTagsFailedToReceive:error];
				}
				
				if(errorHandler) {
					errorHandler(error);
				}
			});
		}
		
		request = nil;
	});
}

- (void) recordGoal: (NSString *) goal {
	[self recordGoal:goal withCount:nil];
}

- (void) recordGoal: (NSString *) goal withCount: (NSNumber *) count {
	PWApplicationEventRequest *request = [[PWApplicationEventRequest alloc] init];
	request.appId = appCode;
	request.hwid = [self uniqueGlobalDeviceIdentifier];
	request.goal = goal;
	request.count = count;
	[self performSelectorInBackground:@selector(sendGoalBackground:) withObject:request];
}

//clears the notifications from the notification center
+ (void) clearNotificationCenter {
	
	UIApplication* application = [UIApplication sharedApplication];
	NSArray* scheduledNotifications = [NSArray arrayWithArray:application.scheduledLocalNotifications];
	application.scheduledLocalNotifications = scheduledNotifications;
}

//start location tracking. this is battery efficient and uses network triangulation in background
- (void)startLocationTracking {
    
    //if OS run application, we should not run again all stuff for geolocation. Just create CLLocationManager in locationTracker - in this step it already done.
    if ([UIApplication sharedApplication].applicationState == UIApplicationStateBackground) {
        return;
    }
    
    self.locationTracker.enabled = YES;
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInt:1] forKey:@"Pushwoosh_TrackingEnabled"];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (void) startBeaconTracking {
#ifdef USE_IBEACONS
    if (kSystemVersion >= 7) {
        PWGetBeaconsRequest *request = [PWGetBeaconsRequest new];
        request.appId = self.appCode;
        request.hwid = [self uniqueGlobalDeviceIdentifier];
        
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [[PWRequestManager sharedManager] sendRequest:request];
            
            dispatch_async(dispatch_get_main_queue(), ^{
                self.beaconsTracker.proximityUUID = request.uuid; //@"D0DE0233-78D0-456F-90C7-24CF47F862B5";
                self.beaconsTracker.indoorOffset = (request.indoorOffset > 0) ? request.indoorOffset : 120;
                self.beaconsTracker.enabled = YES;
            });
        });
    }
#endif
}

//stops location tracking
- (void) stopLocationTracking {
	self.locationTracker.enabled = NO;
	[[NSUserDefaults standardUserDefaults] setObject:[NSNumber numberWithInt:0] forKey:@"Pushwoosh_TrackingEnabled"];
	[[NSUserDefaults standardUserDefaults] synchronize];
}

- (void) stopBeaconTracking {
#ifdef USE_IBEACONS
	self.beaconsTracker.enabled = NO;
#endif
}


- (void) dealloc {
	[[SKPaymentQueue defaultQueue] removeTransactionObserver:self];
	
	self.delegate = nil;
}

@end
