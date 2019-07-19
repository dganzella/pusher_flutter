#import "PusherFlutterPlugin.h"

@implementation PusherFlutterPlugin
+ (void)registerWithRegistrar:(NSObject <FlutterPluginRegistrar> *)registrar {
    FlutterMethodChannel *channel = [FlutterMethodChannel
            methodChannelWithName:@"plugins.apptreesoftware.com/pusher"
                  binaryMessenger:[registrar messenger]];
    PusherFlutterPlugin *instance = [[PusherFlutterPlugin alloc] init];
    [registrar addMethodCallDelegate:instance channel:channel];

    FlutterEventChannel *connectionEventChannel = [FlutterEventChannel eventChannelWithName:@"plugins.apptreesoftware.com/pusher_connection" binaryMessenger:[registrar messenger]];
    instance.connectivityStreamHandler = [[PusherConnectionStateStream alloc] init];
    [connectionEventChannel setStreamHandler:instance.connectivityStreamHandler];

    FlutterEventChannel *messageEventChannel = [FlutterEventChannel eventChannelWithName:@"plugins.apptreesoftware.com/pusher_message" binaryMessenger:[registrar messenger]];
    instance.messageStreamHandler = [[MessageStreamHandler alloc] init];
    [messageEventChannel setStreamHandler:instance.messageStreamHandler];

    FlutterEventChannel *errorChannel = [FlutterEventChannel eventChannelWithName:@"plugins.apptreesoftware.com/pusher_error" binaryMessenger:[registrar messenger]];
    instance.errorStreamHandler = [[PusherErrorStream alloc] init];
    [errorChannel setStreamHandler:instance.errorStreamHandler];
}

- (BOOL)pusher:(PTPusher *)pusher connectionWillConnect:(PTPusherConnection *)connection {
    [self.connectivityStreamHandler sendState:@"connecting"];
    return YES;
}

- (void)pusher:(PTPusher *)pusher connectionDidConnect:(PTPusherConnection *)connection {
    [self.connectivityStreamHandler sendState:@"connected"];

}

- (void)pusher:(PTPusher *)pusher connection:(PTPusherConnection *)connection didDisconnectWithError:(NSError *)error willAttemptReconnect:(BOOL)willAttemptReconnect {
    [self.connectivityStreamHandler sendState:@"disconnected"];
    if (error) {
        [self.errorStreamHandler sendError:error];
    }
}

- (void)pusher:(PTPusher *)pusher connection:(PTPusherConnection *)connection failedWithError:(NSError *)error {
    [self.connectivityStreamHandler sendState:@"disconnected"];
    if (error) {
        [self.errorStreamHandler sendError:error];
    }
}

- (BOOL)pusher:(PTPusher *)pusher connectionWillAutomaticallyReconnect:(PTPusherConnection *)connection afterDelay:(NSTimeInterval)delay {
    [self.connectivityStreamHandler sendState:@"reconnecting"];
    return YES;
}

- (void)pusher:(PTPusher *)pusher willAuthorizeChannel:(PTPusherPresenceChannel *)channel withAuthOperation:(PTPusherChannelAuthorizationOperation *)operation withRequest:(NSMutableURLRequest *)request{
    [request setValue:self.userToken forHTTPHeaderField:@"token"];
    NSLog(@"AUTHORIZE");
}

- (void)pusher:(PTPusher *)pusher didSubscribeToChannel:(PTPusherPresenceChannel *)channel {
    printf("SUBSCRIBE");
}

- (void)pusher:(PTPusher *)pusher didUnsubscribeFromChannel:(PTPusherPresenceChannel *)channel {
    NSLog(@"UNSUBSCRIBE");
}

- (void)pusher:(PTPusher *)pusher didFailToSubscribeToChannel:(PTPusherPresenceChannel *)channel withError:(NSError *)error {
    [self.errorStreamHandler sendError:error];
    NSLog(@"FAIL SUBSCRIBE, %@ %li", error.localizedDescription, error.code);
}

- (void)pusher:(PTPusher *)pusher didReceiveErrorEvent:(PTPusherErrorEvent *)errorEvent {
    [self.errorStreamHandler sendCode:errorEvent.code message:errorEvent.message];
}

- (void)handleMethodCall:(FlutterMethodCall *)call result:(FlutterResult)result {
    if ([call.method isEqualToString:@"create"]) {
        NSString *apiKey = call.arguments[@"api_key"];
        NSString *cluster = call.arguments[@"cluster"];

        self.pusher = [PTPusher pusherWithKey:apiKey delegate:self encrypted:YES cluster:cluster];

        NSString *presenceAuthEndpoint = call.arguments[@"presenceAuthEndpoint"];
        NSString *uToken = call.arguments[@"userToken"];

        if(presenceAuthEndpoint != nil && uToken != nil){
            self.pusher.authorizationURL = [NSURL URLWithString: presenceAuthEndpoint];
            self.userToken = [[NSString alloc] initWithString:uToken];
        }
        

        result(@(YES));
    } else if ([call.method isEqualToString:@"connect"]) {
        [self.pusher connect];
        result(@(YES));
    } else if ([call.method isEqualToString:@"disconnect"]) {
        [self.pusher disconnect];
        result(@(YES));
    } else if ([call.method isEqualToString:@"triggerEvent"]) {
        
        NSString *channelName = call.arguments[@"channel"];
        NSString *event = call.arguments[@"event"];
        NSArray *body = call.arguments[@"body"];

        if([channelName containsString:@"presence"]) {
            PTPusherPresenceChannel *channel = [self.pusher channelNamed:channelName];
            
            if (!channel) {
                channel = [self.pusher subscribeToPresenceChannelNamed:channelName];
                [channel triggerEventNamed:event data:body];
                printf("END TRIGGER CALL");
            }
        }
        
        result(@(YES));
    } else if ([call.method isEqualToString:@"subscribe"]) {
        NSString *channelName = call.arguments[@"channel"];
        NSString *event = call.arguments[@"event"];

        PTPusherPresenceChannel *channel = [self.pusher channelNamed:channelName];
        if (!channel) {
            printf("SUBSCRIBE CHANNEL FOUND");
            channel = [self.pusher subscribeToPresenceChannelNamed:channelName];
            [self listenToChannel:channel forEvent:event];
        }
        
        result(@(YES));
    } else if ([call.method isEqualToString:@"unsubscribe"]) {
        PTPusherPresenceChannel *channel = [self.pusher channelNamed:call.arguments];
        [channel removeAllBindings];
        if (channel) {
            [channel unsubscribe];
        }
        result(@(YES));
    }
    result(FlutterMethodNotImplemented);
}

- (void)listenToChannel:(PTPusherPresenceChannel *)channel forEvent:(NSString *)event {
    printf("BIIIIIIIIIINNNNNNNNNNDDDDDDD");
    NSLog(event);
    [channel bindToEventNamed:event handleWithBlock:^(PTPusherEvent *e) {
        [_messageStreamHandler send:channel.name event:event body:e.data];
    }];
}

@end

@implementation MessageStreamHandler {
    FlutterEventSink _eventSink;
}

- (FlutterError *_Nullable)onListenWithArguments:(id _Nullable)arguments eventSink:(FlutterEventSink)events {
    _eventSink = events;
    return nil;
}

- (void)send:(NSString *)channel event:(NSString *)event body:(id)body {
    if (_eventSink) {
        NSDictionary *dictionary = @{@"channel": channel, @"event": event, @"body": body};
        _eventSink(dictionary);
    }
}

- (FlutterError *_Nullable)onCancelWithArguments:(id _Nullable)arguments {
    _eventSink = nil;
    return nil;
}

@end


@implementation PusherConnectionStateStream {
    FlutterEventSink _eventSink;
}

- (FlutterError *_Nullable)onListenWithArguments:(id _Nullable)arguments eventSink:(FlutterEventSink)events {
    _eventSink = events;
    return nil;
}

- (void)sendState:(NSString *)state {
    if (_eventSink) {
        _eventSink(state);
    }
}

- (FlutterError *_Nullable)onCancelWithArguments:(id _Nullable)arguments {
    _eventSink = nil;
    return nil;
}

@end

@implementation PusherErrorStream {
    FlutterEventSink _eventSink;
}

- (void)sendError:(NSError *)error {
    if (_eventSink) {
        _eventSink(@{@"code" : @(error.code), @"message" : error.localizedDescription});
    }
}

- (void)sendCode:(NSInteger)code message:(NSString *)message {
    if (_eventSink) {
        _eventSink(@{@"code" : @(code), @"message" : message});
    }
}

- (FlutterError *_Nullable)onListenWithArguments:(id _Nullable)arguments eventSink:(FlutterEventSink)events {
    _eventSink = events;
    return nil;
}

- (FlutterError *_Nullable)onCancelWithArguments:(id _Nullable)arguments {
    _eventSink = nil;
    return nil;
}


@end
