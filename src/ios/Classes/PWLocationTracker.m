//
//  PWLocationTracker.m
//  Pushwoosh SDK
//

#import "PWLocationTracker.h"
#import "PWGetBeaconsRequest.h"
#import "PushNotificationManager.h"

@interface PushNotificationManager(Helper)
- (void) sendLocationBackground: (CLLocation *) location;
@end

#define kUserPositionRegionIdentifier   @"com.pushwoosh.userPositionRegion"
#define kNearestGeozoneRegionIdentifier @"com.pushwoosh.nearestGeozoneRegion"

#define kUserPositionRegionRadius 100

#define kDeferredUpdatesInterval 30
#define kDeferredUpdatesMaxCount 3

static CGFloat const kMinUpdateDistance    = 10.f;
static NSTimeInterval const kMinUpdateTime = 10.f;

@interface PWLocationTracker () {
    BOOL _locationServiceEnabledInBG;
    NSInteger _totalRegionsCount, _registeredRegionsCount, _deferredUpdatesCount;
    CLLocation *_previousLocation;
	NSNumber *regionSetUpTaskId;
	NSNumber *deferredUpdatesTaskId;
}

@end

@implementation PWLocationTracker

#pragma mark - Setup

//This is a code to debug geopositioning in background
- (void) scheduleLocalNotification:(NSString *) message {
	return;
	
	UILocalNotification *localNotification = [[UILocalNotification alloc] init];
	
    // Set the fire date/time
    [localNotification setFireDate:[NSDate date]];
	
    // Setup alert notification
    [localNotification setAlertBody:message];
    localNotification.soundName = UILocalNotificationDefaultSoundName;
    [[UIApplication sharedApplication] scheduleLocalNotification:localNotification];
}

- (id)init {
    if (self = [super init]) {
		//set up a handlers so we know when app goes to foreground/background
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidBecomeActive) name:UIApplicationDidBecomeActiveNotification object:nil];
        [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidEnterBackground) name:UIApplicationDidEnterBackgroundNotification object:nil];
        
		//if we have "location" background mode in Info.plist, we can drain the battery with GPS as much as we want
        NSArray * bgModes = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"UIBackgroundModes"];
        _locationServiceEnabledInBG = NO;
        
        if ([bgModes count]) {
            for (NSString *value in bgModes) {
                if (value && [value isKindOfClass:[NSString class]]) {
                    if ([value isEqualToString:@"location"]) {
                        _locationServiceEnabledInBG = YES;
                        break;
                    }
                }
            }
        }
    }
    
    return self;
}

#pragma mark - Notification handlers

- (void)applicationDidBecomeActive {
	[self updateLocationTrackingMode];
}

- (void)applicationDidEnterBackground {
	[self scheduleLocalNotification:[NSString stringWithFormat:@"Going Background"]];
	
	[self updateLocationTrackingMode];
}

#pragma mark -
#pragma mark -

// set the appropriate accuracy for the location manager based on the nearest Pushwoosh Geozone and update nearest geozone region
- (void)setNearestGeozone:(PWGeozone *)nearestGeozone {
    _nearestGeozone = nearestGeozone;
    
    CLLocationAccuracy accuracy;
    
    if (nearestGeozone.distance > 10000.f) {
        accuracy = kCLLocationAccuracyThreeKilometers;
    }
    else if (nearestGeozone.distance  > 1000.f) {
        accuracy = kCLLocationAccuracyHundredMeters;
    }
    else {
        accuracy = kCLLocationAccuracyBest;
    }
    
    [self.locationManager setDesiredAccuracy:accuracy];
    
    [self log:[NSString stringWithFormat:@"Location sent. Nearest geozone updated: %@, <%+.6f, %+.6f>, rad: %.0fm, dist: %.0fm", nearestGeozone.name, nearestGeozone.center.latitude, nearestGeozone.center.longitude, nearestGeozone.radius, nearestGeozone.distance]];
	
	//update nearest geozone region
	[self setupRegionsForMonitoring];
}

- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    [self updateLocationTrackingMode];
}

- (void)stopUpdatingLocation {
    [self.locationManager stopUpdatingLocation];
    [self.locationManager stopMonitoringSignificantLocationChanges];
    [self stopRegionMonitoring];
}

#ifdef __IPHONE_8_0
- (void)locationManager:(CLLocationManager *)manager didChangeAuthorizationStatus:(CLAuthorizationStatus)status {
	if(status == kCLAuthorizationStatusNotDetermined)
	{
		NSLog(@"location services authorization status has not been determined yet");
		return;
	}
	
	if(status != kCLAuthorizationStatusAuthorizedAlways && status != kCLAuthorizationStatusAuthorizedWhenInUse)
	{
		NSLog(@"location services has not been authorized");
		return;
	}
	
	if (self.enabled)
		[self updateLocationTrackingMode];
}
#endif

// selects precise/approximate tracking based on the current running mode
- (void)updateLocationTrackingMode {
	
	if (!self.enabled)
		return;
    
    if (![self locationServiceAuthorized])
        return;
	
	[self stopUpdatingLocation];
	
#ifdef __IPHONE_8_0
	if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0)
	{
		if([[NSBundle mainBundle] objectForInfoDictionaryKey: @"NSLocationAlwaysUsageDescription"] != nil)
		{
			[self.locationManager requestAlwaysAuthorization];
		}
		else
		if([[NSBundle mainBundle] objectForInfoDictionaryKey: @"NSLocationWhenInUseUsageDescription"] != nil)
		{
			[self.locationManager requestWhenInUseAuthorization];
		}
		else
		{
			NSLog(@"Did you forget to add NSLocationAlwaysUsageDescription to your Info.plist file?");
		}
	}
#endif
	
    if ([self isInBackground] && !_locationServiceEnabledInBG) {
		// we are either in background or have no "location" in Info.plist
        [self startApproximateGeoTracking];
    }
    else {
		// ok, let's drain the battery
        [self startPreciseGeoTracking];
    }
}

#pragma mark - Geolocation

- (void)startPreciseGeoTracking {
    if ([CLLocationManager locationServicesEnabled]) {
        [self.locationManager startUpdatingLocation];
    }
    else {
        [self log:@"Location services not enabled on this device"];
    }
}

- (void)startApproximateGeoTracking {
    [self startSignificantMonitoring:NO];
    
    BOOL geoFencingEnabled = NO;
    
    if (kSystemVersion > 7) {
		//OK, Marmalade SDK does not want to link to CLCircularRegion directly. This is a workaround.
		Class circularRegion = NSClassFromString(@"CLCircularRegion");
        if ([CLLocationManager isMonitoringAvailableForClass:circularRegion]) {
            geoFencingEnabled = YES;
        }
    }
    else {
        if ([CLLocationManager regionMonitoringAvailable]) {
            geoFencingEnabled = YES;
        }
    }
    
    if (geoFencingEnabled) {
        [self setupRegionsForMonitoring];
    }
    else {
        [self log:@"Geofencing is not available on this device"];
    }
}

// this method will put outlined location icon on the status bar in background
// sets up a region around the user and another region around geozone
- (void)setupRegionsForMonitoring {
	[self log:[NSString stringWithFormat:@"setting up new regions"]];
	
	//this will give us necessary time to get all the callbacks from regions set-up
	//as they are asynchronoush we have to ask OS for more time or we are going to be killed before they have been set up!
	regionSetUpTaskId = [self startBackgroundTask];

    CLLocation *location = [self.locationManager location];
    
    if (!location) {
        location = _previousLocation;
    }
    
    if (!location) {
		[self log:[NSString stringWithFormat:@"I don't have a location!!!"]];
		
		//start everything
		[self startSignificantMonitoring:YES];
        return;
    }

	//as we could run in background thread we need to sync this as we will be receiving callbacks (didMonitoringStart) during the regions creation
	@synchronized(self) {
		_totalRegionsCount = _registeredRegionsCount = 0;
		_deferredUpdatesCount = -1;
	
		//place a region around the user with 100m radius, we'll have a trigger when user will leave this region
		[self startMonitoringRegionWithCenter:location.coordinate radius:kUserPositionRegionRadius identifier:kUserPositionRegionIdentifier];
		
		//set up a region around nearest pushwoosh geozone
		if (self.nearestGeozone) {
			[self startMonitoringRegionWithCenter:self.nearestGeozone.center radius:self.nearestGeozone.radius identifier:kNearestGeozoneRegionIdentifier];
		}
	}
}

//places a circular region with a radius over the center and starts to monitor it
- (void)startMonitoringRegionWithCenter:(CLLocationCoordinate2D)center radius:(CLLocationDistance)radius identifier:(NSString *)identifier {
    CLRegion *region = nil;
    
    _totalRegionsCount ++;
    
    if (radius > self.locationManager.maximumRegionMonitoringDistance) {
        radius = self.locationManager.maximumRegionMonitoringDistance;
    }
    
    if (kSystemVersion >= 7) {
        Class circularRegion = NSClassFromString(@"CLCircularRegion");
        region = [[circularRegion alloc] initWithCenter:center radius:radius identifier:identifier];
    }
    else {
        region = [[CLRegion alloc] initCircularRegionWithCenter:center radius:radius identifier:identifier];
    }
    
    [self.locationManager stopMonitoringForRegion:region];
    [self.locationManager startMonitoringForRegion:region];
}

- (BOOL) isSignificantMonitoringEnabled {
	NSNumber * useRegionsOnly = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"Pushwoosh_REGIONSONLY"];
	if(useRegionsOnly && [useRegionsOnly isKindOfClass:[NSNumber class]])
		return ![useRegionsOnly boolValue];

	return YES;
}

// this method will put location icon on the status bar in background, though it will use cell-towers for coordinate
- (void)startSignificantMonitoring:(BOOL)force {
	
	BOOL useSignificantMonitoring = [self isSignificantMonitoringEnabled];
	if(!useSignificantMonitoring && !force)
		return;
	
    if ([CLLocationManager significantLocationChangeMonitoringAvailable]) {
        [self.locationManager startMonitoringSignificantLocationChanges];
        [self log:@"Start monitoring significant changes"];
    }
    else {
        [self log:@"Significant changes service not available on this device"];
    }
}

- (void)stopRegionMonitoring {
    NSSet *regions = [self.locationManager monitoredRegions];
    
    for (CLRegion *region in regions) {
        if ([region.identifier isEqualToString:kUserPositionRegionIdentifier] || [region.identifier isEqualToString:kNearestGeozoneRegionIdentifier]) {
            [self.locationManager stopMonitoringForRegion:region];
            [self log:[NSString stringWithFormat:@"Stop monitoring region: %@ <%+.6f, %+.6f> radius %.0fm",region.identifier, region.center.latitude, region.center.longitude, region.radius]];
        }
    }
}

#pragma mark - Helpers

- (void)reportLocation:(CLLocation *)location withMessage:(NSString *)message {
    NSDateFormatter *dateFormat = [[NSDateFormatter alloc] init];
    [dateFormat setDateFormat:@"hh:mmaa"];
    
    NSString *msg = [NSString stringWithFormat:@"%@: %@ <%+.6f, %+.6f> (+/-%.0fm) %.1fkm/h",
                     message,
                     [dateFormat stringFromDate:location.timestamp],
                     location.coordinate.latitude,
                     location.coordinate.longitude,
                     location.horizontalAccuracy,
                     location.speed * 3.6];
    
    if (location.altitude > 0) {
        msg = [NSString stringWithFormat:@"%@ alt: %.2fm (+/-%.0fm)",
               msg,
               location.altitude,
               location.verticalAccuracy];
    }
    
    [self log:msg];
}

- (BOOL)shouldHandleRegion:(CLRegion *)region {
    return [region.identifier isEqualToString:kUserPositionRegionIdentifier] || [region.identifier isEqualToString:kNearestGeozoneRegionIdentifier];
}

//tracks deferred updates cound and reports a location to Pushwoosh
- (void)deferredSendingLocation {
    int remainingTime = [[UIApplication sharedApplication] backgroundTimeRemaining];
    
	//either we are running out of time in background or we have sent enough updates
    if (_deferredUpdatesCount >= kDeferredUpdatesMaxCount || remainingTime <= kDeferredUpdatesInterval) {
		[NSString stringWithFormat:@"Stopping deffered updates"];
        [self stopBackgroundTask:deferredUpdatesTaskId];
		deferredUpdatesTaskId = nil;
        _deferredUpdatesCount = -1;
        return;
    }
    
    [self reportLocation:[self.locationManager location] withMessage:
		[NSString stringWithFormat:@"Deferred location update: %ld, remaining background time: %d", (long)_deferredUpdatesCount, remainingTime]];
	
	//even if we running out of time this function will ask OS for another chunk of time to send the data to the server (managed by this function)
    [self sendLocation:[self.locationManager location]];
    
    _deferredUpdatesCount++;
    [self performSelector:@selector(deferredSendingLocation) withObject:nil afterDelay:kDeferredUpdatesInterval];
}

//when  the user enters the monitored region, we will update location several times every 30 seconds
//to handle situation then user has no internet connection at first (for wi-fi devices).
- (void)startDeferredUpdates {
	//this gives us 180 seconds (iOS 7.1) in background
    deferredUpdatesTaskId = [self startBackgroundTask];
    
	int remainingTime = [[UIApplication sharedApplication] backgroundTimeRemaining];
	[self log:[NSString stringWithFormat:@"Starting deffered updates, time: %d", remainingTime]];

    _deferredUpdatesCount = 0;
    
    [NSObject cancelPreviousPerformRequestsWithTarget:self selector:@selector(deferredSendingLocation) object:nil];
    [self performSelector:@selector(deferredSendingLocation) withObject:nil afterDelay:kDeferredUpdatesInterval];
}

#pragma mark - CLLocationManager Delegate

- (void)locationManager:(CLLocationManager *)manager didStartMonitoringForRegion:(CLRegion *)region {
    if (![self shouldHandleRegion:region])
        return;
    
    [self log:[NSString stringWithFormat:@"Region monitoring did start: %@ <%+.6f, %+.6f> radius %.0fm", region.identifier, region.center.latitude, region.center.longitude, region.radius]];
    
	@synchronized(self) {
		_registeredRegionsCount ++;
		
		//if we are not sending deffered updates (running background task) and this is the last region we have set up
		//we have started this task in setupRegionsForMonitoring
		if (_registeredRegionsCount == _totalRegionsCount && _deferredUpdatesCount == -1) {
			[self stopBackgroundTask:regionSetUpTaskId];
			regionSetUpTaskId = nil;
		}
	}
}

- (void)locationManager:(CLLocationManager *)manager monitoringDidFailForRegion:(CLRegion *)region withError:(NSError *)error {
    if (![self shouldHandleRegion:region])
        return;
    
    [self log:[NSString stringWithFormat:@"Region monitoring did fail: %@ %@", region.identifier, error.localizedDescription]];
	
	//stop the task we have created for regions set-up
	//we have started this task in setupRegionsForMonitoring
	[self stopBackgroundTask:regionSetUpTaskId];
	regionSetUpTaskId = nil;
}

//sends location to Pushwoosh and receives nearest Geozone (handled internally by PWGetNearestZoneRequest)
//runs background task for server operations, will call setNearestGeozone if request succeeds
- (void)sendLocation:(CLLocation *)newLocation {
	
	[self reportLocation:newLocation withMessage:@"Attempt to send location"];

    if (_previousLocation && [newLocation.timestamp timeIntervalSinceDate:_previousLocation.timestamp] < kMinUpdateTime)
	{
		[self log:[NSString stringWithFormat:@"Don't want to send new location as timestamp is less than update time"]];
		return;
	}
	
	if(_previousLocation && [newLocation distanceFromLocation:_previousLocation] < kMinUpdateDistance)
	{
		[self log:[NSString stringWithFormat:@"Don't want to new send location as it is too close"]];
        return;
    }
    
    _previousLocation = newLocation;
	
	dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0ul), ^{
		NSNumber * taskId = [self startBackgroundTask];
		
		[[PushNotificationManager pushManager] sendLocationBackground:newLocation];
		
		if(self.nearestGeozone.radius >= self.nearestGeozone.distance) {
			[self scheduleLocalNotification:[NSString stringWithFormat:@"Entered Geozone %@", self.nearestGeozone.name]];
		}
		
		[self stopBackgroundTask:taskId];
	});
}

//enter to region that corresponds nearest pushwoosh geozone
- (void)locationManager:(CLLocationManager *)manager didEnterRegion:(CLRegion *)region {
    if (![self shouldHandleRegion:region])
        return;
    
    CLLocation *location = [[CLLocation alloc] initWithLatitude:region.center.latitude longitude:region.center.longitude];
    [self reportLocation:location withMessage:[NSString stringWithFormat:@"Enter region %@", region.identifier]];
	
	[self scheduleLocalNotification:[NSString stringWithFormat:@"Entered Region %@", region.identifier]];
    
    [self sendLocation:location];
    
    //then the user enters to monitored region - we will update location several more times to handle situation then user has no internet connection at first (for wi-fi devices).
    [self startDeferredUpdates];
}

//exit from region with center in user position means that now should to update location and recreate regions
- (void)locationManager:(CLLocationManager *)manager didExitRegion:(CLRegion *)region {
    if (![self shouldHandleRegion:region])
        return;
    
    CLLocation *location = [[CLLocation alloc] initWithLatitude:region.center.latitude longitude:region.center.longitude];
    
    [self reportLocation:location withMessage:[NSString stringWithFormat:@"Exit region %@", region.identifier]];
    
    [self log:[NSString stringWithFormat:@"Distance from exited region center to current location: %f", [[manager location] distanceFromLocation:location]]];
	
	[self scheduleLocalNotification:[NSString stringWithFormat:@"Exit Region %@", region.identifier]];

    
    //send location, receive new nearest geozone and then update regions
    [self sendLocation:[manager location]];
	
	//set up another regions, if we receive new geozone it will trigger regions re-setup
	[self setupRegionsForMonitoring];
}

//send location to Pushwoosh and set-up regions again
- (void)updateLocation:(CLLocation *)location {
	
    [self sendLocation:location];
	[self setupRegionsForMonitoring];
}

// this function never gets called
- (void)locationManager:(CLLocationManager *)manager didUpdateToLocation:(CLLocation *)newLocation fromLocation:(CLLocation *)oldLocation {
    [self updateLocation:newLocation];
}

- (void)locationManager:(CLLocationManager *)manager didUpdateLocations:(NSArray *)locations {
    if ([locations count]) {
		//sometimes location manager sends old coordinate!!! we have to compare timestamps then.
		CLLocation *location = [self.locationManager location];
		CLLocation *kindaUpdatedlocation = [locations lastObject];
		
		if(location && [location.timestamp laterDate:kindaUpdatedlocation.timestamp])
		{
			//MAXK: I've found that location in locationManager could be much more precise then the one that comes in callback
			//WHY???
			[self updateLocation:location];
		}
		else
		{
			[self updateLocation:kindaUpdatedlocation];
		}
		
		if(![self isSignificantMonitoringEnabled])
			[self.locationManager stopMonitoringSignificantLocationChanges];
    }
}

#pragma mark - Teardown

- (void)dealloc {
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	[self stopUpdatingLocation];
	self.locationManager.delegate = nil;
	self.locationManager = nil;
}

@end
