//
//  PWGetBeaconsRequest
//  Pushwoosh SDK
//  (c) Pushwoosh 2014
//

#import "PWRequest.h"

@interface PWGetBeaconsRequest : PWRequest

@property (nonatomic, strong) NSString *uuid;
@property (nonatomic, assign) NSTimeInterval indoorOffset;

@end
