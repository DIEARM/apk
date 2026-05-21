# Reglas ProGuard para Zoho TPV Manager
-keepattributes Signature
-keepattributes *Annotation*

# OkHttp
-dontwarn okhttp3.**
-dontwarn okio.**
-keep class okhttp3.** { *; }

# Gson
-keep class com.tpv.zoho.manager.model.** { *; }
-keepclassmembers class com.tpv.zoho.manager.model.** { *; }

# Mantener clases principales
-keep class com.tpv.zoho.manager.** { *; }
