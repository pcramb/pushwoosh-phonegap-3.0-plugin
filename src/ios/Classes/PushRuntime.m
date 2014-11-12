//
//  PushRuntime.m
//  Pushwoosh SDK
//  (c) Pushwoosh 2012
//

#import "PushRuntime.h"
#import "PushNotificationManager.h"
#import <objc/runtime.h>

#if ! __has_feature(objc_arc)
#error "ARC is required to compile Pushwoosh SDK"
#endif

@interface UIApplication(InternalPushRuntime)
- (NSObject<PushNotificationDelegate> *)getPushwooshDelegate;
- (BOOL) pushwooshUseRuntimeMagic;	//use runtime to handle default push notifications callbacks (used in plugins)
@end

static void swizzle(Class class, SEL fromChange, SEL toChange, IMP impl, const char * signature)
{
	Method method = nil;
	method = class_getInstanceMethod(class, fromChange);
	
	if (method) {
		//method exists add a new method and swap with original
		class_addMethod(class, toChange, impl, signature);
		method_exchangeImplementations(class_getInstanceMethod(class, fromChange), class_getInstanceMethod(class, toChange));
	} else {
		//just add as orignal method
		class_addMethod(class, fromChange, impl, signature);
	}
}

static NSNumber *debugLoggingEnabled = nil;

void PWLog(NSString *format, ...) {
    if (!debugLoggingEnabled) {
        debugLoggingEnabled = @(YES);
        
        NSNumber *loggingEnabled = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"Pushwoosh_DEBUG"];
        
        if (loggingEnabled) {
            debugLoggingEnabled = loggingEnabled;
        }
    }
    
    if (!debugLoggingEnabled.boolValue) {
        return;
    }
    
    va_list ap;
    
    va_start (ap, format);
    
    if (![format hasSuffix: @"\n"]) {
        format = [format stringByAppendingString: @"\n"];
    }
    
    NSString *body = [[NSString alloc] initWithFormat:format arguments:ap];
    
    NSLog(@"%@", body);
    
    va_end (ap);
}

@implementation UIApplication(Pushwoosh)

BOOL dynamicDidFinishLaunching(id self, SEL _cmd, id application, id launchOptions) {
	BOOL result = YES;
    
	if ([self respondsToSelector:@selector(application:pw_didFinishLaunchingWithOptions:)]) {
		result = (BOOL) [self application:application pw_didFinishLaunchingWithOptions:launchOptions];
	} else {
		[self applicationDidFinishLaunching:application];
		result = YES;
	}
	
	if(![PushNotificationManager pushManager].delegate) {
		if([[UIApplication sharedApplication] respondsToSelector:@selector(getPushwooshDelegate)])
		{
			[PushNotificationManager pushManager].delegate = [[UIApplication sharedApplication] getPushwooshDelegate];
		}
		else
		{
			[PushNotificationManager pushManager].delegate = (NSObject<PushNotificationDelegate> *)self;
		}
	}

	//this function will also handle UIApplicationLaunchOptionsLocationKey
	[[PushNotificationManager pushManager] handlePushReceived:launchOptions];
	[[PushNotificationManager pushManager] sendAppOpen];
	
	return result;
}

void dynamicDidRegisterForRemoteNotificationsWithDeviceToken(id self, SEL _cmd, id application, id devToken) {
	if ([self respondsToSelector:@selector(application:pw_didRegisterForRemoteNotificationsWithDeviceToken:)]) {
		[self application:application pw_didRegisterForRemoteNotificationsWithDeviceToken:devToken];
	}
	
	[[PushNotificationManager pushManager] handlePushRegistration:devToken];
}

void dynamicDidFailToRegisterForRemoteNotificationsWithError(id self, SEL _cmd, id application, id error) {
	if ([self respondsToSelector:@selector(application:pw_didFailToRegisterForRemoteNotificationsWithError:)]) {
		[self application:application pw_didFailToRegisterForRemoteNotificationsWithError:error];
	}
	
	PWLog(@"Error registering for push notifications. Error: %@", error);
	
	[[PushNotificationManager pushManager] handlePushRegistrationFailure:error];
}

void dynamicDidReceiveRemoteNotification(id self, SEL _cmd, id application, id userInfo) {
	if ([self respondsToSelector:@selector(application:pw_didReceiveRemoteNotification:)]) {
		[self application:application pw_didReceiveRemoteNotification:userInfo];
	}
	
	[[PushNotificationManager pushManager] handlePushReceived:userInfo];
}

void dynamicDidReceiveRemoteNotificationWithFetch(id self, SEL _cmd, id application, id userInfo, void (^completionHandler)(UIBackgroundFetchResult)) {
	if ([self respondsToSelector:@selector(application:pw_didReceiveRemoteNotification:fetchCompletionHandler:)]) {
		[self application:application pw_didReceiveRemoteNotification:userInfo fetchCompletionHandler:completionHandler];
	}
	
	[[PushNotificationManager pushManager] handlePushReceived:userInfo];
	completionHandler(UIBackgroundFetchResultNewData);
}

- (void) pw_setDelegate:(id<UIApplicationDelegate>)delegate {
    BOOL useRuntime = [[[NSBundle mainBundle] objectForInfoDictionaryKey:@"Pushwoosh_AUTO"] boolValue];
    
	//override runtime functions only if requested (used in plugins or by user decision)

    if (![[UIApplication sharedApplication] respondsToSelector:@selector(pushwooshUseRuntimeMagic)] && !useRuntime) {
        [self pw_setDelegate:delegate];
        return;
    }
    
	static Class delegateClass = nil;
	
	//do not swizzle the same class twice
	if(delegateClass == [delegate class])
	{
		[self pw_setDelegate:delegate];
		return;
	}
	
	delegateClass = [delegate class];
	
	swizzle([delegate class], @selector(application:didFinishLaunchingWithOptions:),
		   @selector(application:pw_didFinishLaunchingWithOptions:), (IMP)dynamicDidFinishLaunching, "v@:::");

	swizzle([delegate class], @selector(application:didRegisterForRemoteNotificationsWithDeviceToken:),
		   @selector(application:pw_didRegisterForRemoteNotificationsWithDeviceToken:), (IMP)dynamicDidRegisterForRemoteNotificationsWithDeviceToken, "v@:::");

	swizzle([delegate class], @selector(application:didFailToRegisterForRemoteNotificationsWithError:),
		   @selector(application:pw_didFailToRegisterForRemoteNotificationsWithError:), (IMP)dynamicDidFailToRegisterForRemoteNotificationsWithError, "v@:::");

	swizzle([delegate class], @selector(application:didReceiveRemoteNotification:),
		   @selector(application:pw_didReceiveRemoteNotification:), (IMP)dynamicDidReceiveRemoteNotification, "v@:::");

	swizzle([delegate class], @selector(application:didReceiveRemoteNotification:fetchCompletionHandler:),
		   @selector(application:pw_didReceiveRemoteNotification:fetchCompletionHandler:), (IMP)dynamicDidReceiveRemoteNotificationWithFetch, "v@::::");

	[self pw_setDelegate:delegate];
}

- (void) pw_setApplicationIconBadgeNumber:(NSInteger) badgeNumber {
	[self pw_setApplicationIconBadgeNumber:badgeNumber];
	
	[[PushNotificationManager pushManager] sendBadges:badgeNumber];
}

+ (void) load {

	//make sure app badges work
	method_exchangeImplementations(class_getInstanceMethod(self, @selector(setApplicationIconBadgeNumber:)), class_getInstanceMethod(self, @selector(pw_setApplicationIconBadgeNumber:)));

	method_exchangeImplementations(class_getInstanceMethod(self, @selector(setDelegate:)), class_getInstanceMethod(self, @selector(pw_setDelegate:)));
	
	UIApplication *app = [UIApplication sharedApplication];
    
    PWLog(@"Initializing application: %@ %@", app, app.delegate);
}

@end
