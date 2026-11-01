-keep class **.zego.** { *; }

# OneSignal Native Notification Service Extension
-keep class com.example.instant_messenger.InstantMessengerNotificationExtension { *; }
-keep interface com.onesignal.notifications.INotificationServiceExtension { *; }
-keep interface com.onesignal.notifications.INotificationReceivedEvent { *; }
