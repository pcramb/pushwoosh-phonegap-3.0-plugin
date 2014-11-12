//
//  PWProcessBeaconRequest
//  Pushwoosh SDK
//  (c) Pushwoosh 2014
//

#import "PWRequest.h"

#ifndef __PWBeaconActionIncluded
#define __PWBeaconActionIncluded

typedef NS_ENUM(NSInteger, PWBeaconAction) {
	PWBeaconActionCame,
    PWBeaconActionIndoor,
    PWBeaconActionCameOut
};

#endif

@interface PWProcessBeaconRequest : PWRequest

@property (nonatomic, assign) PWBeaconAction action;
@property (nonatomic, strong) NSNumber *major;
@property (nonatomic, strong) NSNumber *minor;
@property (nonatomic, strong) NSString *uuid;

@property (nonatomic, assign) NSTimeInterval indoorThresholdInterval;

@end
