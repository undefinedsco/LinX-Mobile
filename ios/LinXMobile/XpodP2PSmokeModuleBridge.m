#import "RCTBridgeModule.h"

@interface RCT_EXTERN_MODULE(XpodP2PSmoke, NSObject)
RCT_EXTERN_METHOD(run:(NSDictionary *)request
                  resolver:(RCTPromiseResolveBlock)resolve
                  rejecter:(RCTPromiseRejectBlock)reject)
@end
