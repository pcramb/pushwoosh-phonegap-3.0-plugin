//
//  PWBaseTracker.m
//  PushNotificationManager
//
//	Pushwoosh SDK
//

#import "PWBaseTracker.h"
#import "PushRuntime.h"

//comment this line to disable location tracking for geo-push notifications and dependency on CoreLocation.framework
#define USE_LOCATION

#define LOCATIONS_FILE @"PWLocationTracking"
#define LOCATIONS_FILE_TYPE @"log"

@interface PWBaseTracker () {
    UIBackgroundTaskIdentifier _regionMonitoringBGTask;
}

@end

@implementation PWBaseTracker

#pragma mark - Setup

- (void)prepareForLocationUpdates {
    self.loggingEnabled = YES;
        
    NSNumber *logging = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"Pushwoosh_DEBUG"];
        
    if (logging) {
        self.loggingEnabled = logging.boolValue;
    }
        
#ifdef USE_LOCATION
    self.locationManager = [[CLLocationManager alloc] init];
    self.locationManager.delegate = self;
#endif
}

#pragma mark -
#pragma mark - Logging

- (void)log:(NSString *)message {
    if (!self.loggingEnabled) {
        return;
    }

    message = [NSString stringWithFormat:@"%@:\n%@\n ", NSStringFromClass([self class]), message];
    PWLog(@"%@", message);
    
    NSArray *paths = NSSearchPathForDirectoriesInDomains (NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *path = [NSString stringWithFormat:@"%@/%@.%@", documentsDirectory, LOCATIONS_FILE, LOCATIONS_FILE_TYPE];
    
    NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
    [dateFormat setDateFormat:@"yyyy/MM/dd hh:mm aaa"];
    
    if (![[NSFileManager defaultManager] fileExistsAtPath:path]) {
        PWLog(@"Creating locations log file");
        NSDate *date = [NSDate date];
       
        NSString *content = [NSString stringWithFormat:@"Location Tracker Log (%@)\n------------------------------------------------------------------\n", [dateFormat stringFromDate:date]];
        [content writeToFile:path
                  atomically:NO
                    encoding:NSStringEncodingConversionAllowLossy
                       error:nil];
        PWLog(@"Path to location file: %@", path);
    }
    
    message = [NSString stringWithFormat:@"%@: %@", [dateFormat stringFromDate:[NSDate date]], [message stringByAppendingString:@"\n"]];
    
    NSFileHandle *file = [NSFileHandle fileHandleForUpdatingAtPath:path];
    NSData *data = [message dataUsingEncoding:NSUTF8StringEncoding];
    [file seekToEndOfFile];
    [file writeData: data];
    [file closeFile];
}

#pragma mark -

- (BOOL)isInBackground {
    return [UIApplication sharedApplication].applicationState == UIApplicationStateBackground;
}

- (NSNumber *)startBackgroundTask {
    [self log:@"--------------------startBackgroundTask--------------------"];
    
    __block NSInteger regionMonitoringBGTask = [[UIApplication sharedApplication] beginBackgroundTaskWithExpirationHandler: ^{
        [[UIApplication sharedApplication] endBackgroundTask:regionMonitoringBGTask];
        regionMonitoringBGTask = UIBackgroundTaskInvalid;
    }];
	
	[self log:[NSString stringWithFormat:@"started task: %ld", (long)regionMonitoringBGTask]];
	return @(regionMonitoringBGTask);
}

- (void)stopBackgroundTask:(NSNumber *)taskId {
    if (!taskId || [taskId integerValue] == UIBackgroundTaskInvalid)
	{
		[self log:@"Empty task id to stop!"];
		return;
	}
	
	[self log:@"--------------------stopBackgroundTask--------------------"];
	[self log:[NSString stringWithFormat:@"stopping task: %ld", (long)[taskId integerValue]]];
	
	[[UIApplication sharedApplication] endBackgroundTask:[taskId integerValue]];
}

- (BOOL)shouldHandleRegion:(CLRegion *)region {
    return YES;
}

- (BOOL)locationServiceAuthorized {
    BOOL result = ([CLLocationManager authorizationStatus] != kCLAuthorizationStatusDenied && [CLLocationManager authorizationStatus] != kCLAuthorizationStatusRestricted);
    
    if (!result) {
        [self log:@"Please authorize app for using location services"];
    }
    
    return result;
}

@end
