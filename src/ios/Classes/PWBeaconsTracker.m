//
//  PWBeaconsTracker.m
//	Pushwoosh SDK
//

//Notes: read http://developer.radiusnetworks.com/2013/11/13/ibeacon-monitoring-in-the-background-and-foreground.html

//notifyEntryStateOnDisplay = YES; is crucial
//this way we will receive region and beacons information (including ranging) once user lights up the screen
//(presses shoulder button, home button, another push).
//This is necessary for working in background where ranging otherwise are not available completely
//and region detection could take several minutes

//Ranging beacons in background:
//The cheat with background task gives us 180 seconds in background (tested: iOS 7.1)
//Otherwise ranging will run for 10 seconds only

//Entering region
//at the moment it works almost instant for me, but I'm on debug and plugged to the Mac
//need to test this without charging

//Exiting region
//did exit region - about 1 minute delay after exiting the region, could take 4 minutes

//The strategy:
//1. User enters the region, we use the hack for 180 seconds for ranging the beacons.
//TODO: we could send region-wide event to Pushwoosh. At the moment we don't.

//2. When we see new beacons when ranging we send "came in" event to Pushwoosh for the beacon
//3. If the user is still in the region after 120 seconds (we are ranging using background task hack in background) and near some
//   beacon we can send "indoor" action
//4. When we no longer see the beacon we will send "came out" event for the beacon
//5. When we our of the region we will send "came out" event for all beacons left

//TODO: check how it works when the app is closed completely

#import "PWBeaconsTracker.h"
#import "PWBeacon.h"
#import "PushRuntime.h"

#ifdef USE_IBEACONS

#define kBeaconRegionIdentifier @"com.pushwoosh.kBeaconRegionIdentifier"
#define kLastBeaconKey @"com.pushwoosh.lastNearestBeacon"

@interface PWBeaconsTracker () {
    CLBeaconRegion *_beaconRegion;
}

@end

@implementation PWBeaconsTracker

// gives us the idea of how much background time left for debugging
- (void) reportBackgroundTaskTimer:(NSString *)functionName {
	if([self isInBackground])
	{
		int timeLeft = [[UIApplication sharedApplication] backgroundTimeRemaining];
		PWLog(@"Function: %@, in background, time left: %d", functionName, timeLeft);
	}
	else
	{
		PWLog(@"Function: %@, in foreground", functionName);
	}
}

- (void) stopBeacons:(CLLocationManager *)locManager withRegion:(CLBeaconRegion *)region{
	SEL selector = NSSelectorFromString(@"stopRangingBeaconsInRegion:");
	IMP imp = [locManager methodForSelector:selector];
	void (*func)(id, SEL, CLBeaconRegion *) = (void *)imp;
	func(locManager, selector, region);
}

- (void) startBeacons:(CLLocationManager *)locManager withRegion:(CLBeaconRegion *)region{
	SEL selector = NSSelectorFromString(@"startRangingBeaconsInRegion:");
	IMP imp = [locManager methodForSelector:selector];
	void (*func)(id, SEL, CLBeaconRegion *) = (void *)imp;
	func(locManager, selector, region);
}

// we skip minor version here as they are just "signal extenders" not the push triggers itself
- (NSString *) beaconHashString:(CLBeacon *) beacon {
	return [NSString stringWithFormat:@"%@.%@", beacon.proximityUUID.UUIDString, beacon.major.stringValue];
}

- (NSMutableDictionary *) loadBeaconsList {
	NSData *beaconData = [[NSUserDefaults standardUserDefaults] objectForKey:kLastBeaconKey];
	NSMutableDictionary * beacons = [NSKeyedUnarchiver unarchiveObjectWithData:beaconData];
	
	return beacons;

}

- (void) saveBeaconsList:(NSMutableDictionary *) beacons {
	NSData *beaconData = [NSKeyedArchiver archivedDataWithRootObject:beacons];
	
    [[NSUserDefaults standardUserDefaults] setObject:beaconData forKey:kLastBeaconKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

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
	
	if(_beaconRegion && self.enabled)
		[self startBeaconsTracking];
}

- (void) startBeaconsTracking {
	//go go go, this will trigger didStartMonitoringForRegion callback and subsequent enter/exit callbacks
	[self.locationManager startMonitoringForRegion:_beaconRegion];
	
	//http://developer.radiusnetworks.com/2013/11/13/ibeacon-monitoring-in-the-background-and-foreground.html
	//recommends ranging all the time in the foreground, in backgroudn this function will be ignored most of the time
	if ([CLLocationManager isRangingAvailable] && ![self isInBackground])
	{
		[self startBeacons:self.locationManager withRegion:_beaconRegion];
	}
}

//enables beacon tracking
- (void)setEnabled:(BOOL)enabled {
    [super setEnabled:enabled];
    
	//beacon works on iOS 7 and higher
    if (kSystemVersion < 7) {
        [self log:@"iBeacon is not supported on this OS version"];
        return;
    }
    
    if (enabled) {
        if (![self locationServiceAuthorized])
            return;
        
        if (![CLLocationManager isMonitoringAvailableForClass:[CLBeaconRegion class]]) {
            [self log:@"iBeacon is not supported on this device"];
            return;
        }
        
        if (!_proximityUUID) {
            [self log:@"proximityUUID is empty"];
            return;
        }
        
        NSUUID *uuid = [[NSUUID alloc] initWithUUIDString:_proximityUUID];
		
		//initialize beacon region and start monitoring, we don't bother about major and minor id at this moment
		//just monitor the whole region. Pushwoosh will do the rest.
        _beaconRegion = [[CLBeaconRegion alloc] initWithProximityUUID:uuid identifier:kBeaconRegionIdentifier];
        _beaconRegion.notifyOnExit = YES;
        _beaconRegion.notifyOnEntry = YES;
		
		//we will receive region and beacons information (including ranging) once user lights up the screen
		//(presses shoulder button). This is necessary for working in background where ranging are not available completely
		//and region detection could take 2 - 4 minutes
		_beaconRegion.notifyEntryStateOnDisplay = YES;
		
        if (_beaconRegion) {
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

			[self startBeaconsTracking];
        }
    }
    else if (_beaconRegion) {
		//disable
        [self.locationManager stopMonitoringForRegion:_beaconRegion];
		[self stopBeacons:self.locationManager withRegion:_beaconRegion];
    }
}

//we track only our own region
- (BOOL)shouldHandleRegion:(CLRegion *)region {
    BOOL should = [region.identifier isEqualToString:kBeaconRegionIdentifier];
	return should;
}

- (BOOL)beaconsAreEqual:(NSArray *)beacons {
    if ([beacons count] != 2) {
        return NO;
    }
    
    CLBeacon *beacon1 = beacons[0];
    CLBeacon *beacon2 = beacons[1];
    
    return [beacon1.proximityUUID.UUIDString isEqualToString:beacon2.proximityUUID.UUIDString] && (beacon1.major.intValue == beacon2.major.intValue) && (beacon1.minor.intValue == beacon2.minor.intValue);
}

#pragma mark - CLLocationManager Delegate

- (void)locationManager:(CLLocationManager *)manager didStartMonitoringForRegion:(CLBeaconRegion *)region {
    if (![self shouldHandleRegion:region])
        return;
	
	[self reportBackgroundTaskTimer:@"didStartMonitoringForRegion"];
    [self log:[NSString stringWithFormat:@"Beacon region monitoring did start: %@", region.proximityUUID.UUIDString]];

	//we want to know the current state of the region - inside/outside
	[self.locationManager requestStateForRegion:region];
}

//we know the state of the region. this could be triggered as a "shoulder button" press or when the app starts
- (void)locationManager:(CLLocationManager *)manager didDetermineState:(CLRegionState)state forRegion:(CLRegion *)region
{
	if (![self shouldHandleRegion:region])
        return;
	
	[self reportBackgroundTaskTimer:@"didDetermineState"];

	//do not do Pushwoosh handling here, iOS should trigger enter/exit events.
    if (state == CLRegionStateInside)
    {
		PWLog(@"Inside beacons region");
		
        //start beacon ranging
		if ([CLLocationManager isRangingAvailable] && [region isKindOfClass:[CLBeaconRegion class]])
		{
			[self startBeacons:manager withRegion:(CLBeaconRegion *)region];
		}
    }
	else
	{
		PWLog(@"Outside beacons region");
	}
}

- (void)locationManager:(CLLocationManager *)manager monitoringDidFailForRegion:(CLBeaconRegion *)region withError:(NSError *)error
{
    if (![self shouldHandleRegion:region])
        return;
    
	//oops
    [self log:[NSString stringWithFormat:@"Beacon region monitoring did fail: %@, %@", region.proximityUUID.UUIDString, error.localizedDescription]];
}

//we are in the region!
- (void)locationManager:(CLLocationManager *)manager didEnterRegion:(CLBeaconRegion *)region {
    if (![self shouldHandleRegion:region])
        return;
    
    [self log:[NSString stringWithFormat:@"Enter in beacon region: %@", region.proximityUUID.UUIDString]];
	
	[self reportBackgroundTaskTimer:@"didEnterRegion"];
    
	//try to start ranging beacons using background task hack
    if ([CLLocationManager isRangingAvailable]) {
        [self startBackgroundTask];
		
		//The cheat with background task gives us 180 seconds in background (tested: iOS 7.1)
		//Otherwise ranging will run for 10 seconds only
		[self startBeacons:self.locationManager withRegion:region];
    }
    else {
        [self log:@"Ranging beacons is not supported on this device"];
    }
	
	//TODO: we can notify Pushwoosh that we have entered region
}

//we are out of the region, notify Pushwoosh that we have left the building
- (void)locationManager:(CLLocationManager *)manager didExitRegion:(CLBeaconRegion *)region {
    if (![self shouldHandleRegion:region])
        return;
    
    [self log:[NSString stringWithFormat:@"Exit from beacon region: %@", region.proximityUUID.UUIDString]];
	[self reportBackgroundTaskTimer:@"didExitRegion"];
	
	//Load last seen beacons list, notify Pushwoosh that we no longer see them. Clear the list.
	NSMutableDictionary * lastVisibleBeacons = [self loadBeaconsList];
	for(PWBeacon * beacon in lastVisibleBeacons.allValues)
	{
		if(!beacon)
			continue;
		
		[beacon gone:self];
		PWLog(@"Gone beacon: %@", beacon.beacon);
	}
	
	[self saveBeaconsList:nil];

	//we don't need to range for the region anymore, don't we?
	[self stopBeacons:self.locationManager withRegion:_beaconRegion];
	
	//TODO: we can notify Pushwoosh that we have left the region
}

//The cheat with background task gives us 180 seconds in background (tested: iOS 7.1)
//Otherwise this function will run for 10 seconds
- (void)locationManager:(CLLocationManager *)manager didRangeBeacons:(NSArray *)beacons inRegion:(CLBeaconRegion *)region {
	if (![self shouldHandleRegion:region])
        return;
	
	//if we see no beacons we should receive didExitRegion
	//do not handle this here as sometimes it is empty when the app comes from background and we are in the region
	if(!beacons || !beacons.count)
		return;

	[self reportBackgroundTaskTimer:@"didRangeBeacons"];
	
	NSMutableDictionary * lastVisibleBeacons = [self loadBeaconsList];
	NSMutableDictionary * currentBeacons = [NSMutableDictionary dictionary];

	for(CLBeacon * beacon in beacons)
	{
		NSString * hash = [self beaconHashString:beacon];
		PWBeacon * pwbeacon = [lastVisibleBeacons objectForKey:hash];
		if(!pwbeacon)
			pwbeacon = [currentBeacons objectForKey:hash];
		
		if(!pwbeacon)
		{
			PWLog(@"New beacon: %@", beacon);
			
			//new beacon
			PWBeacon * pwbeacon = [[PWBeacon alloc] init];
			pwbeacon.beacon = beacon;
			pwbeacon.indoorThresholdInterval = self.indoorOffset;
			[pwbeacon firstSeen:self];
			
			[currentBeacons setObject:pwbeacon forKey:hash];
		}
		else
		{
			PWLog(@"Existing beacon: %@", beacon);
			
			//existing beacon
			[pwbeacon seenAgain:self];
			
			[lastVisibleBeacons removeObjectForKey:hash];
			[currentBeacons setObject:pwbeacon forKey:hash];
		}
	}
	
	for(PWBeacon * beacon in lastVisibleBeacons.allValues)
	{
		[beacon gone:self];
		PWLog(@"Gone beacon: %@", beacon.beacon);
	}
	
	[self saveBeaconsList:currentBeacons];
}

- (void)processBeacon:(CLBeacon *)beacon withAction:(PWBeaconAction)action completion:(dispatch_block_t)completion
{
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
		self.processBeaconBlock(action, beacon.proximityUUID.UUIDString, beacon.major, beacon.minor);
        
        if (completion) {
            dispatch_async(dispatch_get_main_queue(), ^{
                completion();
            });
        }
    });
}

@end

#endif
