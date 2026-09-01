import XCTest
import SwiftUI
@testable import StoryUI

final class ProbeBox2: ObservableObject {
    @Published var scale: CGFloat = 1
    @Published var offsetY: CGFloat = 0
    var samples: [String: [String: CGFloat]] = [:]
    func record(_ id: String, _ v: [String: CGFloat]) { samples[id] = v }
    func dump(_ label: String) -> String {
        samples.keys.sorted().map { k in
            let s = samples[k]!
            let body = s.keys.sorted().map { String(format: "%@=%.2f", $0, s[$0]!) }.joined(separator: " ")
            return "\(label) [\(k)] \(body)"
        }.joined(separator: "\n")
    }
}

struct Probe2Measure: View {
    let id: String
    let box: ProbeBox2
    var body: some View {
        GeometryReader { proxy in
            let _ = box.record(id, [
                "global.minX": proxy.frame(in: .global).minX,
                "named.minX": proxy.frame(in: .named("pagerSpace")).minX,
                "bogus.minX": proxy.frame(in: .named("noSuchSpaceAtAll")).minX,
                "local.minX": proxy.frame(in: .local).minX,
                "global.minY": proxy.frame(in: .global).minY,
                "named.minY": proxy.frame(in: .named("pagerSpace")).minY,
                "width": proxy.size.width
            ])
            Color.gray
        }
    }
}

struct Probe2Root: View {
    @ObservedObject var box: ProbeBox2
    @State private var selection: String = "a"
    var body: some View {
        ZStack {
            Color.black
            ZStack {
                Color.black
                TabView(selection: $selection) {
                    ForEach(["a", "b"], id: \.self) { id in
                        Probe2Measure(id: "inTab-\(id)", box: box)
                    }
                }
                // sibling of the TabView, direct descendant of the named container
                Probe2Measure(id: "sibling", box: box)
                    .frame(width: 100, height: 100)
            }
            .coordinateSpace(name: "pagerSpace")   // named container wraps BOTH
            .scaleEffect(box.scale)
            .offset(y: box.offsetY)
        }
        .ignoresSafeArea()
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

final class ZZCoordSpaceProbe2Tests: XCTestCase {
    func testNamedSpaceInsideVsOutsideTabView() {
        let box = ProbeBox2()
        let host = UIHostingController(rootView: Probe2Root(box: box))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.layoutIfNeeded()
        spin(2.0)
        print("PROBE2-A ==== identity ====")
        print(box.dump("identity"))
        box.scale = 0.8
        box.offsetY = -120
        host.view.layoutIfNeeded()
        spin(2.0)
        print("PROBE2-B ==== scale 0.8 offset -120 ====")
        print(box.dump("scaled"))
    }

    private func spin(_ seconds: TimeInterval) {
        let exp = expectation(description: "spin")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 5)
    }
}
