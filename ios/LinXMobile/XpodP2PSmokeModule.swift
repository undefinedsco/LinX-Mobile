import Foundation
import Network

@objc(XpodP2PSmoke)
final class XpodP2PSmokeModule: NSObject {
  private let queue = DispatchQueue(label: "co.undefineds.linx.xpod-p2p-smoke", qos: .userInitiated)
  private let winnerSelectionWindowMs: Int = 50
  private let resultMarker = "RESULT_JSON "

  @objc static func requiresMainQueueSetup() -> Bool {
    false
  }

  @objc(run:resolver:rejecter:)
  func run(
    _ request: NSDictionary,
    resolver resolve: @escaping (Any?) -> Void,
    rejecter reject: @escaping (String, String?, NSError?) -> Void
  ) {
    queue.async {
      do {
        resolve(try self.runBlocking(request))
      } catch {
        reject("XPOD_P2P_SMOKE_FAILED", error.localizedDescription, error as NSError)
      }
    }
  }

  private func runBlocking(_ request: NSDictionary) throws -> [String: Any] {
    let signalSessionsUrl = try request.requireString("signalSessionsUrl")
    let clientId = try request.requireString("clientId")
    let nodeId = try request.requireString("nodeId")
    let token = request.optionalString("token")
    let localCandidates = request.optionalArray("localCandidates")
    let connectTimeoutMs = request.optionalInt("connectTimeoutMs", fallback: 8_000)
    let waitTimeoutMs = request.optionalInt("waitTimeoutMs", fallback: 20_000)
    let pollIntervalMs = request.optionalInt("pollIntervalMs", fallback: 1_000)
    let requestTimeoutMs = request.optionalInt("requestTimeoutMs", fallback: 10_000)
    var connectorEvents: [[String: Any]] = []
    var stage = "create-session"
    var sessionId: String?

    do {
      let session = try createSession(signalSessionsUrl, clientId: clientId, token: token, localCandidates: localCandidates)
      sessionId = session.string("sessionId")
      let resolvedSessionId = try session.requireString("sessionId")
      let sessionUrl = session.string("signalingUrl") ?? "\(signalSessionsUrl)/\(resolvedSessionId)"
      let bucket = firstCandidateBucket(localCandidates)

      stage = "wait-remote-candidates"
      let remoteCandidates = try waitForRemoteCandidates(
        sessionUrl,
        token: token,
        clientId: clientId,
        bucket: bucket,
        waitTimeoutMs: waitTimeoutMs,
        pollIntervalMs: pollIntervalMs
      )
      let localCandidateList = try compatibleLocalCandidatesFromSessionOrFallback(
        session,
        fallbackCandidates: localCandidates,
        clientId: clientId,
        bucket: bucket
      )

      stage = "connect-raw-tcp"
      let connection = try connectRawTcpCandidatePairs(
        localCandidates: localCandidateList,
        remoteCandidates: remoteCandidates,
        timeoutMs: connectTimeoutMs,
        events: &connectorEvents
      )
      defer { Darwin.close(connection.fd) }

      stage = "put-frame"
      let putResponse = try sendFrame(connection.fd, frame: requestFrame(request, method: "PUT"), timeoutMs: requestTimeoutMs)
      let putStatus = putResponse.int("status") ?? 0
      stage = "get-frame"
      let getResponse = try sendFrame(connection.fd, frame: requestFrame(request, method: "GET"), timeoutMs: requestTimeoutMs)
      let body = decodeBody(getResponse)
      let status = getResponse.int("status") ?? 0

      let result: [String: Any] = [
        "smokeOk": (200...299).contains(putStatus) && (200...299).contains(status),
        "stage": "complete",
        "route": [
          "kind": "p2p",
          "id": connection.remoteCandidate.string("id") ?? "",
          "targetUrl": "tcp-punch://\(candidateHost(connection.remoteCandidate)):\(try connection.remoteCandidate.requireInt("port"))",
          "nodeId": nodeId,
          "localCandidateId": connection.localCandidate.string("id") ?? "",
        ],
        "status": status,
        "body": body,
        "connectorEvents": connectorEvents,
        "putStatus": putStatus,
        "sessionId": resolvedSessionId,
        "clientAddress": clientAddressEvidence(connection.localCandidate),
      ]
      logResult(result)
      return result
    } catch {
      let result = failureEvidence(
        stage: stage,
        clientId: clientId,
        nodeId: nodeId,
        signalSessionsUrl: signalSessionsUrl,
        sessionId: sessionId,
        error: error,
        connectorEvents: connectorEvents
      )
      logResult(result)
      return result
    }
  }

  private func failureEvidence(
    stage: String,
    clientId: String,
    nodeId: String,
    signalSessionsUrl: String,
    sessionId: String?,
    error: Error,
    connectorEvents: [[String: Any]]
  ) -> [String: Any] {
    [
      "smokeOk": false,
      "stage": stage,
      "clientId": clientId,
      "nodeId": nodeId,
      "signalSessionsUrl": signalSessionsUrl,
      "sessionId": sessionId as Any,
      "error": error.localizedDescription,
      "route": ["kind": "unknown"],
      "connectorEvents": connectorEvents,
    ]
  }

  private func createSession(
    _ url: String,
    clientId: String,
    token: String?,
    localCandidates: [[String: Any]]
  ) throws -> [String: Any] {
    try requestJson(url, method: "POST", token: token, body: [
      "kind": "p2p",
      "clientId": clientId,
      "capabilities": ["tcp-punch"],
      "candidates": localCandidates,
    ])
  }

  private struct RawTcpConnection {
    let fd: Int32
    let localCandidate: [String: Any]
    let remoteCandidate: [String: Any]
  }

  private struct CandidatePair {
    let localCandidate: [String: Any]
    let remoteCandidate: [String: Any]
    let index: Int
  }

  private struct RawTcpSuccess {
    let fd: Int32
    let localCandidate: [String: Any]
    let remoteCandidate: [String: Any]
    let index: Int
  }

  private func waitForRemoteCandidates(
    _ sessionUrl: String,
    token: String?,
    clientId: String,
    bucket: Int?,
    waitTimeoutMs: Int,
    pollIntervalMs: Int
  ) throws -> [[String: Any]] {
    let deadline = Date().timeIntervalSince1970 + Double(waitTimeoutMs) / 1_000.0
    while Date().timeIntervalSince1970 <= deadline {
      let session = try requestJson(sessionUrl, method: "GET", token: token, body: nil)
      let candidates = session.array("candidates")
      let remoteCandidates = compatibleRemoteCandidates(candidates, clientId: clientId, bucket: bucket)
      if !remoteCandidates.isEmpty {
        return remoteCandidates
      }
      Thread.sleep(forTimeInterval: Double(max(1, pollIntervalMs)) / 1_000.0)
    }
    throw SmokeError("Timed out waiting for raw TCP P2P candidates after \(waitTimeoutMs)ms")
  }

  private func compatibleRemoteCandidates(
    _ candidates: [[String: Any]],
    clientId: String,
    bucket: Int?
  ) -> [[String: Any]] {
    candidates
      .filter { candidate in
        isRawTcpCandidate(candidate)
          && !(candidate.string("role") == "client" && candidate.string("sourceId") == clientId)
          && (bucket == nil || candidateBucket(candidate) == bucket)
          && !candidateHost(candidate).isEmpty
      }
      .sorted { ($0.int("priority") ?? 0) > ($1.int("priority") ?? 0) }
  }

  private func compatibleLocalCandidates(
    _ candidates: [[String: Any]],
    bucket: Int?
  ) throws -> [[String: Any]] {
    let result = candidates
      .filter { isRawTcpCandidate($0) && (bucket == nil || candidateBucket($0) == bucket) }
      .sorted { ($0.int("priority") ?? 0) > ($1.int("priority") ?? 0) }
    if result.isEmpty {
      throw SmokeError("No local raw TCP candidate for bucket \(bucket.map(String.init) ?? "unknown")")
    }
    return result
  }

  private func compatibleLocalCandidatesFromSessionOrFallback(
    _ session: [String: Any],
    fallbackCandidates: [[String: Any]],
    clientId: String,
    bucket: Int?
  ) throws -> [[String: Any]] {
    let signaled = session.array("candidates")
      .filter { candidate in
        isRawTcpCandidate(candidate)
          && candidate.string("role") == "client"
          && candidate.string("sourceId") == clientId
          && (bucket == nil || candidateBucket(candidate) == bucket)
      }
      .sorted { ($0.int("priority") ?? 0) > ($1.int("priority") ?? 0) }
    if !signaled.isEmpty {
      return signaled
    }
    return try compatibleLocalCandidates(fallbackCandidates, bucket: bucket)
  }

  private func connectRawTcpCandidatePairs(
    localCandidates: [[String: Any]],
    remoteCandidates: [[String: Any]],
    timeoutMs: Int,
    events: inout [[String: Any]]
  ) throws -> RawTcpConnection {
    let pairs = candidatePairs(localCandidates: localCandidates, remoteCandidates: remoteCandidates)
    if pairs.isEmpty {
      throw SmokeError("No compatible raw TCP P2P candidate pairs")
    }

    let group = DispatchGroup()
    let lock = NSLock()
    let firstSuccessOrAllDone = DispatchSemaphore(value: 0)
    var successes: [RawTcpSuccess] = []
    var errors: [String] = []
    var allEvents: [[String: Any]] = []
    var shouldStop = false
    var firstSuccessOrAllDoneSignaled = false

    for pair in pairs {
      group.enter()
      DispatchQueue.global(qos: .userInitiated).async {
        var localEvents: [[String: Any]] = []
        do {
          let fd = try self.connectRawTcp(
            local: pair.localCandidate,
            remote: pair.remoteCandidate,
            timeoutMs: timeoutMs,
            events: &localEvents,
            shouldStop: {
              lock.lock()
              defer { lock.unlock() }
              return shouldStop
            }
          )

          lock.lock()
          allEvents.append(contentsOf: localEvents)
          if shouldStop {
            lock.unlock()
            Darwin.close(fd)
          } else {
            successes.append(RawTcpSuccess(
              fd: fd,
              localCandidate: pair.localCandidate,
              remoteCandidate: pair.remoteCandidate,
              index: pair.index
            ))
            if !firstSuccessOrAllDoneSignaled {
              firstSuccessOrAllDoneSignaled = true
              firstSuccessOrAllDone.signal()
            }
            lock.unlock()
          }
        } catch {
          lock.lock()
          allEvents.append(contentsOf: localEvents)
          errors.append(error.localizedDescription)
          lock.unlock()
        }
        group.leave()
      }
    }

    group.notify(queue: DispatchQueue.global(qos: .userInitiated)) {
      lock.lock()
      if !firstSuccessOrAllDoneSignaled {
        firstSuccessOrAllDoneSignaled = true
        firstSuccessOrAllDone.signal()
      }
      lock.unlock()
    }

    let maxRendezvousDelayMs = pairs
      .map { max(candidateRendezvousMs($0.localCandidate), candidateRendezvousMs($0.remoteCandidate)) - Int64(Date().timeIntervalSince1970 * 1_000) }
      .max() ?? 0
    let waitBudgetMs = max(0, maxRendezvousDelayMs) + Int64(timeoutMs + winnerSelectionWindowMs + 1_000)
    guard firstSuccessOrAllDone.wait(timeout: .now() + .milliseconds(Int(waitBudgetMs))) == .success else {
      lock.lock()
      shouldStop = true
      lock.unlock()
      group.wait()
      lock.lock()
      events.append(contentsOf: allEvents)
      lock.unlock()
      throw SmokeError("Raw TCP candidate connect timed out after \(waitBudgetMs)ms")
    }

    lock.lock()
    let hasSuccess = !successes.isEmpty
    lock.unlock()
    if hasSuccess && winnerSelectionWindowMs > 0 {
      _ = group.wait(timeout: .now() + .milliseconds(winnerSelectionWindowMs))
    }
    lock.lock()
    if hasSuccess {
      shouldStop = true
    }
    lock.unlock()
    group.wait()

    lock.lock()
    let successSnapshot = successes
    let errorSnapshot = errors
    let eventSnapshot = allEvents
    lock.unlock()
    events.append(contentsOf: eventSnapshot)

    if successSnapshot.isEmpty {
      throw SmokeError("Raw TCP candidate connect failed for all compatible pairs: \(errorSnapshot.joined(separator: "; "))")
    }

    let winner = selectRawTcpWinner(successSnapshot)
    for success in successSnapshot where success.index != winner.index {
      Darwin.close(success.fd)
    }
    return RawTcpConnection(fd: winner.fd, localCandidate: winner.localCandidate, remoteCandidate: winner.remoteCandidate)
  }

  private func candidatePairs(localCandidates: [[String: Any]], remoteCandidates: [[String: Any]]) -> [CandidatePair] {
    var result: [CandidatePair] = []
    var index = 0
    for remoteCandidate in remoteCandidates {
      for localCandidate in localCandidates where candidateBucket(localCandidate) == candidateBucket(remoteCandidate) {
        result.append(CandidatePair(localCandidate: localCandidate, remoteCandidate: remoteCandidate, index: index))
        index += 1
      }
    }
    return result
  }

  private func selectRawTcpWinner(_ successes: [RawTcpSuccess]) -> RawTcpSuccess {
    successes.sorted { left, right in
      let leftKey = rawTcpAttemptPairKey(local: left.localCandidate, remote: left.remoteCandidate)
      let rightKey = rawTcpAttemptPairKey(local: right.localCandidate, remote: right.remoteCandidate)
      if leftKey == rightKey {
        return left.index < right.index
      }
      return leftKey < rightKey
    }.first!
  }

  private func rawTcpAttemptPairKey(local: [String: Any], remote: [String: Any]) -> String {
    [rawTcpEndpointKey(local), rawTcpEndpointKey(remote)].sorted().joined(separator: "<->")
  }

  private func rawTcpEndpointKey(_ candidate: [String: Any]) -> String {
    [
      candidate.string("sourceId") ?? "",
      candidateHost(candidate),
      candidate.string("port") ?? String(candidate.int("port") ?? 0),
      candidate.string("id") ?? "",
    ].joined(separator: "|")
  }

  private func connectRawTcp(
    local: [String: Any],
    remote: [String: Any],
    timeoutMs: Int,
    events: inout [[String: Any]],
    shouldStop: () -> Bool = { false }
  ) throws -> Int32 {
    // The iOS bridge is intentionally native TCP. Network.NWConnection is imported
    // for the platform transport boundary, while POSIX sockets are used here so we
    // can bind the exact local port required by raw TCP hole punching.
    _ = NWConnection.self
    let remoteHost = candidateHost(remote)
    let remotePort = try remote.requireInt("port")
    let localPort = try local.requireInt("port")
    let rendezvousTimeMs = max(candidateRendezvousMs(local), candidateRendezvousMs(remote))
    let delayMs = rendezvousTimeMs - Int64(Date().timeIntervalSince1970 * 1_000)
    if delayMs > 0 {
      Thread.sleep(forTimeInterval: Double(delayMs) / 1_000.0)
    }

    let deadline = Date().timeIntervalSince1970 + Double(timeoutMs) / 1_000.0
    var lastError: String?
    while Date().timeIntervalSince1970 <= deadline && !shouldStop() {
      events.append(event(type: "attempt", localPort: localPort, remotePort: remotePort, message: nil))
      let fd = socket(AF_INET, SOCK_STREAM, 0)
      if fd < 0 {
        throw SmokeError("socket() failed")
      }
      do {
        try configureReusableSocket(fd)
        try bindSocket(fd, localPort: localPort)
        try connectSocket(fd, host: remoteHost, port: remotePort, timeoutMs: max(1, Int((deadline - Date().timeIntervalSince1970) * 1_000)))
        events.append(event(type: "success", localPort: localPort, remotePort: remotePort, message: nil))
        return fd
      } catch {
        lastError = error.localizedDescription
        Darwin.close(fd)
        events.append(event(type: "retry", localPort: localPort, remotePort: remotePort, message: error.localizedDescription))
        Thread.sleep(forTimeInterval: 0.025)
      }
    }
    throw SmokeError("Raw TCP candidate connect timed out after \(timeoutMs)ms: \(lastError ?? "unknown")")
  }

  private func configureReusableSocket(_ fd: Int32) throws {
    var yes: Int32 = 1
    guard setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout<Int32>.size)) == 0 else {
      throw SmokeError("setsockopt(SO_REUSEADDR) failed")
    }
  }

  private func setSocketTimeouts(_ fd: Int32, timeoutMs: Int) throws {
    var timeout = timeval(tv_sec: timeoutMs / 1_000, tv_usec: Int32((timeoutMs % 1_000) * 1_000))
    guard setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0 else {
      throw SmokeError("setsockopt(SO_RCVTIMEO) failed")
    }
    guard setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size)) == 0 else {
      throw SmokeError("setsockopt(SO_SNDTIMEO) failed")
    }
  }

  private func bindSocket(_ fd: Int32, localPort: Int) throws {
    var addr = sockaddr_in()
    addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_port = in_port_t(localPort).bigEndian
    addr.sin_addr = in_addr(s_addr: INADDR_ANY.bigEndian)
    try withSockaddr(&addr) { pointer, length in
      guard Darwin.bind(fd, pointer, length) == 0 else {
        throw SmokeError("bind(localPort=\(localPort)) failed: \(String(cString: strerror(errno)))")
      }
    }
  }

  private func connectSocket(_ fd: Int32, host: String, port: Int, timeoutMs: Int) throws {
    var hints = addrinfo(
      ai_flags: 0,
      ai_family: AF_INET,
      ai_socktype: SOCK_STREAM,
      ai_protocol: IPPROTO_TCP,
      ai_addrlen: 0,
      ai_canonname: nil,
      ai_addr: nil,
      ai_next: nil
    )
    var result: UnsafeMutablePointer<addrinfo>?
    let lookup = getaddrinfo(host, String(port), &hints, &result)
    guard lookup == 0, let result else {
      throw SmokeError("getaddrinfo(\(host)) failed: \(String(cString: gai_strerror(lookup)))")
    }
    defer { freeaddrinfo(result) }

    let flags = fcntl(fd, F_GETFL, 0)
    _ = fcntl(fd, F_SETFL, flags | O_NONBLOCK)
    let connectResult = Darwin.connect(fd, result.pointee.ai_addr, result.pointee.ai_addrlen)
    if connectResult == 0 {
      _ = fcntl(fd, F_SETFL, flags)
      return
    }
    guard errno == EINPROGRESS else {
      throw SmokeError("connect(\(host):\(port)) failed: \(String(cString: strerror(errno)))")
    }

    var writeSet = fd_set()
    fdZero(&writeSet)
    fdSet(fd, set: &writeSet)
    var timeout = timeval(tv_sec: timeoutMs / 1_000, tv_usec: Int32((timeoutMs % 1_000) * 1_000))
    let selected = select(fd + 1, nil, &writeSet, nil, &timeout)
    guard selected > 0 else {
      throw SmokeError("connect(\(host):\(port)) timed out")
    }
    var socketError: Int32 = 0
    var socketErrorLength = socklen_t(MemoryLayout<Int32>.size)
    guard getsockopt(fd, SOL_SOCKET, SO_ERROR, &socketError, &socketErrorLength) == 0, socketError == 0 else {
      throw SmokeError("connect(\(host):\(port)) failed: \(String(cString: strerror(socketError)))")
    }
    _ = fcntl(fd, F_SETFL, flags)
  }

  private func sendFrame(_ fd: Int32, frame: [String: Any], timeoutMs: Int) throws -> [String: Any] {
    try setSocketTimeouts(fd, timeoutMs: timeoutMs)
    let requestId = try frame.requireString("requestId")
    let envelope: [String: Any] = [
      "type": "xpod-p2p-http-request",
      "requestId": requestId,
      "frame": frame,
    ]
    let data = try JSONSerialization.data(withJSONObject: envelope)
    guard let line = String(data: data, encoding: .utf8) else {
      throw SmokeError("Could not encode P2P request frame")
    }
    try writeLine(line, fd: fd, timeoutMs: timeoutMs)
    let responseLine = try readLine(fd: fd, timeoutMs: timeoutMs)
    guard let responseData = responseLine.data(using: .utf8),
          let response = try JSONSerialization.jsonObject(with: responseData) as? [String: Any] else {
      throw SmokeError("Unexpected P2P frame envelope")
    }
    if response.string("type") == "xpod-p2p-http-error" {
      throw SmokeError(response.string("error") ?? "P2P HTTP frame failed")
    }
    guard response.string("type") == "xpod-p2p-http-response",
          response.string("requestId") == requestId,
          let responseFrame = response["frame"] as? [String: Any] else {
      throw SmokeError("Unexpected P2P frame envelope")
    }
    return responseFrame
  }

  private func requestFrame(_ request: NSDictionary, method: String) throws -> [String: Any] {
    var frame: [String: Any] = [
      "protocol": "xpod-p2p-http/1",
      "requestId": "rn_\(UUID().uuidString)",
      "method": method,
      "url": try request.requireString("targetUrl"),
      "headers": headersToJson(request.optionalDictionary("headers")),
    ]
    if method != "GET" && method != "HEAD" {
      let body = try request.requireString("body")
      frame["bodyBase64"] = Data(body.utf8).base64EncodedString()
    }
    return frame
  }

  private func requestJson(_ url: String, method: String, token: String?, body: [String: Any]?) throws -> [String: Any] {
    guard let target = URL(string: url) else {
      throw SmokeError("Invalid URL: \(url)")
    }
    var request = URLRequest(url: target, timeoutInterval: 10)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let body {
      request.setValue("application/json", forHTTPHeaderField: "Content-Type")
      request.httpBody = try JSONSerialization.data(withJSONObject: body)
    }
    if let token, !token.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
      request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    }

    let semaphore = DispatchSemaphore(value: 0)
    var result: Result<(Data, HTTPURLResponse), Error>?
    URLSession.shared.dataTask(with: request) { data, response, error in
      if let error {
        result = .failure(error)
      } else if let http = response as? HTTPURLResponse {
        result = .success((data ?? Data(), http))
      } else {
        result = .failure(SmokeError("Signal request returned no HTTP response"))
      }
      semaphore.signal()
    }.resume()
    semaphore.wait()

    let (data, response) = try result?.get() ?? { throw SmokeError("Signal request failed") }()
    let text = String(data: data, encoding: .utf8) ?? ""
    guard (200...299).contains(response.statusCode) else {
      throw SmokeError("Signal request \(method) \(url) failed with \(response.statusCode): \(text)")
    }
    guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
      throw SmokeError("Signal request \(method) \(url) returned non-object JSON")
    }
    return json
  }

  private func firstCandidateBucket(_ candidates: [[String: Any]]) -> Int? {
    for candidate in candidates {
      if let bucket = candidateBucket(candidate) {
        return bucket
      }
    }
    return nil
  }

  private func isRawTcpCandidate(_ candidate: [String: Any]) -> Bool {
    candidate.string("protocol") == "tcp"
      && candidate.string("transport") == "raw-tcp-hole-punch"
      && candidate.int("port") != nil
      && candidate.dictionary("metadata")?["rendezvousTimeSeconds"] != nil
  }

  private func candidateBucket(_ candidate: [String: Any]) -> Int? {
    candidate.dictionary("metadata")?.int("bucket")
  }

  private func candidateRendezvousMs(_ candidate: [String: Any]) -> Int64 {
    Int64(candidate.dictionary("metadata")?.int("rendezvousTimeSeconds") ?? 0) * 1_000
  }

  private func candidateHost(_ candidate: [String: Any]) -> String {
    if let host = candidate.string("host"), !host.isEmpty { return host }
    if let address = candidate.string("address"), !address.isEmpty { return address }
    return hostFromCandidateUrl(candidate.string("url") ?? "")
  }

  private func clientAddressEvidence(_ candidate: [String: Any]) -> String {
    if let host = candidate.string("host"), !host.isEmpty { return "explicit-host" }
    if let address = candidate.string("address"), !address.isEmpty { return "signal-observed" }
    if let url = candidate.string("url"), !url.isEmpty { return "candidate-url" }
    return "port-only"
  }

  private func hostFromCandidateUrl(_ value: String) -> String {
    guard !value.isEmpty else { return "" }
    return URL(string: value.replacingOccurrences(of: "tcp-punch://", with: "http://"))?.host ?? ""
  }

  private func headersToJson(_ headers: [String: Any]) -> [[String]] {
    headers.map { key, value in [key, String(describing: value)] }
  }

  private func decodeBody(_ frame: [String: Any]) -> String {
    guard let encoded = frame.string("bodyBase64"),
          let data = Data(base64Encoded: encoded) else {
      return ""
    }
    return String(data: data, encoding: .utf8) ?? ""
  }

  private func event(type: String, localPort: Int, remotePort: Int, message: String?) -> [String: Any] {
    var value: [String: Any] = [
      "type": type,
      "localPort": localPort,
      "remotePort": remotePort,
    ]
    if let message { value["message"] = message }
    return value
  }

  private func logResult(_ result: [String: Any]) {
    NSLog("XpodP2PSmoke %@%@", resultMarker, verifierEvidenceJson(result))
  }

  private func verifierEvidenceJson(_ result: [String: Any]) -> String {
    var evidence: [String: Any] = [
      "smokeOk": result["smokeOk"] as? Bool ?? false,
      "route": result["route"] as? [String: Any] ?? ["kind": "unknown"],
      "connectorEvents": successConnectorEvents(result["connectorEvents"] as? [[String: Any]] ?? []),
    ]
    copyOptional(result, to: &evidence, key: "stage")
    copyOptional(result, to: &evidence, key: "clientId")
    copyOptional(result, to: &evidence, key: "nodeId")
    copyOptional(result, to: &evidence, key: "sessionId")
    copyOptional(result, to: &evidence, key: "clientAddress")
    copyOptional(result, to: &evidence, key: "error")
    copyOptional(result, to: &evidence, key: "status")
    copyOptional(result, to: &evidence, key: "putStatus")

    guard JSONSerialization.isValidJSONObject(evidence),
          let data = try? JSONSerialization.data(withJSONObject: evidence, options: []),
          let json = String(data: data, encoding: .utf8) else {
      NSLog("XpodP2PSmoke could not encode RESULT_JSON")
      return #"{"smokeOk":false,"route":{"kind":"unknown"},"connectorEvents":[],"error":"Could not encode RESULT_JSON"}"#
    }
    return json
  }

  private func successConnectorEvents(_ events: [[String: Any]]) -> [[String: Any]] {
    events.filter { $0["type"] as? String == "success" }
  }

  private func copyOptional(_ source: [String: Any], to target: inout [String: Any], key: String) {
    if let value = source[key] {
      target[key] = value
    }
  }

  private func writeLine(_ line: String, fd: Int32, timeoutMs: Int) throws {
    let bytes = Array((line + "\n").utf8)
    var offset = 0
    while offset < bytes.count {
      let written = bytes.withUnsafeBytes { buffer in
        Darwin.send(fd, buffer.baseAddress!.advanced(by: offset), bytes.count - offset, 0)
      }
      guard written > 0 else {
        throw SmokeError("P2P socket write failed: \(String(cString: strerror(errno)))")
      }
      offset += written
    }
  }

  private func readLine(fd: Int32, timeoutMs: Int) throws -> String {
    let deadline = Date().timeIntervalSince1970 + Double(timeoutMs) / 1_000.0
    var bytes: [UInt8] = []
    while Date().timeIntervalSince1970 <= deadline {
      var byte: UInt8 = 0
      let count = Darwin.recv(fd, &byte, 1, 0)
      if count == 1 {
        if byte == 10 { return String(decoding: bytes, as: UTF8.self) }
        bytes.append(byte)
      } else if count == 0 {
        throw SmokeError("P2P socket closed before response")
      } else if errno != EAGAIN && errno != EWOULDBLOCK {
        throw SmokeError("P2P socket read failed: \(String(cString: strerror(errno)))")
      }
    }
    throw SmokeError("P2P socket read timed out after \(timeoutMs)ms")
  }

  private func withSockaddr<T>(_ addr: inout sockaddr_in, _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> T) throws -> T {
    try withUnsafePointer(to: &addr) { pointer in
      try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { sockaddrPointer in
        try body(sockaddrPointer, socklen_t(MemoryLayout<sockaddr_in>.size))
      }
    }
  }
}

private struct SmokeError: LocalizedError {
  let message: String

  init(_ message: String) {
    self.message = message
  }

  var errorDescription: String? { message }
}

private extension NSDictionary {
  func requireString(_ key: String) throws -> String {
    guard let value = self[key] as? String, !value.isEmpty else {
      throw SmokeError("\(key) is required")
    }
    return value
  }

  func optionalString(_ key: String) -> String? {
    self[key] as? String
  }

  func optionalArray(_ key: String) -> [[String: Any]] {
    self[key] as? [[String: Any]] ?? []
  }

  func optionalDictionary(_ key: String) -> [String: Any] {
    self[key] as? [String: Any] ?? [:]
  }

  func optionalInt(_ key: String, fallback: Int) -> Int {
    if let value = self[key] as? NSNumber { return value.intValue }
    if let value = self[key] as? Int { return value }
    return fallback
  }
}

private extension Dictionary where Key == String, Value == Any {
  func string(_ key: String) -> String? {
    if let value = self[key] as? String { return value }
    if let value = self[key] as? NSNumber { return value.stringValue }
    return nil
  }

  func requireString(_ key: String) throws -> String {
    guard let value = string(key), !value.isEmpty else {
      throw SmokeError("\(key) is required")
    }
    return value
  }

  func int(_ key: String) -> Int? {
    if let value = self[key] as? Int { return value }
    if let value = self[key] as? NSNumber { return value.intValue }
    if let value = self[key] as? String { return Int(value) }
    return nil
  }

  func requireInt(_ key: String) throws -> Int {
    guard let value = int(key) else {
      throw SmokeError("\(key) is required")
    }
    return value
  }

  func dictionary(_ key: String) -> [String: Any]? {
    self[key] as? [String: Any]
  }

  func array(_ key: String) -> [[String: Any]] {
    self[key] as? [[String: Any]] ?? []
  }
}

private func fdZero(_ set: inout fd_set) {
  set.fds_bits = (0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0)
}

private let darwinNfdBits = MemoryLayout<Int32>.size * 8

private func fdSet(_ fd: Int32, set: inout fd_set) {
  let intOffset = Int(fd) / darwinNfdBits
  let bitOffset = Int(fd) % darwinNfdBits
  let mask = Int32(1 << bitOffset)
  switch intOffset {
  case 0: set.fds_bits.0 |= mask
  case 1: set.fds_bits.1 |= mask
  case 2: set.fds_bits.2 |= mask
  case 3: set.fds_bits.3 |= mask
  case 4: set.fds_bits.4 |= mask
  case 5: set.fds_bits.5 |= mask
  case 6: set.fds_bits.6 |= mask
  case 7: set.fds_bits.7 |= mask
  case 8: set.fds_bits.8 |= mask
  case 9: set.fds_bits.9 |= mask
  case 10: set.fds_bits.10 |= mask
  case 11: set.fds_bits.11 |= mask
  case 12: set.fds_bits.12 |= mask
  case 13: set.fds_bits.13 |= mask
  case 14: set.fds_bits.14 |= mask
  case 15: set.fds_bits.15 |= mask
  case 16: set.fds_bits.16 |= mask
  case 17: set.fds_bits.17 |= mask
  case 18: set.fds_bits.18 |= mask
  case 19: set.fds_bits.19 |= mask
  case 20: set.fds_bits.20 |= mask
  case 21: set.fds_bits.21 |= mask
  case 22: set.fds_bits.22 |= mask
  case 23: set.fds_bits.23 |= mask
  case 24: set.fds_bits.24 |= mask
  case 25: set.fds_bits.25 |= mask
  case 26: set.fds_bits.26 |= mask
  case 27: set.fds_bits.27 |= mask
  case 28: set.fds_bits.28 |= mask
  case 29: set.fds_bits.29 |= mask
  case 30: set.fds_bits.30 |= mask
  case 31: set.fds_bits.31 |= mask
  default: break
  }
}
