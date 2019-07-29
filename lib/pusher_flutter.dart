import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

enum PusherConnectionState {
  connecting,
  connected,
  disconnecting,
  disconnected,
  reconnecting,
  reconnectingWhenNetworkBecomesReachable
}

class PusherFlutter {
  MethodChannel _channel;
  EventChannel _connectivityEventChannel;
  EventChannel _messageChannel;
  EventChannel _errorChannel;

  /// Creates a [PusherFlutter] with the specified [apiKey] from pusher.
  ///
  /// The [apiKey] may not be null.
  PusherFlutter(String apiKey, {String cluster, String csrfToken, String userToken, String presenceAuthEndpoint }) {
    _channel = new MethodChannel('plugins.apptreesoftware.com/pusher');
    var args = {"api_key": apiKey};
    if (cluster != null) {
      args["cluster"] = cluster;
    }
    if (userToken != null) {
      args["userToken"] = userToken;
    }
    if (csrfToken != null) {
      args["csrfToken"] = csrfToken;
    }
    if (presenceAuthEndpoint != null) {
      args["presenceAuthEndpoint"] = presenceAuthEndpoint;
    }

    _channel.invokeMethod('create', args);
    _connectivityEventChannel =
        new EventChannel('plugins.apptreesoftware.com/pusher_connection');
    _messageChannel =
        new EventChannel('plugins.apptreesoftware.com/pusher_message');
    _errorChannel =
        new EventChannel('plugins.apptreesoftware.com/pusher_error');
  }

  /// Connect to the pusher service.
  Future<void> connect() async {
    _channel.invokeMethod('connect');
    return;
  }

  Future< List< dynamic > > getUsers(String channel) async {

    var args = {"channel": channel};

    return _channel.invokeMethod('getUsers', args);
  }

  Future<void> triggerEvent(PusherMessage message) async {
    _channel.invokeMethod('triggerEvent', {"channel": message.channelName, "event": message.eventName, "body": jsonEncode(message.body)} );
    return;
  }

  /// Disconnect from the pusher service
  Future<void> disconnect() async {
    _channel.invokeMethod('disconnect');
    return;
  }

  /// Subscribe to a channel with the name [channelName] for the event [event]
  ///
  /// Calling this method will cause any messages matching the [event] and [channelName]
  /// provided to be delivered to the [onMessage] method. After calling this you
  /// must listen to the [Stream] returned from [onMessage].
  Future<void> subscribe(String channelName, String event) async {
    await _channel.invokeMethod('subscribe', {"channel": channelName, "event": event});
    return;
  }

  /// Subscribe to the channel [channelName] for each [eventName] in [events]
  ///
  /// This method is just for convenience if you need to register multiple events
  /// for the same channel.
  Future<void> subscribeAll(String channelName, List<String> events) async {
    await events.forEach((e) => _channel.invokeMethod('subscribe', {"channel": channelName, "event": e}));
    return;
  }

  /// Unsubscribe from a channel with the name [channelName]
  ///
  /// This will un-subscribe you from all events on that channel.
  Future<void> unsubscribe(String channelName) async {
    await _channel.invokeMethod('unsubscribe', {"channel": channelName});
    return;
  }

  /// Get the [Stream] of [PusherMessage] for the channels and events you've
  /// signed up for.
  ///
  Stream<PusherMessage> get onMessage =>
      _messageChannel.receiveBroadcastStream().map(_toPusherMessage);

  Stream<PusherError> get onError =>
      _errorChannel.receiveBroadcastStream().map(_toPusherError);

  /// Get a [Stream] of [PusherConnectionState] events.
  /// Use this method to get notified about connection-related information.
  ///
  Stream<PusherConnectionState> get onConnectivityChanged =>
      _connectivityEventChannel
          .receiveBroadcastStream()
          .map((state) => _connectivityStringToState(state.toString()));

  PusherConnectionState _connectivityStringToState(String string) {
    switch (string) {
      case 'connecting':
        return PusherConnectionState.connecting;
      case 'connected':
        return PusherConnectionState.connected;
      case 'disconnected':
        return PusherConnectionState.disconnected;
      case 'disconnecting':
        return PusherConnectionState.disconnecting;
      case 'reconnecting':
        return PusherConnectionState.reconnecting;
      case 'reconnectingWhenNetworkBecomesReachable':
        return PusherConnectionState.reconnectingWhenNetworkBecomesReachable;
    }
    return PusherConnectionState.disconnected;
  }

  PusherMessage _toPusherMessage(dynamic map) {
    if (map is Map) {
      var body = new Map<String, dynamic>.from(map['body']);
      return new PusherMessage(map['channel'], map['event'], body);
    }
    return null;
  }

  PusherError _toPusherError(Map map) {
    return new PusherError(map['code'], map['message']);
  }
}

class PusherMessage {
  final String channelName;
  final String eventName;
  final Map<String, dynamic> body;

  PusherMessage(this.channelName, this.eventName, this.body);
}

class PusherError {
  final int code;
  final String message;

  PusherError(this.code, this.message);
}