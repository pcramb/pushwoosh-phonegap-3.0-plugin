//
//  PWRequest.h
//  Pushwoosh SDK
//  (c) Pushwoosh 2012
//

#import <Foundation/Foundation.h>

@interface PWRequest : NSObject

@property (nonatomic, copy) NSString *appId;
@property (nonatomic, copy) NSString *hwid;
@property (nonatomic, assign) BOOL volatile processed;
@property (nonatomic, strong) NSError *error;

- (NSString *) methodName;
- (NSDictionary *) requestDictionary;

- (NSMutableDictionary *) baseDictionary;
- (void) parseResponse: (NSDictionary *) response;

@end
