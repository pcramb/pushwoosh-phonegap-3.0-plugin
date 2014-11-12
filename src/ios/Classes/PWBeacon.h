//
//  PWBeacon.h
//	Pushwoosh SDK
//

#import <Foundation/Foundation.h>
#import <CoreLocation/CoreLocation.h>

#ifdef USE_IBEACONS

@class PWBeaconsTracker;

@interface PWBeacon : NSObject

@property (nonatomic, strong) CLBeacon * beacon;
@property (nonatomic, strong) NSDate * firstSeenTime;
@property (nonatomic, assign) NSTimeInterval indoorThresholdInterval;

- (void) firstSeen:(PWBeaconsTracker *)tracker;
- (void) seenAgain:(PWBeaconsTracker *)tracker;
- (void) gone:(PWBeaconsTracker *)tracker;

@end

#endif