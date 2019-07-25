import Flutter
import UIKit
import PusherSwift

public class SwiftPusherFlutterPlugin: NSObject, FlutterPlugin, PusherDelegate {
    
  var pusher: Pusher! = nil
  var channel: PusherPresenceChannel! = nil;
  public static var eventSink: FlutterEventSink?
    
  public static func register(with registrar: FlutterPluginRegistrar) {

    let channel = FlutterMethodChannel(name: "plugins.apptreesoftware.com/pusher", binaryMessenger: registrar.messenger())
    let instance = SwiftPusherFlutterPlugin()
    registrar.addMethodCallDelegate(instance, channel: channel)

    let messageChannel = FlutterEventChannel(name: "plugins.apptreesoftware.com/pusher_message", binaryMessenger: registrar.messenger())
    messageChannel.setStreamHandler(StreamHandler())
  }

  public func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
   switch call.method {
    case "create":
      setup(call, result: result)
    case "connect":
      connect(call, result: result)
    case "disconnect":
      disconnect(call, result: result)
    case "subscribe":
      subscribe(call, result: result)
    case "unsubscribe":
      unsubscribe(call, result: result)
    case "triggerEvent":
      trigger(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func setup(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments else{
      return
    }

    let myArgs = args as! [String: Any];

    var apiKey = myArgs["api_key"] as! String;
    var cluster = myArgs["cluster"] as! String;
    var authEndpoint = myArgs["presenceAuthEndpoint"] as! String;
    var userToken = myArgs["userToken"] as! String;

    var options = PusherClientOptions(
      authMethod: AuthMethod.authRequestBuilder(authRequestBuilder: AuthRequestBuilder(
        endpoint: authEndpoint,
        uToken: userToken
      )),
      host: .cluster(cluster)
    )
    
    pusher = Pusher(key: apiKey, options: options)
    pusher.delegate = self

    result(nil);
  }

  public func connect(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    pusher.connect();
    result(nil);
  }
  
  public func disconnect(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    pusher.disconnect();
    result(nil);
  }

  public func subscribe(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments else{
      return
    }

    let myArgs = args as! [String: Any];
    var channelName = myArgs["channel"] as! String;
    var eventName = myArgs["event"] as! String;

    var onMemberAdded = { (member: PusherPresenceChannelMember) in
      print(member)
    }

    self.channel = pusher.subscribeToPresenceChannel(channelName: channelName, onMemberAdded: onMemberAdded)
    
    if(channel == nil){
      self.channel.bind(eventName: "pusher:subscription_succeeded", callback: { data in
        result(nil)
      })
    }
    else{
      let _ = channel.bind(eventName: eventName, callback: { data in
        do {
          if let dataObj = data as? [String : Any] {
            
            var messageMap: [String: Any] = [
              "channel": channelName,
              "event": eventName,
              "body": dataObj
            ]

            if let eventSinkObj = SwiftPusherFlutterPlugin.eventSink {
              eventSinkObj(messageMap)
            }
          }
        } 
        catch {
          print("Pusher bind error")
        }
      })
      result(nil);
    }
  }
  
  public func unsubscribe(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    let channelName = call.arguments as! String
    pusher.unsubscribe(channelName)
    result(nil);
  }

  public func trigger(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments else{
      return
    }

    let myArgs = args as! [String: Any];
    var channelName = myArgs["channel"] as! String;
    var eventName = myArgs["event"] as! String;
    var body = myArgs["body"] as! String;

    if (self.channel != nil){
      self.channel.trigger(eventName: eventName, data: body)
    }
    else{
      print("User is not subscribed to channel, trigger event could not be done");
    }
    
    result(nil);
  }
  
  
  // PusherDelegate methods
  public func changedConnectionState(from old: ConnectionState, to new: ConnectionState) {
    print("old: \(old.stringValue()) -> new: \(new.stringValue())")
  }

  public func subscribedToChannel(name: String) {
    print("Subscribed to \(name)")
  }
    
  public func failedToSubscribeToChannel(name: String, response: URLResponse?, data: String?, error: NSError?){
    print("NOT subscribed to \(name)")
    print(data);
    print(error?.localizedDescription);
  }

  public func debugLog(message: String) {
    print(message)
  }
}

class AuthRequestBuilder: AuthRequestBuilderProtocol {
    
  var authEndpoint: String
  var userToken: String

  init(endpoint: String, uToken: String){
    self.authEndpoint = endpoint;
    self.userToken = uToken;
  }
    
  func requestFor(socketID: String, channelName: String) -> URLRequest? {
    var request = URLRequest(url: URL(string: self.authEndpoint)!)
    request.httpMethod = "POST"
    request.httpBody = "socket_id=\(socketID)&channel_name=\(channelName)".data(using: String.Encoding.utf8)
    request.addValue(self.userToken, forHTTPHeaderField: "token")
    return request
  }
}

class StreamHandler: NSObject, FlutterStreamHandler {
  public func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    SwiftPusherFlutterPlugin.eventSink = events
    return nil;
  }
  
  public func onCancel(withArguments arguments: Any?) -> FlutterError? {
    return nil;
  }
}
