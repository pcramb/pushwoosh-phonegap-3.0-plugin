//
//  PWBaseTracker.h
//  PushNotificationManager
//
//	Pushwoosh SDK
//  (c) Pushwoosh 2014
//

#import "Constants.h"

#import <CoreLocation/CoreLocation.h>

//Base class with helper functions for location and beacons tracking
@interface PWBaseTracker : NSObject <CLLocationManagerDelegate>

@property (nonatomic, strong) CLLocationManager *locationManager;
@property (nonatomic, assign) BOOL enabled;
@property (nonatomic, assign) BOOL loggingEnabled;

//initializes location tracker manager
- (void)prepareForLocationUpdates;

//logs the message to the log file and console
- (void)log:(NSString *)message;

//if location services have been authorized
- (BOOL)locationServiceAuthorized;

//returns YES by default
- (BOOL)shouldHandleRegion:(CLRegion *)region;

//start background task helper function
- (NSNumber *)startBackgroundTask;

//stop background task helper function
- (void)stopBackgroundTask:(NSNumber *)taskId;

//checks if the app is in background
- (BOOL)isInBackground;

@end
