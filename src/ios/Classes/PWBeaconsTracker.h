//
//  PWBeaconsTracker.h
//	Pushwoosh SDK
//

#import "PWBaseTracker.h"
#import "PWProcessBeaconRequest.h"

#ifdef USE_IBEACONS

@interface PWBeaconsTracker : PWBaseTracker

@property (nonatomic, strong) NSString *proximityUUID;
@property (nonatomic, assign) NSTimeInterval indoorOffset;
@property (nonatomic, strong) void (^processBeaconBlock)(PWBeaconAction action, NSString *uuid, NSNumber *major, NSNumber *minor);

- (void) processBeacon:(CLBeacon *)beacon withAction:(PWBeaconAction)action completion:(dispatch_block_t)completion;
@end

#endif