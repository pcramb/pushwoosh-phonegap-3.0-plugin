//
//  PWBeacon
//	Pushwoosh SDK
//

#import "PWBeacon.h"
#import "PWBeaconsTracker.h"
#import "PushRuntime.h"

#ifdef USE_IBEACONS

@implementation PWBeacon

- (id)initWithCoder:(NSCoder *)decoder {
    if (self = [super init]) {
        self.beacon = [decoder decodeObjectForKey:@"beacon"];
		self.firstSeenTime = [decoder decodeObjectForKey:@"firstSeenTime"];
		self.indoorThresholdInterval = [decoder decodeDoubleForKey:@"indoorThresholdInterval"];
    }
    return self;
}
- (void)encodeWithCoder:(NSCoder *)encoder {
    [encoder encodeObject:self.beacon forKey:@"beacon"];
	[encoder encodeObject:self.firstSeenTime forKey:@"firstSeenTime"];
	[encoder encodeDouble:self.indoorThresholdInterval forKey:@"indoorThresholdInterval"];
}

- (void) gone:(PWBeaconsTracker *)tracker {
	NSNumber *taskId = [tracker startBackgroundTask];
	
	//tell the Pushwoosh we're out
	[tracker processBeacon:self.beacon withAction:PWBeaconActionCameOut completion:^{
		[tracker stopBackgroundTask:taskId];
	}];
}

- (void) firstSeen:(PWBeaconsTracker *)tracker {
	NSNumber *taskId = [tracker startBackgroundTask];
	
	[tracker processBeacon:self.beacon withAction:PWBeaconActionCame completion:^{
		[tracker stopBackgroundTask:taskId];
	}];
	
	self.firstSeenTime = [NSDate date];
}

- (void) seenAgain:(PWBeaconsTracker *)tracker {
	if(!self.firstSeenTime)
		return;
	
	NSTimeInterval time = [[NSDate date] timeIntervalSinceDate:self.firstSeenTime];
	PWLog(@"Time: %f, indoor thresh: %f", time, self.indoorThresholdInterval);
	
	if(time >= self.indoorThresholdInterval)
	{
		NSNumber *taskId = [tracker startBackgroundTask];
		
		[tracker processBeacon:self.beacon withAction:PWBeaconActionIndoor completion:^{
			[tracker stopBackgroundTask:taskId];
		}];
		
		self.firstSeenTime = nil;
	}
}

@end

#endif