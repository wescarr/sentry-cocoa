import Foundation
import SentryObjc
import SwiftUI

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6.0, *)
public struct SentryPerformanceView<Content: View>: View {
    
    let content : () -> Content
    let name: String
    let id: SpanId
    
    public init(_ name: String? = nil, content : @escaping () -> Content) {
        self.content = content
        self.name = name ?? String(describing: Content.self)
        id = SentryPerformanceTracker.shared.startSpan(withName: self.name,
                                                       nameSource: name == nil ? .component : .custom,
                                                       operation: "ui")
    }
    
    static func extractName(content: Any) -> String {
        var result = String(describing: type(of: content))
        
        if let index = result.firstIndex(of: "<") {
            result = String(result[result.startIndex ..< index])
        }
        
        return result
    }
    
    public var body: some View {
        SentryPerformanceTracker.shared.pushActiveSpan(id)
        
        let result = self.content().onAppear {
            SentryPerformanceTracker.shared.finishSpan(id)
        }
        
        SentryPerformanceTracker.shared.popActiveSpan()
        return result
    }
}

@available(iOS 13, macOS 10.15, tvOS 13, watchOS 6.0, *)
public extension View {
    func sentryTransaction(_ transactionName: String? = nil) -> some View {
        return SentryPerformanceView (transactionName) {
            return self
        }
    }
}