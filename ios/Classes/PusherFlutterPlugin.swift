import UIKit
import PusherSwift

class PusherFlutterPlugin: NSObject, PusherDelegate {
    
    var pusher: Pusher! = nil
    var channel: PusherChannel! = nil

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

        channel = pusher.subscribe(channelName, onMemberAdded: onMemberAdded)

        let _ = channel.bind(eventName: eventName, callback: { data in
            print(data)
            let _ = self.pusher.subscribe(channelName, onMemberAdded: onMemberAdded)
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

        let onMemberAdded = { (member: PusherPresenceChannelMember) in
            print(member)
        }

        self.channel.trigger(eventName: eventName, data: body)
        result(nil);
    }
    
    // PusherDelegate methods
    func changedConnectionState(from old: ConnectionState, to new: ConnectionState) {
        // print the old and new connection states
        print("old: \(old.stringValue()) -> new: \(new.stringValue())")
    }

    func subscribedToChannel(name: String) {
        print("Subscribed to \(name)")
    }

    func debugLog(message: String) {
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
        request.addValue(self.userToken, forHTTPHeaderField: "Authorization")
        return request
    }
}