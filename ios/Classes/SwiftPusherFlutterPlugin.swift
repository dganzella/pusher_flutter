import Flutter
import UIKit
import PusherSwift

public class SwiftPusherFlutterPlugin: NSObject, FlutterPlugin, PusherDelegate {
    
  var pusher: Pusher! = nil
  var channel: PusherPresenceChannel! = nil;
  public static var eventSink: FlutterEventSink?
  var subscribedToChannel: Bool = false;
  var resultFirstSubscribe: FlutterResult! = nil;
    
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
    case "getUsers":
      getUsers(call, result: result)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  public func setup(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments else{
      return
    }

    let myArgs = args as! [String: Any];

    let apiKey = myArgs["api_key"] as! String;
    let cluster = myArgs["cluster"] as! String;
    let authEndpoint = myArgs["presenceAuthEndpoint"] as! String;
    let userToken = myArgs["userToken"] as! String;

    let options = PusherClientOptions(
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
    
    private func buildUsersArray() -> [[String: Any]]?
    {
        if(self.channel != nil){
            
            var arr: [[String: Any]] = [];
            
            self.channel.members.forEach { (member: PusherPresenceChannelMember) in
                
                arr.append([
                    "userId:" : member.userId,
                    "userInfo" : member.userInfo as Any
                    ]);
            }
            
            return arr;
        }
        
        return nil;
    }

  public func getUsers(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    if(self.channel != nil){
        result(self.buildUsersArray());
    }
    else{
        result(nil);
    }
  }
    
  public func subscribe(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments else{
      return
    }

    let myArgs = args as! [String: Any];
    let channelName = myArgs["channel"] as! String;
    let eventName = myArgs["event"] as! String;

    let onMemberAdded = { (member: PusherPresenceChannelMember) in
        
      var bodyResponse: [String : Any] = [:];
        
      bodyResponse["users"] = self.buildUsersArray();
        
      let messageMap: [String: Any] = [
          "channel": channelName,
          "event": "user_added",
          "body":  bodyResponse
      ];

      if let eventSinkObj = SwiftPusherFlutterPlugin.eventSink {
        eventSinkObj(messageMap)
      }
    }

    let onMemberRemoved = { (member: PusherPresenceChannelMember) in
        
        var bodyResponse: [String : Any] = [:];
        
        bodyResponse["users"] = self.buildUsersArray();
        
        let messageMap: [String: Any] = [
            "channel": channelName,
            "event": "user_removed",
            "body": bodyResponse
        ];
        
        if let eventSinkObj = SwiftPusherFlutterPlugin.eventSink {
            eventSinkObj(messageMap)
        }
    }
    

    if(self.channel == nil){
        self.channel = pusher.subscribeToPresenceChannel(channelName: channelName, onMemberAdded: onMemberAdded, onMemberRemoved: onMemberRemoved)
    }
    
    self.channel.bind(eventName: eventName, callback: { data in
        
        if let dataObj = data as? [String : Any] {
            
            let messageMap: [String: Any] = [
                "channel": channelName,
                "event": eventName,
                "body": dataObj
            ]
            
            if let eventSinkObj = SwiftPusherFlutterPlugin.eventSink {
                eventSinkObj(messageMap)
            }
        }
        else if let dataObjArr = data as? [Any] {
            
            var dataObj: [String: Any] = [:];
            
            for (idx,obj) in dataObjArr.enumerated() {
                
                let internobj = obj as? [String : Any];
                dataObj[String(idx)] = internobj;
            }
            
            let messageMap: [String: Any] = [
                "channel": channelName,
                "event": eventName,
                "body": dataObj
            ]
            
            if let eventSinkObj = SwiftPusherFlutterPlugin.eventSink {
                eventSinkObj(messageMap)
            }
        }
    })
    
    if(subscribedToChannel){
        result(nil);
    }
    else{
        self.resultFirstSubscribe = result;
    }
    }
  
    public func unsubscribe(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
        let argsDict = call.arguments as! Dictionary<String, Any>
        pusher.unsubscribe(argsDict["channel"] as! String)
        result(nil);
    }

  public func trigger(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    guard let args = call.arguments else{
      return
    }

    let myArgs = args as! [String: Any];
    let eventName = myArgs["event"] as! String;
    let body = myArgs["body"] as! String;

    if (self.subscribedToChannel){
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
    
    if(new == ConnectionState.disconnected){
        subscribedToChannel = false;
        self.channel = nil;
    }
  }

  public func subscribedToChannel(name: String) {
    print("Subscribed to \(name)")
    
    subscribedToChannel = true;
    self.resultFirstSubscribe(nil);
  }
    
  public func failedToSubscribeToChannel(name: String, response: URLResponse?, data: String?, error: NSError?){
    print("fail subscribed to \(name)")
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
