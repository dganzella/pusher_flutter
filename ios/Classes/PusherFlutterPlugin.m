#import "PusherFlutterPlugin.h"
#import <pusher_flutter/pusher_flutter-Swift.h>

@implementation PusherFlutterPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  [SwiftPusherFlutterPlugin registerWithRegistrar:registrar];
}
@end
