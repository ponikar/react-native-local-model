
#ifdef RCT_NEW_ARCH_ENABLED
#import "RNLocalModelSpec.h"

@interface LocalModel : NSObject <NativeLocalModelSpec>
#else
#import <React/RCTBridgeModule.h>

@interface LocalModel : NSObject <RCTBridgeModule>
#endif

@end
