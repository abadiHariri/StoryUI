import XCTest
import SwiftUI
@testable import StoryUI

final class ProbeBox: ObservableObject {
    @Published var scale: CGFloat = 1
    @Published var offsetY: CGFloat = 0
    var samples: [String: (global: CGFloat, named: CGFloat, width: CGFloat)] = [:]
    func record(_ id: String, _ g: CGFloat, _ n: CGFloat, _ w: CGFloat) {
        samples[id] = (g, n, w)
    }
    func dump(_ label: String) -> String {
        samples.keys.sorted().map { k in
            let s = samples[k]!
            return String(format: "%@ page=%@ global.minX=%.2f named.minX=%.2f width=%.2f", label, k, s.global, s.named, s.width)
        }.joined(separator: "\n")
    }
}

struct ProbePage: View {
    let id: String
    let box: ProbeBox
    var body: some View {
        GeometryReader { proxy in
            let g = proxy.frame(in: .global).minX
            let n = proxy.frame(in: .named("pagerSpace")).minX
            let w = proxy.size.width
            let _ = box.record(id, g, n, w)
            Color.gray
        }
    }
}

struct ProbeRoot: View {
    @ObservedObject var box: ProbeBox
    @State private var selection: String = "a"
    var body: some View {
        ZStack {
            Color.black
            ZStack {
                Color.black
                TabView(selection: $selection) {
                    ForEach(["a", "b", "c"], id: \.self) { id in
                        ProbePage(id: id, box: box)
                    }
                }
                .coordinateSpace(name: "pagerSpace")
            }
            .scaleEffect(box.scale)
            .offset(y: box.offsetY)
        }
        .ignoresSafeArea()
        .tabViewStyle(.page(indexDisplayMode: .never))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

final class ZZCoordSpaceProbeTests: XCTestCase {

    func testNamedCoordinateSpaceCrossesPagingCells() {
        let box = ProbeBox()
        let host = UIHostingController(rootView: ProbeRoot(box: box))
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = host
        window.makeKeyAndVisible()
        host.view.frame = window.bounds
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        spin(2.0)
        print("PROBE-A ==== identity transform ====")
        print(box.dump("identity"))

        box.scale = 0.8
        box.offsetY = -120
        host.view.setNeedsLayout()
        host.view.layoutIfNeeded()
        spin(2.0)
        print("PROBE-B ==== scale 0.8 offset -120 ====")
        print(box.dump("scaled"))
    }

    private func spin(_ seconds: TimeInterval) {
        let exp = expectation(description: "spin")
        DispatchQueue.main.asyncAfter(deadline: .now() + seconds) { exp.fulfill() }
        wait(for: [exp], timeout: seconds + 5)
    }
}
