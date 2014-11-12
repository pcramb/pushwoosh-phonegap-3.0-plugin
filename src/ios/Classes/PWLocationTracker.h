//
//  PWLocationTracker.h
//	Pushwoosh SDK
//

#import "PWBaseTracker.h"
#import "PWGeozone.h"

typedef void(^locationHandler)(CLLocation *location);

@interface PWLocationTracker : PWBaseTracker

@property (nonatomic, copy) NSString *backgroundMode;
@property (nonatomic, strong) PWGeozone *nearestGeozone;

@end
