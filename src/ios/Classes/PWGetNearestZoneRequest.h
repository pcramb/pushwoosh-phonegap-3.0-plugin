//
//  PWGetNearestZoneRequest.h
//  Pushwoosh SDK
//  (c) Pushwoosh 2012
//

#import "PWRequest.h"
#import <CoreLocation/CoreLocation.h>
#import "PWGeozone.h"

@interface PWGetNearestZoneRequest : PWRequest

@property CLLocationCoordinate2D userCoordinate;

@property (nonatomic, strong) PWGeozone *nearestGeozone;

@end
