package com.linxmobile.p2p

import android.util.Base64
import android.util.Log
import com.facebook.react.bridge.Arguments
import com.facebook.react.bridge.Promise
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.bridge.ReadableArray
import com.facebook.react.bridge.ReadableMap
import com.facebook.react.bridge.WritableArray
import com.facebook.react.bridge.WritableMap
import java.io.BufferedReader
import java.io.BufferedWriter
import java.io.InputStreamReader
import java.io.OutputStreamWriter
import java.net.HttpURLConnection
import java.net.InetSocketAddress
import java.net.Socket
import java.net.URL
import java.nio.charset.StandardCharsets
import java.util.Collections
import java.util.UUID
import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import org.json.JSONArray
import org.json.JSONObject

class XpodP2PSmokeModule(reactContext: ReactApplicationContext) : ReactContextBaseJavaModule(reactContext) {
  private val executor = Executors.newSingleThreadExecutor()
  private val winnerSelectionWindowMs = 50L

  override fun getName(): String = "XpodP2PSmoke"

  @ReactMethod
  fun run(request: ReadableMap, promise: Promise) {
    executor.execute {
      try {
        promise.resolve(runBlocking(request))
      } catch (error: Throwable) {
        promise.reject("XPOD_P2P_SMOKE_FAILED", error.message, error)
      }
    }
  }

  private fun runBlocking(request: ReadableMap): WritableMap {
    val signalSessionsUrl = request.requireString("signalSessionsUrl")
    val clientId = request.requireString("clientId")
    val nodeId = request.requireString("nodeId")
    val token = request.optionalString("token")
    val localCandidates = request.requireArray("localCandidates")
    val connectTimeoutMs = request.optionalInt("connectTimeoutMs", 8_000)
    val waitTimeoutMs = request.optionalInt("waitTimeoutMs", 20_000)
    val pollIntervalMs = request.optionalInt("pollIntervalMs", 1_000)
    val requestTimeoutMs = request.optionalInt("requestTimeoutMs", 10_000)
    val connectorEvents = Arguments.createArray()
    val connectorEventJson = Collections.synchronizedList(mutableListOf<JSONObject>())
    var stage = "create-session"
    var sessionId: String? = null

    try {
      val session = createSession(signalSessionsUrl, clientId, token, localCandidates)
      sessionId = session.optString("sessionId").ifBlank { null }
      val resolvedSessionId = sessionId ?: session.getString("sessionId")
      val sessionUrl = session.optString("signalingUrl", "$signalSessionsUrl/$resolvedSessionId")
      val bucket = firstCandidateBucket(localCandidates)
      stage = "wait-remote-candidates"
      val remoteCandidates = waitForRemoteCandidates(
        sessionUrl,
        token,
        clientId,
        bucket,
        waitTimeoutMs,
        pollIntervalMs,
      )
      val localCandidateList = compatibleLocalCandidatesFromSessionOrFallback(session, localCandidates, clientId, bucket)
      stage = "connect-raw-tcp"
      val connection = connectRawTcpCandidatePairs(
        localCandidateList,
        remoteCandidates,
        connectTimeoutMs,
        connectorEventJson,
      )

      connection.socket.use { connected ->
        val putFrame = requestFrame(request, "PUT")
        stage = "put-frame"
        val putResponse = sendFrame(connected, putFrame, requestTimeoutMs)
        val putStatus = putResponse.optInt("status", 0)
        val getFrame = requestFrame(request, "GET")
        stage = "get-frame"
        val getResponse = sendFrame(connected, getFrame, requestTimeoutMs)
        val body = decodeBody(getResponse)
        val status = getResponse.optInt("status", 0)
        appendConnectorEvents(connectorEvents, connectorEventJson)
        val result = Arguments.createMap().apply {
          putBoolean("smokeOk", putStatus in 200..299 && status in 200..299)
          putString("stage", "complete")
          putMap("route", Arguments.createMap().apply {
            putString("kind", "p2p")
            putString("id", connection.remoteCandidate.optString("id"))
            putString("targetUrl", "tcp-punch://${candidateHost(connection.remoteCandidate)}:${connection.remoteCandidate.getInt("port")}")
            putString("nodeId", nodeId)
            putString("localCandidateId", connection.localCandidate.optString("id"))
          })
          putInt("status", status)
          putString("body", body)
          putArray("connectorEvents", connectorEvents)
          putInt("putStatus", putStatus)
          putString("sessionId", resolvedSessionId)
          putString("clientAddress", clientAddressEvidence(connection.localCandidate))
        }
        logResult(result)
        return result
      }
    } catch (error: Throwable) {
      appendConnectorEvents(connectorEvents, connectorEventJson)
      return failureEvidence(stage, clientId, nodeId, signalSessionsUrl, sessionId, error, connectorEvents)
    }
  }

  private fun failureEvidence(
    stage: String,
    clientId: String,
    nodeId: String,
    signalSessionsUrl: String,
    sessionId: String?,
    error: Throwable,
    connectorEvents: WritableArray,
  ): WritableMap {
    val result = Arguments.createMap().apply {
      putBoolean("smokeOk", false)
      putString("stage", stage)
      putString("clientId", clientId)
      putString("nodeId", nodeId)
      putString("signalSessionsUrl", signalSessionsUrl)
      putString("sessionId", sessionId)
      putString("error", error.message ?: error.toString())
      putMap("route", Arguments.createMap().apply {
        putString("kind", "unknown")
      })
      putArray("connectorEvents", connectorEvents)
    }
    logResult(result)
    return result
  }

  private fun createSession(url: String, clientId: String, token: String?, localCandidates: ReadableArray): JSONObject {
    val body = JSONObject()
      .put("kind", "p2p")
      .put("clientId", clientId)
      .put("capabilities", JSONArray().put("tcp-punch"))
      .put("candidates", readableArrayToJson(localCandidates))
    return requestJson(url, "POST", token, body)
  }

  private data class RawTcpConnection(
    val socket: Socket,
    val localCandidate: JSONObject,
    val remoteCandidate: JSONObject,
  )

  private data class CandidatePair(
    val localCandidate: JSONObject,
    val remoteCandidate: JSONObject,
    val index: Int,
  )

  private data class RawTcpSuccess(
    val socket: Socket,
    val localCandidate: JSONObject,
    val remoteCandidate: JSONObject,
    val index: Int,
  )

  private fun waitForRemoteCandidates(
    sessionUrl: String,
    token: String?,
    clientId: String,
    bucket: Int?,
    waitTimeoutMs: Int,
    pollIntervalMs: Int,
  ): List<JSONObject> {
    val deadline = System.currentTimeMillis() + waitTimeoutMs
    while (System.currentTimeMillis() <= deadline) {
      val session = requestJson(sessionUrl, "GET", token, null)
      val candidates = session.optJSONArray("candidates") ?: JSONArray()
      val remoteCandidates = compatibleRemoteCandidates(candidates, clientId, bucket)
      if (remoteCandidates.isNotEmpty()) return remoteCandidates
      Thread.sleep(pollIntervalMs.toLong().coerceAtLeast(1L))
    }
    throw IllegalStateException("Timed out waiting for raw TCP P2P candidates after ${waitTimeoutMs}ms")
  }

  private fun compatibleRemoteCandidates(candidates: JSONArray, clientId: String, bucket: Int?): List<JSONObject> {
    val result = mutableListOf<JSONObject>()
    for (index in 0 until candidates.length()) {
      val candidate = candidates.optJSONObject(index) ?: continue
      if (!isRawTcpCandidate(candidate)) continue
      if (candidate.optString("role") == "client" && candidate.optString("sourceId") == clientId) continue
      if (bucket != null && candidateBucket(candidate) != bucket) continue
      if (candidateHost(candidate).isBlank()) continue
      result.add(candidate)
    }
    return result.sortedByDescending { it.optInt("priority", 0) }
  }

  private fun compatibleLocalCandidates(candidates: ReadableArray, bucket: Int?): List<JSONObject> {
    val json = readableArrayToJson(candidates)
    val result = mutableListOf<JSONObject>()
    for (index in 0 until json.length()) {
      val candidate = json.getJSONObject(index)
      if (isRawTcpCandidate(candidate) && (bucket == null || candidateBucket(candidate) == bucket)) {
        result.add(candidate)
      }
    }
    if (result.isEmpty()) {
      throw IllegalStateException("No local raw TCP candidate for bucket ${bucket ?: "unknown"}")
    }
    return result.sortedByDescending { it.optInt("priority", 0) }
  }

  private fun compatibleLocalCandidatesFromSessionOrFallback(
    session: JSONObject,
    fallbackCandidates: ReadableArray,
    clientId: String,
    bucket: Int?,
  ): List<JSONObject> {
    val candidates = session.optJSONArray("candidates") ?: JSONArray()
    val signaledCandidates = mutableListOf<JSONObject>()
    for (index in 0 until candidates.length()) {
      val candidate = candidates.optJSONObject(index) ?: continue
      if (!isRawTcpCandidate(candidate)) continue
      if (candidate.optString("role") != "client") continue
      if (candidate.optString("sourceId") != clientId) continue
      if (bucket != null && candidateBucket(candidate) != bucket) continue
      signaledCandidates.add(candidate)
    }
    if (signaledCandidates.isNotEmpty()) {
      return signaledCandidates.sortedByDescending { it.optInt("priority", 0) }
    }
    return compatibleLocalCandidates(fallbackCandidates, bucket)
  }

  private fun connectRawTcpCandidatePairs(
    localCandidates: List<JSONObject>,
    remoteCandidates: List<JSONObject>,
    timeoutMs: Int,
    events: MutableList<JSONObject>,
  ): RawTcpConnection {
    val pairs = candidatePairs(localCandidates, remoteCandidates)
    if (pairs.isEmpty()) {
      throw IllegalStateException("No compatible raw TCP P2P candidate pairs")
    }

    val pairExecutor = Executors.newCachedThreadPool()
    val finished = AtomicBoolean(false)
    val allAttemptsDone = CountDownLatch(pairs.size)
    val firstSuccessOrAllDone = CountDownLatch(1)
    val successes = Collections.synchronizedList(mutableListOf<RawTcpSuccess>())
    val errors = Collections.synchronizedList(mutableListOf<String>())

    for (pair in pairs) {
      pairExecutor.execute {
        try {
          val socket = connectRawTcp(pair.localCandidate, pair.remoteCandidate, timeoutMs, events)
          if (finished.get()) {
            socket.close()
          } else {
            successes.add(RawTcpSuccess(socket, pair.localCandidate, pair.remoteCandidate, pair.index))
            firstSuccessOrAllDone.countDown()
          }
        } catch (error: Throwable) {
          errors.add(error.message ?: error.toString())
        } finally {
          allAttemptsDone.countDown()
          if (allAttemptsDone.count == 0L) {
            firstSuccessOrAllDone.countDown()
          }
        }
      }
    }

    val maxRendezvousDelayMs = pairs.maxOf {
      maxOf(candidateRendezvousMs(it.localCandidate), candidateRendezvousMs(it.remoteCandidate)) - System.currentTimeMillis()
    }.coerceAtLeast(0L)
    val waitBudgetMs = maxRendezvousDelayMs + timeoutMs + winnerSelectionWindowMs + 1_000L
    try {
      val signaled = firstSuccessOrAllDone.await(waitBudgetMs, TimeUnit.MILLISECONDS)
      if (!signaled) {
        throw IllegalStateException("Raw TCP candidate connect timed out after ${waitBudgetMs}ms")
      }
      if (successes.isEmpty()) {
        throw IllegalStateException("Raw TCP candidate connect failed for all compatible pairs: ${errors.joinToString("; ")}")
      }
      allAttemptsDone.await(winnerSelectionWindowMs, TimeUnit.MILLISECONDS)
      val winner = selectRawTcpWinner(successes.toList())
      finished.set(true)
      closeLosingSockets(successes.toList(), winner)
      return RawTcpConnection(
        socket = winner.socket,
        localCandidate = winner.localCandidate,
        remoteCandidate = winner.remoteCandidate,
      )
    } finally {
      finished.set(true)
      pairExecutor.shutdownNow()
    }
  }

  private fun candidatePairs(
    localCandidates: List<JSONObject>,
    remoteCandidates: List<JSONObject>,
  ): List<CandidatePair> {
    val result = mutableListOf<CandidatePair>()
    var index = 0
    for (remoteCandidate in remoteCandidates) {
      for (localCandidate in localCandidates) {
        if (candidateBucket(localCandidate) == candidateBucket(remoteCandidate)) {
          result.add(CandidatePair(localCandidate, remoteCandidate, index))
          index += 1
        }
      }
    }
    return result
  }

  private fun selectRawTcpWinner(successes: List<RawTcpSuccess>): RawTcpSuccess =
    successes.sortedWith(compareBy<RawTcpSuccess> {
      rawTcpAttemptPairKey(it.localCandidate, it.remoteCandidate)
    }.thenBy { it.index }).first()

  private fun closeLosingSockets(successes: List<RawTcpSuccess>, winner: RawTcpSuccess) {
    for (success in successes) {
      if (success !== winner) {
        success.socket.close()
      }
    }
  }

  private fun rawTcpAttemptPairKey(local: JSONObject, remote: JSONObject): String =
    listOf(rawTcpEndpointKey(local), rawTcpEndpointKey(remote)).sorted().joinToString("<->")

  private fun rawTcpEndpointKey(candidate: JSONObject): String =
    listOf(
      candidate.optString("sourceId"),
      candidateHost(candidate),
      candidate.optString("port"),
      candidate.optString("id"),
    ).joinToString("|")

  private fun connectRawTcp(local: JSONObject, remote: JSONObject, timeoutMs: Int, events: MutableList<JSONObject>): Socket {
    val remoteHost = candidateHost(remote)
    val remotePort = remote.getInt("port")
    val localPort = local.getInt("port")
    val rendezvousTimeMs = maxOf(candidateRendezvousMs(local), candidateRendezvousMs(remote))
    val delayMs = rendezvousTimeMs - System.currentTimeMillis()
    if (delayMs > 0) Thread.sleep(delayMs)

    val deadline = System.currentTimeMillis() + timeoutMs
    var lastError: Throwable? = null
    while (System.currentTimeMillis() <= deadline && !Thread.currentThread().isInterrupted) {
      events.add(event("attempt", localPort, remotePort, null))
      val socket = Socket()
      try {
        socket.reuseAddress = true
        socket.bind(InetSocketAddress(localPort))
        socket.connect(InetSocketAddress(remoteHost, remotePort), maxOf(1, (deadline - System.currentTimeMillis()).toInt()))
        events.add(event("success", localPort, remotePort, null))
        return socket
      } catch (error: Throwable) {
        lastError = error
        socket.close()
        events.add(event("retry", localPort, remotePort, error.message))
        Thread.sleep(25)
      }
    }
    throw IllegalStateException("Raw TCP candidate connect timed out after ${timeoutMs}ms: ${lastError?.message ?: "unknown"}")
  }

  private fun sendFrame(socket: Socket, frame: JSONObject, timeoutMs: Int): JSONObject {
    socket.soTimeout = timeoutMs
    val requestId = frame.getString("requestId")
    val writer = BufferedWriter(OutputStreamWriter(socket.getOutputStream(), StandardCharsets.UTF_8))
    writer.write(JSONObject()
      .put("type", "xpod-p2p-http-request")
      .put("requestId", requestId)
      .put("frame", frame)
      .toString())
    writer.write("\n")
    writer.flush()

    val reader = BufferedReader(InputStreamReader(socket.getInputStream(), StandardCharsets.UTF_8))
    val line = reader.readLine() ?: throw IllegalStateException("P2P socket closed before response")
    val envelope = JSONObject(line)
    if (envelope.optString("type") == "xpod-p2p-http-error") {
      throw IllegalStateException(envelope.optString("error", "P2P HTTP frame failed"))
    }
    if (envelope.optString("type") != "xpod-p2p-http-response" || envelope.optString("requestId") != requestId) {
      throw IllegalStateException("Unexpected P2P frame envelope")
    }
    return envelope.getJSONObject("frame")
  }

  private fun requestFrame(request: ReadableMap, method: String): JSONObject {
    val frame = JSONObject()
      .put("protocol", "xpod-p2p-http/1")
      .put("requestId", "rn_${UUID.randomUUID()}")
      .put("method", method)
      .put("url", request.requireString("targetUrl"))
      .put("headers", headersToJson(request.requireMap("headers")))
    if (method != "GET" && method != "HEAD") {
      frame.put("bodyBase64", Base64.encodeToString(request.requireString("body").toByteArray(StandardCharsets.UTF_8), Base64.NO_WRAP))
    }
    return frame
  }

  private fun requestJson(url: String, method: String, token: String?, body: JSONObject?): JSONObject {
    val connection = (URL(url).openConnection() as HttpURLConnection).apply {
      requestMethod = method
      setRequestProperty("Accept", "application/json")
      if (body != null) setRequestProperty("Content-Type", "application/json")
      if (!token.isNullOrBlank()) setRequestProperty("Authorization", "Bearer $token")
      connectTimeout = 10_000
      readTimeout = 10_000
      doInput = true
      doOutput = body != null
    }
    if (body != null) {
      connection.outputStream.use { output -> output.write(body.toString().toByteArray(StandardCharsets.UTF_8)) }
    }
    val code = connection.responseCode
    val stream = if (code in 200..299) connection.inputStream else connection.errorStream
    val text = stream?.bufferedReader(StandardCharsets.UTF_8)?.use { it.readText() }.orEmpty()
    if (code !in 200..299) throw IllegalStateException("Signal request $method $url failed with $code: $text")
    return JSONObject(text)
  }

  private fun firstCandidateBucket(candidates: ReadableArray): Int? {
    val json = readableArrayToJson(candidates)
    for (index in 0 until json.length()) {
      val bucket = candidateBucket(json.getJSONObject(index))
      if (bucket != null) return bucket
    }
    return null
  }

  private fun isRawTcpCandidate(candidate: JSONObject): Boolean =
    candidate.optString("protocol") == "tcp" &&
      candidate.optString("transport") == "raw-tcp-hole-punch" &&
      candidate.has("port") &&
      candidate.optJSONObject("metadata")?.has("rendezvousTimeSeconds") == true

  private fun candidateBucket(candidate: JSONObject): Int? =
    candidate.optJSONObject("metadata")?.takeIf { it.has("bucket") }?.optInt("bucket")

  private fun candidateRendezvousMs(candidate: JSONObject): Long =
    (candidate.optJSONObject("metadata")?.optLong("rendezvousTimeSeconds") ?: 0L) * 1_000L

  private fun candidateHost(candidate: JSONObject): String =
    candidate.optString("host").ifBlank { candidate.optString("address").ifBlank { hostFromCandidateUrl(candidate.optString("url")) } }

  private fun clientAddressEvidence(candidate: JSONObject): String =
    when {
      candidate.optString("host").isNotBlank() -> "explicit-host"
      candidate.optString("address").isNotBlank() -> "signal-observed"
      candidate.optString("url").isNotBlank() -> "candidate-url"
      else -> "port-only"
    }

  private fun hostFromCandidateUrl(value: String): String {
    if (value.isBlank()) return ""
    return try { URL(value.replace("tcp-punch://", "http://")).host } catch (_: Throwable) { "" }
  }

  private fun headersToJson(headers: ReadableMap): JSONArray {
    val result = JSONArray()
    val iterator = headers.keySetIterator()
    while (iterator.hasNextKey()) {
      val key = iterator.nextKey()
      result.put(JSONArray().put(key).put(headers.getString(key) ?: ""))
    }
    return result
  }

  private fun readableArrayToJson(array: ReadableArray): JSONArray {
    val result = JSONArray()
    for (index in 0 until array.size()) {
      when (array.getType(index).name) {
        "Map" -> result.put(readableMapToJson(array.getMap(index)!!))
        "String" -> result.put(array.getString(index))
        "Number" -> result.put(array.getDouble(index))
        "Boolean" -> result.put(array.getBoolean(index))
        else -> result.put(JSONObject.NULL)
      }
    }
    return result
  }

  private fun readableMapToJson(map: ReadableMap): JSONObject {
    val result = JSONObject()
    val iterator = map.keySetIterator()
    while (iterator.hasNextKey()) {
      val key = iterator.nextKey()
      when (map.getType(key).name) {
        "Map" -> result.put(key, readableMapToJson(map.getMap(key)!!))
        "Array" -> result.put(key, readableArrayToJson(map.getArray(key)!!))
        "String" -> result.put(key, map.getString(key))
        "Number" -> result.put(key, map.getDouble(key))
        "Boolean" -> result.put(key, map.getBoolean(key))
        else -> result.put(key, JSONObject.NULL)
      }
    }
    return result
  }

  private fun decodeBody(frame: JSONObject): String {
    val encoded = frame.optString("bodyBase64")
    if (encoded.isBlank()) return ""
    return String(Base64.decode(encoded, Base64.DEFAULT), StandardCharsets.UTF_8)
  }

  private fun logResult(result: WritableMap) {
    try {
      Log.i(LOG_TAG, RESULT_MARKER + verifierEvidenceJson(result))
    } catch (error: Throwable) {
      Log.w(LOG_TAG, "Could not encode P2P smoke result JSON: ${error.message}")
    }
  }

  private fun verifierEvidenceJson(result: ReadableMap): String {
    val evidence = JSONObject()
      .put("smokeOk", result.hasKey("smokeOk") && !result.isNull("smokeOk") && result.getBoolean("smokeOk"))
      .put("route", if (result.hasKey("route") && !result.isNull("route")) readableMapToJson(result.getMap("route")!!) else JSONObject().put("kind", "unknown"))
      .put("connectorEvents", if (result.hasKey("connectorEvents") && !result.isNull("connectorEvents")) successConnectorEvents(result.getArray("connectorEvents")) else JSONArray())
    copyOptionalString(result, evidence, "stage")
    copyOptionalString(result, evidence, "clientId")
    copyOptionalString(result, evidence, "nodeId")
    copyOptionalString(result, evidence, "sessionId")
    copyOptionalString(result, evidence, "clientAddress")
    copyOptionalString(result, evidence, "error")
    copyOptionalInt(result, evidence, "status")
    copyOptionalInt(result, evidence, "putStatus")
    return evidence.toString()
  }

  private fun successConnectorEvents(events: ReadableArray?): JSONArray {
    val result = JSONArray()
    if (events == null) return result
    for (index in 0 until events.size()) {
      if (events.getType(index).name != "Map") continue
      val event = events.getMap(index) ?: continue
      if (event.getString("type") != "success") continue
      result.put(readableMapToJson(event))
    }
    return result
  }

  private fun copyOptionalString(source: ReadableMap, target: JSONObject, key: String) {
    if (source.hasKey(key) && !source.isNull(key)) {
      target.put(key, source.getString(key))
    }
  }

  private fun copyOptionalInt(source: ReadableMap, target: JSONObject, key: String) {
    if (source.hasKey(key) && !source.isNull(key)) {
      target.put(key, source.getDouble(key).toInt())
    }
  }

  private fun appendConnectorEvents(target: WritableArray, events: List<JSONObject>) {
    synchronized(events) {
      for (event in events) {
        target.pushMap(connectorEventToWritableMap(event))
      }
    }
  }

  private fun connectorEventToWritableMap(event: JSONObject): WritableMap =
    Arguments.createMap().apply {
      putString("type", event.optString("type", "unknown"))
      if (event.has("localPort")) putInt("localPort", event.optInt("localPort"))
      if (event.has("remotePort")) putInt("remotePort", event.optInt("remotePort"))
      if (event.has("message")) putString("message", event.optString("message"))
    }

  private fun event(type: String, localPort: Int, remotePort: Int, message: String?): JSONObject =
    JSONObject()
      .put("type", type)
      .put("localPort", localPort)
      .put("remotePort", remotePort)
      .apply {
        if (message != null) put("message", message)
      }

  private fun ReadableMap.requireString(key: String): String =
    getString(key) ?: throw IllegalArgumentException("$key is required")

  private fun ReadableMap.requireMap(key: String): ReadableMap =
    getMap(key) ?: throw IllegalArgumentException("$key is required")

  private fun ReadableMap.requireArray(key: String): ReadableArray =
    getArray(key) ?: throw IllegalArgumentException("$key is required")

  private fun ReadableMap.optionalString(key: String): String? =
    if (hasKey(key) && !isNull(key)) getString(key) else null

  private fun ReadableMap.optionalInt(key: String, fallback: Int): Int =
    if (hasKey(key) && !isNull(key)) getDouble(key).toInt() else fallback

  private companion object {
    private const val LOG_TAG = "XpodP2PSmoke"
    private const val RESULT_MARKER = "RESULT_JSON "
  }
}
