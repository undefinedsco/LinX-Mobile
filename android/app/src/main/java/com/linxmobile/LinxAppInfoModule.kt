package com.linxmobile

import android.os.Build
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.WritableNativeMap

class LinxAppInfoModule(
    private val reactContext: ReactApplicationContext
) : ReactContextBaseJavaModule(reactContext) {
  override fun getName(): String = "LinxAppInfo"

  @ReactMethod
  fun getVersion(promise: Promise) {
    try {
      val packageInfo = reactContext.packageManager.getPackageInfo(reactContext.packageName, 0)
      val versionCode = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
        packageInfo.longVersionCode.toDouble()
      } else {
        @Suppress("DEPRECATION")
        packageInfo.versionCode.toDouble()
      }
      promise.resolve(WritableNativeMap().apply {
        putString("versionName", packageInfo.versionName ?: "")
        putDouble("buildNumber", versionCode)
      })
    } catch (error: Exception) {
      promise.reject("LINX_APP_INFO_VERSION_FAILED", error)
    }
  }
}
