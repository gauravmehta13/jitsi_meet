import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'jitsi_meet_platform_interface.dart';

const MethodChannel _channel = MethodChannel('jitsi_meet');

const EventChannel _eventChannel = EventChannel('jitsi_meet_events');

/// An implementation of [JitsiMeetPlatform] that uses method channels.
class MethodChannelJitsiMeet extends JitsiMeetPlatform {
  final List<JitsiMeetingListener> _listeners = <JitsiMeetingListener>[];
  final Map<String, JitsiMeetingListener> _perMeetingListeners = {};

  @override
  Future<JitsiMeetingResponse> joinMeeting(
    JitsiMeetingOptions options, {
    JitsiMeetingListener? listener,
  }) async {
    // Attach a listener if it exists. The key is based on the serverURL + room
    if (listener != null) {
      String serverURL = options.serverURL ?? "https://meet.jit.si";
      String key;
      if (serverURL.endsWith("/")) {
        key = serverURL + options.room;
      } else {
        key = "$serverURL/${options.room}";
      }

      _perMeetingListeners.update(key, (oldListener) => listener, ifAbsent: () => listener);
      initialize();
    }
    Map<String, dynamic> meetOptions = {
      'room': options.room.trim(),
      'serverURL': options.serverURL?.trim(),
      'subject': options.subject,
      'token': options.token,
      'audioMuted': options.audioMuted,
      'audioOnly': options.audioOnly,
      'videoMuted': options.videoMuted,
      'featureFlags': options.getFeatureFlags(),
      'userDisplayName': options.userDisplayName,
      'userEmail': options.userEmail,
      'iosAppBarRGBAColor': options.iosAppBarRGBAColor,
    };

    return await _channel
        .invokeMethod<String>('joinMeeting', meetOptions)
        .then((message) => JitsiMeetingResponse(isSuccess: true, message: message))
        .catchError(
      (error) {
        return JitsiMeetingResponse(isSuccess: true, message: error.toString(), error: error);
      },
    );
  }

  @override
  closeMeeting() {
    _channel.invokeMethod('closeMeeting');
  }

  @override
  addListener(JitsiMeetingListener jitsiMeetingListener) {
    _listeners.add(jitsiMeetingListener);
    initialize();
  }

  @override
  removeListener(JitsiMeetingListener jitsiMeetingListener) {
    _listeners.remove(jitsiMeetingListener);
  }

  @override
  removeAllListeners() {
    _listeners.clear();
  }

  @override
  void executeCommand(String command, List<String> args) {}

  @override
  Widget buildView(List<String> extraJS) {
    // return empty container for compatibily
    return Container();
  }

  @override
  void initialize() {
    _eventChannel.receiveBroadcastStream().listen((dynamic message) {
      _broadcastToGlobalListeners(message);
      _broadcastToPerMeetingListeners(message);
    }, onError: (dynamic error) {
      debugPrint('Jitsi Meet broadcast error: $error');
      for (var listener in _listeners) {
        if (listener.onError != null) listener.onError!(error);
      }
      _perMeetingListeners.forEach((key, listener) {
        if (listener.onError != null) listener.onError!(error);
      });
    });
  }

  /// Sends a broadcast to global listeners added using addListener
  void _broadcastToGlobalListeners(message) {
    for (var listener in _listeners) {
      switch (message['event']) {
        case "onConferenceWillJoin":
          if (listener.onConferenceWillJoin != null) {
            listener.onConferenceWillJoin!(message);
          }
          break;
        case "onConferenceJoined":
          if (listener.onConferenceJoined != null) {
            listener.onConferenceJoined!(message);
          }
          break;
        case "onConferenceTerminated":
          if (listener.onConferenceTerminated != null) {
            listener.onConferenceTerminated!(message);
          }
          break;
      }
    }
  }

  /// Sends a broadcast to per meeting listeners added during joinMeeting
  void _broadcastToPerMeetingListeners(message) {
    String? url = message['url'];
    final listener = _perMeetingListeners[url];
    if (listener != null) {
      switch (message['event']) {
        case "onConferenceWillJoin":
          if (listener.onConferenceWillJoin != null) {
            listener.onConferenceWillJoin!(message);
          }
          break;
        case "onConferenceJoined":
          if (listener.onConferenceJoined != null) {
            listener.onConferenceJoined!(message);
          }
          break;
        case "onConferenceTerminated":
          if (listener.onConferenceTerminated != null) {
            listener.onConferenceTerminated!(message);
          }

          // Remove the listener from the map of _perMeetingListeners on terminate
          _perMeetingListeners.remove(listener);
          break;
      }
    }
  }
}
