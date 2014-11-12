//
//  PWRegisterDeviceRequest
//  Pushwoosh SDK
//  (c) Pushwoosh 2012
//

#import "PWRegisterDeviceRequest.h"
#import "PushNotificationManager.h"
#import <sys/utsname.h>

#if ! __has_feature(objc_arc)
#error "ARC is required to compile Pushwoosh SDK"
#endif

@implementation PWRegisterDeviceRequest

- (NSString *) methodName {
	return @"registerDevice";
}

- (NSArray *) buildSoundsList {
	NSMutableArray * listOfSounds = [[NSMutableArray alloc] init];
	
	NSString * bundleRoot = [[NSBundle mainBundle] bundlePath];
    NSError * err;
    NSArray * dirContents = [[NSFileManager defaultManager] contentsOfDirectoryAtPath:bundleRoot error:&err];
    for (NSString * filename in dirContents) {
        if ([filename hasSuffix:@".wav"] || [filename hasSuffix:@".caf"] || [filename hasSuffix:@".aif"])
        {
            [listOfSounds addObject:filename];
        }
    }
	
	return listOfSounds;
}

- (NSDictionary *) requestDictionary {
	NSMutableDictionary *dict = [self baseDictionary];
	
	[dict setObject:[NSNumber numberWithInt:1] forKey:@"device_type"];
	[dict setObject:_pushToken forKey:@"push_token"];
	[dict setObject:_language forKey:@"language"];
	[dict setObject:_timeZone forKey:@"timezone"];
    
    if (_appVersion)
        [dict setObject:_appVersion forKey:@"app_version"];
    
	BOOL sandbox = ![PushNotificationManager getAPSProductionStatus];
	if(sandbox)
		[dict setObject:@"sandbox" forKey:@"gateway"];
	else
		[dict setObject:@"production" forKey:@"gateway"];

	NSString * package = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"];
	[dict setObject:package forKey:@"package"];
	
	NSArray * soundsList = [self buildSoundsList];
	[dict setObject:soundsList forKey:@"sounds"];
	
	int jail = [self isJailBroken];
	[dict setObject:[NSNumber numberWithInt:jail] forKey:@"jailbroken"];
	
	NSString * systemVersion = [[UIDevice currentDevice] systemVersion];
	[dict setObject:systemVersion forKey:@"os_version"];
	
	NSString * machineName = [PWRegisterDeviceRequest machineName];
	[dict setObject:machineName forKey:@"device_model"];

	return dict;
}

- (void) parseResponse: (NSDictionary *) response {
    
#ifdef __IPHONE_8_0
	if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0)
	{
		NSArray * iosCategories = [response objectForKey:@"iosCategories"];
		if(!iosCategories || ![iosCategories isKindOfClass:[NSArray class]])
			return;
		
		NSMutableSet *categoriesSet = [NSMutableSet set];
		for(NSDictionary * category in iosCategories) {
			NSString * categoryId = [[category objectForKey:@"categoryId"] stringValue];
			NSArray * buttons = [category objectForKey:@"buttons"];
			
			if(!categoryId || !buttons)
				return;
			
			NSMutableArray * buttonArray = [NSMutableArray array];
			int i =0;
			for(NSDictionary * button in buttons) {
				NSString * label = [button objectForKey:@"label"];
				BOOL destructive = [[button objectForKey:@"type"] boolValue];
				BOOL launchApp = [[button objectForKey:@"startApplication"] boolValue];
				
				
				UIMutableUserNotificationAction *acceptAction = [[UIMutableUserNotificationAction alloc] init];
				acceptAction.identifier = [[NSNumber numberWithInt:i++] stringValue];	//should be button id
				acceptAction.title = label;
				// Given seconds, not minutes, to run in the background
				acceptAction.activationMode = launchApp ? UIUserNotificationActivationModeForeground : UIUserNotificationActivationModeBackground;
				acceptAction.destructive = destructive;
				
				// If YES requires passcode, but does not unlock the device
				acceptAction.authenticationRequired = NO;
				
				[buttonArray addObject:acceptAction];
			}
			
			UIMutableUserNotificationCategory *notificationCategory = [[UIMutableUserNotificationCategory alloc] init];
			notificationCategory.identifier = categoryId;
			
			//have to reverse it
			NSArray *buttonArrayReversed = [[buttonArray reverseObjectEnumerator] allObjects];
			
			[notificationCategory setActions:buttonArrayReversed forContext:UIUserNotificationActionContextDefault];
			[notificationCategory setActions:buttonArrayReversed forContext:UIUserNotificationActionContextMinimal];
			
			[categoriesSet addObject:notificationCategory];
		}
		
		UIUserNotificationType types = UIUserNotificationTypeSound | UIUserNotificationTypeAlert | UIUserNotificationTypeBadge;
		UIUserNotificationSettings *settings = [UIUserNotificationSettings settingsForTypes:types categories:categoriesSet];
		[[UIApplication sharedApplication] registerUserNotificationSettings:settings];
	}
#endif
}

- (int)isJailBroken {
    FILE *f = fopen("/bin/bash", "r");
    BOOL isbash = NO;
    
    if (f != NULL) {
        isbash = YES;
    }
    
    fclose(f);
    
    return isbash ? 1 : 0;
}

+ (NSString *) machineName
{
    struct utsname systemInfo;
    uname(&systemInfo);
	
    return [NSString stringWithCString:systemInfo.machine encoding:NSUTF8StringEncoding];
}

@end
