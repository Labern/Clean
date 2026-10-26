// Gt7Direct for Android: the app talks to Gran Turismo 7 directly, no bridge.
// Same contract as the iOS plugin (see native/plugin/ios/Gt7DirectPlugin.swift).
package com.labern.gt7endgame

import android.annotation.SuppressLint
import android.app.Dialog
import android.os.Handler
import android.os.Looper
import android.util.Base64
import android.webkit.CookieManager
import android.webkit.JavascriptInterface
import android.webkit.WebView
import android.webkit.WebViewClient
import com.getcapacitor.JSObject
import com.getcapacitor.Plugin
import com.getcapacitor.PluginCall
import com.getcapacitor.PluginMethod
import com.getcapacitor.annotation.CapacitorPlugin
import org.json.JSONObject
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.NetworkInterface
import java.util.Timer
import kotlin.concurrent.thread
import kotlin.concurrent.timer

@CapacitorPlugin(name = "Gt7Direct")
class Gt7DirectPlugin : Plugin() {
    @Volatile private var running = false
    @Volatile private var ps5: String? = null
    private var recv: DatagramSocket? = null
    private var sender: DatagramSocket? = null
    private var beat: Timer? = null

    @PluginMethod
    fun startTelemetry(call: PluginCall) {
        stop()
        val target = call.getString("ps5") ?: "auto"
        try {
            recv = DatagramSocket(null).apply { reuseAddress = true; bind(InetSocketAddress(33740)) }
            sender = DatagramSocket()
        } catch (e: Exception) { call.reject("Couldn't open UDP port 33740: ${e.message}"); return }
        running = true
        ps5 = if (target == "auto") null else target
        thread(name = "gt7-recv") {
            val buf = ByteArray(2048)
            while (running) {
                try {
                    val p = DatagramPacket(buf, buf.size); recv?.receive(p)
                    val ip = p.address.hostAddress ?: continue
                    if (ps5 == null) { ps5 = ip; notifyListeners("status", JSObject().put("status", "live").put("ps5", ip)) }
                    val data = Base64.encodeToString(p.data.copyOf(p.length), Base64.NO_WRAP)
                    notifyListeners("packet", JSObject().put("data", data).put("from", ip))
                } catch (_: Exception) { if (!running) break }
            }
        }
        beat = timer(name = "gt7-beat", period = 10_000L) { heartbeat() }
        notifyListeners("status", JSObject().put("status", if (ps5 == null) "searching" else "connecting").put("ps5", ps5 ?: ""))
        call.resolve()
    }

    @PluginMethod
    fun stopTelemetry(call: PluginCall) { stop(); call.resolve() }

    private fun stop() {
        running = false
        beat?.cancel(); beat = null
        recv?.close(); recv = null
        sender?.close(); sender = null
    }

    private fun send(ip: String) {
        try { val b = byteArrayOf(0x7E); sender?.send(DatagramPacket(b, 1, InetAddress.getByName(ip), 33739)) } catch (_: Exception) {}
    }

    private fun heartbeat() {
        ps5?.let { send(it); return }
        val me = wifiIPv4() ?: return
        val base = me.substringBeforeLast('.')
        for (h in 1..254) { val ip = "$base.$h"; if (ip != me) send(ip) }
    }

    private fun wifiIPv4(): String? = NetworkInterface.getNetworkInterfaces().toList()
        .filter { it.isUp && !it.isLoopback }
        .flatMap { it.inetAddresses.toList() }
        .firstOrNull { it is Inet4Address && it.isSiteLocalAddress }?.hostAddress

    // ── GT7 account via gran-turismo.com ──
    private var web: WebView? = null
    private var dialog: Dialog? = null
    private var pending: PluginCall? = null
    private val main = Handler(Looper.getMainLooper())

    @PluginMethod fun gt7SignIn(call: PluginCall) { main.post { openWeb(call, true) } }
    @PluginMethod fun gt7Token(call: PluginCall) { main.post { openWeb(call, false) } }

    inner class Js {
        @JavascriptInterface fun post(json: String?) { main.post { if (json != null && json.contains("access_token")) finish(json, null) else if (dialog == null) finish(null, "signin") } }
    }

    @SuppressLint("SetJavaScriptEnabled")
    private fun openWeb(call: PluginCall, interactive: Boolean) {
        pending = call
        CookieManager.getInstance().setAcceptCookie(true)
        val w = WebView(activity)
        w.settings.javaScriptEnabled = true
        w.settings.domStorageEnabled = true
        w.addJavascriptInterface(Js(), "Gt7Native")
        w.webViewClient = object : WebViewClient() {
            override fun onPageFinished(view: WebView, url: String) {
                if (!url.startsWith("https://www.gran-turismo.com/")) return
                view.evaluateJavascript("fetch('/us/gt7/info/api/token/',{credentials:'include'}).then(r=>r.ok?r.text():null).then(t=>Gt7Native.post(t)).catch(()=>Gt7Native.post(null))", null)
            }
        }
        web = w
        w.loadUrl(if (interactive) "https://www.gran-turismo.com/us/gt7/user/mymenu/" else "https://www.gran-turismo.com/us/gt7/info/api/token/")
        if (interactive) {
            dialog = Dialog(activity, android.R.style.Theme_Black_NoTitleBar_Fullscreen).apply {
                setContentView(w); setOnCancelListener { finish(null, "cancelled") }; show()
            }
        } else main.postDelayed({ finish(null, "timeout") }, 15_000)
    }

    private fun finish(json: String?, error: String?) {
        val call = pending ?: return
        pending = null
        dialog?.dismiss(); dialog = null
        CookieManager.getInstance().flush()
        web?.destroy(); web = null
        if (json != null) {
            val o = JSONObject(json); val r = JSObject()
            for (k in o.keys()) r.put(k, o.get(k).toString())
            call.resolve(r)
        } else call.reject(error ?: "failed")
    }
}
