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
    print("AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA");
    print(call.method);
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
    let _ = channel.bind(eventName: eventName, callback: { data in
      print(data)
      do {
        if let dataObj = data as? [String : Any] {
          let pushJsonData = try! JSONSerialization.data(withJSONObject: dataObj)
          let pushJsonString = NSString(data: pushJsonData, encoding: String.Encoding.utf8.rawValue)
          let event = Event(channel: channelName, event: eventName, data: pushJsonString! as String)
          let message = PusherEventStreamMessage(event: event, connectionStateChange:  nil)
          let jsonEncoder = JSONEncoder()
          let jsonData = try jsonEncoder.encode(message)
          let jsonString = String(data: jsonData, encoding: .utf8)
          if let eventSinkObj = SwiftPusherFlutterPlugin.eventSink {
            eventSinkObj(jsonString)
            print(jsonString)
          }
        }
      } 
      catch {
        print("Pusher bind error")
      }
    })

    result(nil);
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

    self.channel.trigger(eventName: eventName, data: body)
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
    print("NOT Subscribed to \(name)")
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

struct PusherEventStreamMessage: Codable {
    var event: Event?
    var connectionStateChange: ConnectionStateChange?
}

struct ConnectionStateChange: Codable {
    var currentState: String
    var previousState: String
}

struct Event: Codable {
    var channel: String
    var event: String
    var data: String
}

struct BindArgs: Codable {
    var channelName: String
    var eventName: String
}
