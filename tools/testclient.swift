import Foundation
import Network

// Test client: reproduces the crash condition by sending many frames
// coalesced in each send (several messages in the same receive buffer).

let serviceType = "_mytrackpad._tcp"

func frame(_ json: [String: Any]) -> Data {
    let payload = try! JSONSerialization.data(withJSONObject: json)
    let len = UInt32(payload.count)
    var d = Data()
    d.append(UInt8((len >> 24) & 0xFF))
    d.append(UInt8((len >> 16) & 0xFF))
    d.append(UInt8((len >> 8) & 0xFF))
    d.append(UInt8(len & 0xFF))
    d.append(payload)
    return d
}

var connected = false
let browser = NWBrowser(for: .bonjour(type: serviceType, domain: nil), using: NWParameters())

func connect(to endpoint: NWEndpoint) {
    let conn = NWConnection(to: endpoint, using: .tcp)
    conn.stateUpdateHandler = { state in
        switch state {
        case .ready:
            print("connected; sending bursts…")
            conn.send(content: frame(["kind": "hello", "name": "TestClient"]),
                      completion: .contentProcessed { _ in })
            var total = 0
            for _ in 0..<300 {
                var batch = Data()
                for i in 0..<25 {
                    batch.append(frame(["kind": "move", "dx": Double(i) * 0.5, "dy": -Double(i) * 0.3]))
                    batch.append(frame(["kind": "scroll", "dx": 1.0, "dy": 2.0]))
                    if i % 5 == 0 { batch.append(frame(["kind": "media", "media": "volUp"])) }
                    if i % 7 == 0 { batch.append(frame(["kind": "text", "text": "hello world"])) }
                    if i % 3 == 0 { batch.append(frame(["kind": "key", "key": "right"])) }
                    total += 1
                }
                conn.send(content: batch, completion: .contentProcessed { _ in })
            }
            print("sent \(total) burst iterations")
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                conn.cancel()
                print("DONE")
                exit(0)
            }
        case .failed(let e):
            print("connection failed: \(e)")
            exit(2)
        default:
            break
        }
    }
    conn.start(queue: .main)
}

browser.browseResultsChangedHandler = { results, _ in
    guard !connected, let first = results.first else { return }
    connected = true
    print("found: \(first.endpoint)")
    connect(to: first.endpoint)
}
browser.start(queue: .main)

DispatchQueue.main.asyncAfter(deadline: .now() + 10) {
    print("timeout: server not found")
    exit(3)
}
RunLoop.main.run()
