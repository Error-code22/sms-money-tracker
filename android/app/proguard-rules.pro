# App-specific R8 keep rules.
# MainActivity and SmsReceiver are referenced from AndroidManifest.xml and are
# kept automatically by AGP. Keep the rest of the app package as a safety net
# for Kotlin metadata / MethodChannel wiring.
-keep class com.droner.sms_money_tracker.** { *; }

# org.json is used by the DB layer; it ships with the platform but keep it
# explicit so R8 never rewrites the constructors we rely on.
-keep class org.json.** { *; }
