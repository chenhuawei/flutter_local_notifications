import 'dart:async';
import 'dart:io';
import 'package:flutter/services.dart';
import 'package:meta/meta.dart';
import 'package:platform/platform.dart';
import 'initialization_settings.dart';
import 'notification_app_launch_details.dart';
import 'notification_details.dart';

/// Signature of callback passed to [initialize]. Callback triggered when user taps on a notification
typedef SelectNotificationCallback = Future<dynamic> Function(String payload);

// Signature of the callback that is triggered when a notification is shown whilst the app is in the foreground. Applicable to iOS versions < 10 only
typedef DidReceiveLocalNotificationCallback = Future<dynamic> Function(
    int id, String title, String body, String payload);
typedef RegisterForRemoteNotificationsCallback = Future<dynamic> Function(String payload);

/// The available intervals for periodically showing notifications
enum RepeatInterval { EveryMinute, Hourly, Daily, Weekly }

/// The days of the week
class Day {
  static const Sunday = const Day(1);
  static const Monday = const Day(2);
  static const Tuesday = const Day(3);
  static const Wednesday = const Day(4);
  static const Thursday = const Day(5);
  static const Friday = const Day(6);
  static const Saturday = const Day(7);

  static get values =>
      [Sunday, Monday, Tuesday, Wednesday, Thursday, Friday, Saturday];

  final int value;

  const Day(this.value);
}

/// Used for specifying a time in 24 hour format
class Time {
  /// The hour component of the time. Accepted range is 0 to 23 inclusive
  final int hour;

  /// The minutes component of the time. Accepted range is 0 to 59 inclusive
  final int minute;

  /// The seconds component of the time. Accepted range is 0 to 59 inclusive
  final int second;

  Time([this.hour = 0, this.minute = 0, this.second = 0]) {
    assert(this.hour >= 0 && this.hour < 24);
    assert(this.minute >= 0 && this.minute < 60);
    assert(this.second >= 0 && this.second < 60);
  }

  Map<String, int> toMap() {
    return <String, int>{
      'hour': hour,
      'minute': minute,
      'second': second,
    };
  }
}

class FlutterLocalNotificationsPlugin {
  factory FlutterLocalNotificationsPlugin() => _instance;

  @visibleForTesting
  FlutterLocalNotificationsPlugin.private(
      MethodChannel channel, Platform platform)
      : _channel = channel,
        _platform = platform;

  static final FlutterLocalNotificationsPlugin _instance =
      FlutterLocalNotificationsPlugin.private(
          const MethodChannel('dexterous.com/flutter/local_notifications'),
          const LocalPlatform());

  final MethodChannel _channel;
  final Platform _platform;

  SelectNotificationCallback selectNotificationCallback;

  DidReceiveLocalNotificationCallback didReceiveLocalNotificationCallback;

  List<Completer<String>> registerForRemoteNotificationCompleterList = [];

  String registerForRemoteNotificationToken;

  RegisterForRemoteNotificationsCallback registerForRemoteNotificationsCallback;

  /// Initializes the plugin. Call this method on application before using the plugin further
  Future<bool> initialize(InitializationSettings initializationSettings,
      {SelectNotificationCallback onSelectNotification, RegisterForRemoteNotificationsCallback registerForRemoteNotificationsCallback}) async {
    selectNotificationCallback = onSelectNotification;
    this.registerForRemoteNotificationsCallback = registerForRemoteNotificationsCallback;
    didReceiveLocalNotificationCallback =
        initializationSettings?.ios?.onDidReceiveLocalNotification;
    var serializedPlatformSpecifics =
        _retrievePlatformSpecificInitializationSettings(initializationSettings);
    _channel.setMethodCallHandler(_handleMethod);
    /*final CallbackHandle callback =
        PluginUtilities.getCallbackHandle(_callbackDispatcher);
    serializedPlatformSpecifics['callbackDispatcher'] = callback.toRawHandle();
    if (onShowNotification != null) {
      serializedPlatformSpecifics['onNotificationCallbackDispatcher'] =
          PluginUtilities.getCallbackHandle(onShowNotification).toRawHandle();
    }*/
    var result =
        await _channel.invokeMethod('initialize', serializedPlatformSpecifics);
    return result;
  }

  Future<NotificationAppLaunchDetails> getNotificationAppLaunchDetails() async {
    var result = await _channel.invokeMethod('getNotificationAppLaunchDetails');
    return NotificationAppLaunchDetails(result['notificationLaunchedApp'],
        result.containsKey('payload') ? result['payload'] : null);
  }

  Future<String> registerForRemoteNotifications(Map<String,dynamic> parameters) async {
    Completer<String> completer = Completer();
    if (registerForRemoteNotificationToken == null || registerForRemoteNotificationToken.isEmpty) {
      registerForRemoteNotificationCompleterList.add(completer);
      await _channel.invokeMethod('registerForRemoteNotifications', parameters);
    } else {
      completer.complete(registerForRemoteNotificationToken);
    }
    return completer.future;
  }

  /// Show a notification with an optional payload that will be passed back to the app when a notification is tapped
  Future show(int id, String title, String body,
      NotificationDetails notificationDetails,
      {String payload}) async {
    _validateId(id);
    var serializedPlatformSpecifics =
        _retrievePlatformSpecificNotificationDetails(notificationDetails);
    await _channel.invokeMethod('show', <String, dynamic>{
      'id': id,
      'title': title,
      'body': body,
      'platformSpecifics': serializedPlatformSpecifics,
      'payload': payload ?? ''
    });
  }

  /// Cancel/remove the notification with the specified id. This applies to notifications that have been scheduled and those that have already been presented.
  Future cancel(int id) async {
    _validateId(id);
    await _channel.invokeMethod('cancel', id);
  }

  /// Cancels/removes all notifications. This applies to notifications that have been scheduled and those that have already been presented.
  Future cancelAll() async {
    await _channel.invokeMethod('cancelAll');
  }

  /// Schedules a notification to be shown at the specified time with an optional payload that is passed through when a notification is tapped
  Future schedule(int id, String title, String body, DateTime scheduledDate,
      NotificationDetails notificationDetails,
      {String payload}) async {
    _validateId(id);
    var serializedPlatformSpecifics =
        _retrievePlatformSpecificNotificationDetails(notificationDetails);
    await _channel.invokeMethod('schedule', <String, dynamic>{
      'id': id,
      'title': title,
      'body': body,
      'millisecondsSinceEpoch': scheduledDate.millisecondsSinceEpoch,
      'platformSpecifics': serializedPlatformSpecifics,
      'payload': payload ?? ''
    });
  }

  /// Periodically show a notification using the specified interval.
  /// For example, specifying a hourly interval means the first time the notification will be an hour after the method has been called and then every hour after that.
  Future periodicallyShow(int id, String title, String body,
      RepeatInterval repeatInterval, NotificationDetails notificationDetails,
      {String payload}) async {
    _validateId(id);
    var serializedPlatformSpecifics =
        _retrievePlatformSpecificNotificationDetails(notificationDetails);
    await _channel.invokeMethod('periodicallyShow', <String, dynamic>{
      'id': id,
      'title': title,
      'body': body,
      'calledAt': DateTime.now().millisecondsSinceEpoch,
      'repeatInterval': repeatInterval.index,
      'platformSpecifics': serializedPlatformSpecifics,
      'payload': payload ?? ''
    });
  }

  /// Shows a notification on a daily interval at the specified time
  Future showDailyAtTime(int id, String title, String body,
      Time notificationTime, NotificationDetails notificationDetails,
      {String payload}) async {
    _validateId(id);
    var serializedPlatformSpecifics =
        _retrievePlatformSpecificNotificationDetails(notificationDetails);
    await _channel.invokeMethod('showDailyAtTime', <String, dynamic>{
      'id': id,
      'title': title,
      'body': body,
      'calledAt': DateTime.now().millisecondsSinceEpoch,
      'repeatInterval': RepeatInterval.Daily.index,
      'repeatTime': notificationTime.toMap(),
      'platformSpecifics': serializedPlatformSpecifics,
      'payload': payload ?? ''
    });
  }

  /// Shows a notification on a daily interval at the specified time
  Future showWeeklyAtDayAndTime(int id, String title, String body, Day day,
      Time notificationTime, NotificationDetails notificationDetails,
      {String payload}) async {
    _validateId(id);
    var serializedPlatformSpecifics =
        _retrievePlatformSpecificNotificationDetails(notificationDetails);
    await _channel.invokeMethod('showWeeklyAtDayAndTime', <String, dynamic>{
      'id': id,
      'title': title,
      'body': body,
      'calledAt': DateTime.now().millisecondsSinceEpoch,
      'repeatInterval': RepeatInterval.Weekly.index,
      'repeatTime': notificationTime.toMap(),
      'day': day.value,
      'platformSpecifics': serializedPlatformSpecifics,
      'payload': payload ?? ''
    });
  }

  Map<String, dynamic> _retrievePlatformSpecificNotificationDetails(
      NotificationDetails notificationDetails) {
    Map<String, dynamic> serializedPlatformSpecifics;
    if (_platform.isAndroid) {
      serializedPlatformSpecifics = notificationDetails?.android?.toMap();
    } else if (_platform.isIOS) {
      serializedPlatformSpecifics = notificationDetails?.iOS?.toMap();
    }
    return serializedPlatformSpecifics;
  }

  Map<String, dynamic> _retrievePlatformSpecificInitializationSettings(
      InitializationSettings initializationSettings) {
    Map<String, dynamic> serializedPlatformSpecifics;
    if (_platform.isAndroid) {
      serializedPlatformSpecifics = initializationSettings?.android?.toMap();
    } else if (_platform.isIOS) {
      serializedPlatformSpecifics = initializationSettings?.ios?.toMap();
    }
    return serializedPlatformSpecifics;
  }

  Future _handleMethod(MethodCall call) {
    switch (call.method) {
      case 'selectNotification':
        return selectNotificationCallback(call.arguments);

      case 'didReceiveLocalNotification':
        return didReceiveLocalNotificationCallback(
            call.arguments['id'],
            call.arguments['title'],
            call.arguments['body'],
            call.arguments['payload']);
      case 'didRegisterForRemoteNotificationsWithDeviceToken':
        registerForRemoteNotificationToken = call.arguments;
        print('dart token $registerForRemoteNotificationToken');
        _registerForRemoteNotificationsCallback();
        if (registerForRemoteNotificationsCallback != null) {
          registerForRemoteNotificationsCallback(
              registerForRemoteNotificationToken);
        }
        return null;
      case 'didRegisterForRemoteNotificationsFailed':

        return null;
      case 'didReceiveRemoteNotification':
        print('dart didReceiveRemoteNotification ${call.arguments}');
        return null;
      default:
        return Future.error('method not defined');
    }
  }

  void _registerForRemoteNotificationsCallback() {
    print('registerForRemoteNotificationsCallback $registerForRemoteNotificationCompleterList');
    if (registerForRemoteNotificationCompleterList == null || registerForRemoteNotificationCompleterList.isEmpty) {
      return;
    }
    registerForRemoteNotificationCompleterList.forEach((c){
      print('RemoteNotificationsCallback');
      c.complete(registerForRemoteNotificationToken);
    });
    registerForRemoteNotificationCompleterList.clear();
  }

  void _validateId(int id) {
    if (id > 0x7FFFFFFF || id < -0x80000000) {
      throw ArgumentError(
          'id must fit within the size of a 32-bit integer i.e. in the range [-2^31, 2^31 - 1]');
    }
  }
}
