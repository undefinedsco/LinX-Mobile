package com.linxmobile

import android.os.Bundle
import com.facebook.react.ReactActivity
import com.facebook.react.ReactActivityDelegate
import com.facebook.react.defaults.DefaultNewArchitectureEntryPoint.fabricEnabled
import com.facebook.react.defaults.DefaultReactActivityDelegate

class MainActivity : ReactActivity() {
  override fun getMainComponentName(): String = "LinXP2PSmoke"

  override fun createReactActivityDelegate(): ReactActivityDelegate =
      object : DefaultReactActivityDelegate(this, mainComponentName, fabricEnabled) {
        override fun getLaunchOptions(): Bundle {
          val defaults = Bundle()
          copyStringExtra(defaults, "localSpUrl", "xpod.p2p.localSpUrl")
          copyStringExtra(defaults, "idpUrl", "xpod.p2p.idpUrl")
          copyStringExtra(defaults, "storageUrl", "xpod.p2p.storageUrl")
          copyStringExtra(defaults, "apiBaseUrl", "xpod.p2p.apiBaseUrl")
          copyStringExtra(defaults, "nodeId", "xpod.p2p.nodeId")
          copyStringExtra(defaults, "clientId", "xpod.p2p.clientId")
          copyStringExtra(defaults, "resourcePath", "xpod.p2p.resourcePath")
          copyStringExtra(defaults, "updateManifestUrl", "xpod.update.manifestUrl")
          return Bundle().apply {
            putBundle("p2pSmokeDefaults", defaults)
          }
        }
      }

  private fun copyStringExtra(target: Bundle, field: String, extraName: String) {
    val value = intent?.getStringExtra(extraName)?.trim().orEmpty()
    if (value.isNotEmpty()) {
      target.putString(field, value)
    }
  }
}
