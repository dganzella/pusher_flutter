package com.apptreesoftware.pusher_flutter

import android.app.Activity
import com.pusher.client.Pusher
import com.pusher.client.PusherOptions
import com.pusher.client.channel.Channel
import com.pusher.client.channel.SubscriptionEventListener
import com.pusher.client.channel.PresenceChannelEventListener
import com.pusher.client.channel.User;
import com.pusher.client.connection.ConnectionEventListener
import com.pusher.client.connection.ConnectionState
import com.pusher.client.connection.ConnectionStateChange
import com.pusher.client.util.HttpAuthorizer

import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry.Registrar
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.common.StandardMethodCodec

import org.json.JSONObject
import java.lang.Exception
import org.json.JSONArray
import android.os.Handler
import android.os.Looper
import java.io.ByteArrayOutputStream;


class PusherFlutterPlugin() : MethodCallHandler, ConnectionEventListener {

    var pusher: Pusher? = null
    val messageStreamHandler = MessageStreamHandler()
    val connectionStreamHandler = ConnectionStreamHandler()
    val errorStreamHandler = ErrorStreamHandler()

    private val handler:Handler = Handler(Looper.getMainLooper())

    companion object {
        @JvmStatic
        fun registerWith(registrar: Registrar): Unit {

            val instance = PusherFlutterPlugin()

            val channel = MethodChannel(registrar.messenger(), "plugins.apptreesoftware.com/pusher")
            channel.setMethodCallHandler(instance)
            val connectionEventChannel = EventChannel(registrar.messenger(),
                                                      "plugins.apptreesoftware.com/pusher_connection", StandardMethodCodec(CustomMessageCodec()))

            connectionEventChannel.setStreamHandler(instance.connectionStreamHandler)
            val messageEventChannel = EventChannel(registrar.messenger(),
                                                   "plugins.apptreesoftware.com/pusher_message", StandardMethodCodec(CustomMessageCodec()))

            messageEventChannel.setStreamHandler(instance.messageStreamHandler)

            val errorEventChannel = EventChannel(registrar.messenger(), "plugins.apptreesoftware.com/pusher_error", StandardMethodCodec(CustomMessageCodec()))

            errorEventChannel.setStreamHandler(instance.errorStreamHandler)
        }
    }

    override fun onConnectionStateChange(state: ConnectionStateChange) {
        connectionStreamHandler.sendState(state.currentState)
    }

    override fun onError(message: String?, code: String?, p2: Exception?) {
        p2?.printStackTrace()
        val errMessage = message ?: p2?.localizedMessage ?: "Unknown error"
        errorStreamHandler.send(code ?: "", errMessage)
    }

    override fun onMethodCall(call: MethodCall, rawResult: Result): Unit {

        var result:MethodChannel.Result = MethodResultWrapper(rawResult)

        when (call.method) {
            "create" -> {
                val apiKey = call.argument<String>("api_key")
                val cluster = call.argument<String?>("cluster")

                val presenceAuthEndpoint = call.argument<String?>("presenceAuthEndpoint")
                val userToken = call.argument<String?>("userToken")
                //val csrfToken = call.argument<String?>("csrfToken")

                val pusherOptions = PusherOptions()
                if (cluster != null) {
                    pusherOptions.setCluster(cluster)
                }

                if (presenceAuthEndpoint != null && userToken != null /*&& csrfToken != null*/) {

                    val authorizer = HttpAuthorizer(presenceAuthEndpoint);
                    authorizer.setHeaders( mapOf("token" to userToken ) );

                    pusherOptions.setAuthorizer(authorizer).setEncrypted(true);
                }

                pusher = Pusher(apiKey, pusherOptions)
            }
            "connect" -> pusher?.connect(this, ConnectionState.ALL)
            "disconnect" -> pusher?.disconnect()
            "triggerEvent" -> {
                val pusher = this.pusher ?: return

                val event = call.argument<String>("event") ?: throw RuntimeException("Must provide event name")
                val channelName = call.argument<String>("channel") ?: throw RuntimeException("Must provide channel")
                val body = call.argument<String>("body") ?: throw RuntimeException("Must provide body")

                if(channelName.contains("presence")){
                    var channel = pusher.getPresenceChannel(channelName)

                    println("body");
                    println(body);

                    if (channel != null) {
                        channel.trigger(event, body);
                        result.success(null)
                    }
                    else{
                        throw RuntimeException("Presence channel not found")
                    }
                }
                else{
                    throw RuntimeException("Must be a presence channelto trigger events")
                }
            }
            "subscribe" -> {
                val pusher = this.pusher ?: return
                val event = call.argument<String>("event") ?: throw RuntimeException("Must provide event name")
                val channelName = call.argument<String>("channel") ?: throw RuntimeException("Must provide channel")

                if(channelName.contains("presence")){
                    var channel = pusher.getPresenceChannel(channelName)

                    if (channel == null) {

                        val channelEvList = object : PresenceChannelEventListener {
                            override fun onEvent( channelName: String, eventName : String, data: String){
                            }

                            override fun onSubscriptionSucceeded( channelName : String){
                                println("on sub succeeded");

                                handler.post(
                                    object : Runnable {
                                    public override fun run() {
                                        result.success(null);
                                    }
                                })
                            }

                            override fun onAuthenticationFailure( message : String, exception: Exception){
                                println("on auth fail");
                            }

                            override fun onUsersInformationReceived( channelName : String, users: Set<User>){
                                println("on user info received");
                            }

                            override fun userSubscribed( channelName : String, user: User){
                                println("user subscribed");
                            }

                            override fun userUnsubscribed( channelName : String, user: User){
                                println("user unsubscribed");
                            }
                        }

                        channel = pusher.subscribePresence(channelName, channelEvList)
                        listenToChannelPresence(channel, event)
                    }
                    else{
                        listenToChannelPresence(channel, event)
                        result.success(null);
                    }
                }
                else{
                    var channel = pusher.getChannel(channelName)

                    if (channel == null) {
                        channel = pusher.subscribe(channelName)
                    }
                    
                    listenToChannel(channel, event)

                    result.success(null)
                }
            }
            "unsubscribe" -> {
                val pusher = this.pusher ?: return
                val channelName = call.argument<String>("channel")
                pusher.unsubscribe(channelName)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun listenToChannel(channel: Channel, event: String) {
        val asyncDataListener = SubscriptionEventListener { _, eventName, data ->
            messageStreamHandler.send(channel.name, eventName, data)
        }
        channel.bind(event, asyncDataListener)
    }

    private fun listenToChannelPresence(channel: Channel, event: String) {

        val asyncDataListener = object : PresenceChannelEventListener {
            override fun onEvent( channelName: String, eventName : String, data: String){
                messageStreamHandler.send(channel.name, eventName, data)
            }

            override fun onSubscriptionSucceeded( channelName : String){
            }

            override fun onAuthenticationFailure( message : String, exception: Exception){
            }

            override fun onUsersInformationReceived( channelName : String, users: Set<User>){
            }

            override fun userSubscribed( channelName : String, user: User){
            }

            override fun userUnsubscribed( channelName : String, user: User){
            }
        }

        channel.bind(event, asyncDataListener)
    }
}

class MessageStreamHandler : EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null
    override fun onListen(arguments: Any?, rawSink: EventChannel.EventSink) {
        var sink:EventChannel.EventSink = EventSinkWrapper(rawSink)
        eventSink = sink
    }

    fun send(channel: String, event: String, data: Any) {
        val json = JSONObject(data as String)
        val map = jsonToMap(json)
        eventSink?.success(mapOf("channel" to channel,
                "event" to event,
                "body" to map))
    }

    override fun onCancel(p0: Any?) {
        eventSink = null
    }
}

class CustomMessageCodec() : StandardMessageCodec() {

    override fun writeValue(stream: ByteArrayOutputStream, value: Any?) {

        if(value != null && value.javaClass.name.contains("org.json.JSONObject"))
        {
            stream.write(0);
        }
        else
        {
            super.writeValue(stream, value);
        }
    }
}

class ErrorStreamHandler : EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null
    override fun onListen(arguments: Any?, rawSink: EventChannel.EventSink) {
        var sink:EventChannel.EventSink = EventSinkWrapper(rawSink)
        eventSink = sink
    }

    fun send(code : String, message : String) {
        val errCode = try { code.toInt() } catch (e : NumberFormatException) { 0 }
        eventSink?.success(mapOf("code" to errCode, "message" to message))
    }

    override fun onCancel(p0: Any?) {
        eventSink = null
    }
}

class ConnectionStreamHandler : EventChannel.StreamHandler {
    private var eventSink: EventChannel.EventSink? = null
    override fun onListen(argunents: Any?, rawSink: EventChannel.EventSink) {
        var sink:EventChannel.EventSink = EventSinkWrapper(rawSink)
        eventSink = sink
    }

    fun sendState(state: ConnectionState) {
        eventSink?.success(state.toString().toLowerCase())
    }

    override fun onCancel(p0: Any?) {
        eventSink = null
    }
}

fun jsonToMap(json: JSONObject?): Map<String, Any> {
    var retMap: Map<String, Any> = HashMap()

    if (json != null) {
        retMap = toMap(json)
    }
    return retMap
}

fun toMap(`object`: JSONObject): Map<String, Any> {
    val map = HashMap<String, Any>()

    val keysItr = `object`.keys().iterator()
    while (keysItr.hasNext()) {
        val key = keysItr.next()
        var value = `object`.get(key)

        if (value is JSONArray) {
            value = toList(value)
        } else if (value is JSONObject) {
            value = toMap(value)
        }
        map.put(key, value)
    }
    return map
}

fun toList(array: JSONArray): List<Any> {
    val list = ArrayList<Any>()
    for (i in 0..array.length() - 1) {
        var value = array.get(i)
        if (value is JSONArray) {
            value = toList(value)
        } else if (value is JSONObject) {
            value = toMap(value)
        }
        list.add(value)
    }
    return list
}

// MethodChannel.Result wrapper that responds on the platform thread.
private class MethodResultWrapper internal constructor(result:MethodChannel.Result): MethodChannel.Result {

    private val methodResult:MethodChannel.Result
    private val handler:Handler

    init{
        methodResult = result
        handler = Handler(Looper.getMainLooper())
    }


    override fun success(result: Any?) {
        handler.post(
                object : Runnable {
                    public override fun run() {
                        methodResult.success(result)
                    }
                })
    }

    override fun error(
            errorCode:String?, errorMessage:String?, errorDetails:Any?) {
        handler.post(
                object:Runnable {
                    public override fun run() {
                        methodResult.error(errorCode, errorMessage, errorDetails)
                    }
                })
    }
    override fun notImplemented() {
        handler.post(
                object:Runnable {
                    public override fun run() {
                        methodResult.notImplemented()
                    }
                })
    }
}

private class EventSinkWrapper internal constructor(result:EventChannel.EventSink): EventChannel.EventSink {

    private val methodResult:EventChannel.EventSink
    private val handler:Handler

    init{
        methodResult = result
        handler = Handler(Looper.getMainLooper())
    }


    override fun success(result: Any) {
        handler.post(
                object : Runnable {
                    public override fun run() {
                        methodResult.success(result)
                    }
                })
    }

    override fun error(errorCode:String, errorMessage:String, errorDetails:Any) {
        handler.post(
                object:Runnable {
                    public override fun run() {
                        methodResult.error(errorCode, errorMessage, errorDetails)
                    }
                })
    }
    override fun endOfStream() {
        handler.post(
                object:Runnable {
                    public override fun run() {
                        methodResult.endOfStream()
                    }
                })
    }
}