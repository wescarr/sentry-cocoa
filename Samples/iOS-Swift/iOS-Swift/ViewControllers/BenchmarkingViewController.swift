import CryptoKit
import Sentry
import UIKit
import SwiftUI

class BenchmarkingViewController: UIViewController {
    enum Scenario: String {
        /// Compute a factorial.
        case cpu_100percent
        case cpu_idle

        /// Write a large amount of text to disk
        case fileIO_write

        /// Read a large file from disk
        case fileIO_read

        /// Compress a large amount of data
        case data_compress

        /// Encrypt a large amount of data
        case data_encrypt

        /// Compute the SHA sum of a large amount of data
        case data_shasum

        case data_json_serialize
        case data_json_deserialize

        /// Scroll a table view containing basic cells containing lorem ipsum text.
        case scrollTableView

        /// Render an image in a `UIImageView`.
        case renderImage

        /// Download a file from the Internet.
        case network_download
        case network_upload
        case network_stream_up
        case network_stream_down
        case network_stream_both

        /// Render a website in a view containing a `WKWebView`.
        case renderWebpageInWebKit

        case coreData_loadDB_Empty
        case coreData_loadDB_WithEntities

        case coreData_entity_create
        case coreData_entity_fetch
        case coreData_entity_update
        case coreData_entity_delete

        // TODO: more scenarios, basic components of apps, Apple framework (e.g. CoreImage, CoreLocation), etc

        var transactionName: String {
            "\(operation).\(rawValue)"
        }

        var operation: String {
            "io.sentry.ios-swift.benchmark"
        }
    }

    func actionInfo(for scenario: Scenario) -> (description: String, action: () -> Void) {
        switch scenario {
        case .fileIO_write: return ("File write", writeFile)
        case .fileIO_read: return ("File read", readFile)
        case .scrollTableView: return ("Scroll UITableView", scrollTableView)
        case .renderImage: return ("Render image", renderImage)
        case .network_download: return ("Network download", networkDownload)
        case .network_upload: return ("Network upload", networkUpload)
        case .network_stream_up: return ("Network stream up", networkStreamUp)
        case .network_stream_down: return ("Network stream down", networkStreamDown)
        case .network_stream_both: return ("Network stream mixed", networkStreamBoth)
        case .renderWebpageInWebKit: return ("WebKit render", webkitRender)
        case .coreData_loadDB_Empty: return ("Load empty DB", loadEmptyDB)
        case .coreData_loadDB_WithEntities: return ("Load DB with entities", loadDBWithEntities)
        case .coreData_entity_create: return ("Create entity", createEntity)
        case .coreData_entity_fetch: return ("Fetch entity", fetchEntity)
        case .coreData_entity_update: return ("Update entity", updateEntity)
        case .coreData_entity_delete: return ("Delete entity", deleteEntity)
        case .cpu_100percent: return ("CPU 100%", cpuIntensiveArithmetic)
        case .cpu_idle: return ("CPU idle", cpuIdle)
        case .data_compress: return ("Data compression", dataCompress)
        case .data_encrypt: return ("Data encrypt", dataEncrypt)
        case .data_shasum: return ("Data SHA1 sum", dataSHA)
        }
    }

    func sectionInfo(for scenario: Scenario) -> (index: NSInteger, name: String) {
        switch scenario {
        case .cpu_100percent, .cpu_idle: return (0, "CPU")
        case .fileIO_write, .fileIO_read: return (1, "File I/O")
        case .scrollTableView, .renderImage: return (2, "UI Events")
        case .network_download, .network_upload, .network_stream_up, .network_stream_down, .network_stream_both: return (3, "Networking")
        case .renderWebpageInWebKit: return (4, "WebKit")
        case .coreData_loadDB_Empty, .coreData_loadDB_WithEntities, .coreData_entity_create, .coreData_entity_fetch, .coreData_entity_update, .coreData_entity_delete: return (5, "CoreData")
        case .data_compress, .data_encrypt, .data_shasum: return (6, "Data")
        }
    }

    private lazy var valueTextField: UITextField = {
        let tf = UITextField(frame: .zero)
        tf.accessibilityLabel = "io.sentry.benchmark.value-marshaling-text-field"
        return tf
    }()
    private let imageView = UIImageView(frame: .zero)
    private lazy var scrollScenarioTableView: UITableView = {
        let tv = UITableView(frame: .zero, style: .plain)
        tv.register(UITableViewCell.self, forCellReuseIdentifier: "Cell")
        tv.translatesAutoresizingMaskIntoConstraints = false
        tv.dataSource = self
        return tv
    }()

    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: Bundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)

        let views = [ imageView, valueTextField]
        let stack = UIStackView(arrangedSubviews: views)
        stack.axis = .vertical
        (views + [stack]).forEach { $0.translatesAutoresizingMaskIntoConstraints = false }
        view.addSubview(stack)
        NSLayoutConstraint.activate([
            stack.centerYAnchor.constraint(equalTo: view.centerYAnchor),
            stack.centerXAnchor.constraint(equalTo: view.centerXAnchor),
        ])

        view.backgroundColor = .white
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    // refresh rate of 60 hz is 0.0167
    // 120 hz is 0.0083
    // 240 hz is 0.004167
    private let interval = 0.000_000_05
    private var timer: Timer?
    private let iterations = 5_000_000
    private let range = 1..<Double.greatestFiniteMagnitude

    private let session = URLSession(configuration: .default)

    var mobyDickURL: URL {
        Bundle.main.url(forResource: "mobydick", withExtension: "txt")!
    }

    var mobyDickString: String {
        try! String(contentsOf: mobyDickURL)
    }

    var mobyDickData: Data {
        try! Data(contentsOf: mobyDickURL)
    }
}

// MARK: CPU
private extension BenchmarkingViewController {
    func doWork(withNumber a: Double) -> Double {
        var b: Double
        if arc4random() % 2 == 0 {
            b = fmod(a, Double.random(in: range))
        } else {
            b = fmod(Double.random(in: range), a)
        }
        if b == 0 {
            b = Double.random(in: range)
        }
        return b
    }

    func orchestrateWork() {
        var a = doWork(withNumber: Double.random(in: range))
        for _ in 0..<iterations {
            a = doWork(withNumber: a)
        }
    }

    func cpuIntensiveArithmetic() {
        let span = SentrySDK.startTransaction(name: "io.sentry.benchmark.transaction", operation: "cpu-intensive-arithmetic")
        if #available(iOS 10.0, *) {
            timer = Timer.scheduledTimer(withTimeInterval: interval, repeats: true, block: { _ in
                self.orchestrateWork()
            })
        } else {
            fatalError("Only available on iOS 10 or later.")
        }
        SentryBenchmarking.startBenchmark()
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            self.stopTest(span: span) {
                self.timer?.invalidate()
            }
        }
    }

    func cpuIdle() {
        let span = SentrySDK.startTransaction(name: "io.sentry.benchmark.transaction", operation: "cpu-intensive-arithmetic")
        SentryBenchmarking.startBenchmark()
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            self.stopTest(span: span) {
                self.timer?.invalidate()
            }
        }
    }
}

// MARK: File I/O
private extension BenchmarkingViewController {
    func writeFile() {
        let s = mobyDickString // do this before starting the span, we don't want to profile/benchmark the file read
        inTransaction(for: .fileIO_write) {
            try! s.write(to: URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent("mobydickcopy.txt"), atomically: false, encoding: String.Encoding.utf8)
        }
    }

    func readFile() {
        inTransaction(for: .fileIO_read) {
            let _ = mobyDickString
        }
    }
}

// MARK: UI events
extension BenchmarkingViewController: UITableViewDataSource {
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "Cell", for: indexPath)
        cell.textLabel?.text = UUID().uuidString
        return cell
    }

    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return 10_000_000
    }

    func scrollTableView() {
        view.addSubview(scrollScenarioTableView)
        scrollScenarioTableView.pintToSuperviewEdges()
        let span = transaction(for: .scrollTableView)
        DispatchQueue.main.asyncAfter(deadline: .now() + 15) {
            self.stopTest(span: span) {
                self.scrollScenarioTableView.removeFromSuperview()
            }
        }
    }

    func renderImage() {
        inTransaction(for: .renderImage) {
            imageView.image = UIImage(imageLiteralResourceName: "Tongariro")
        }
    }
}

extension UIView {
    func pintToSuperviewEdges() {
        NSLayoutConstraint.activate([
            topAnchor.constraint(equalTo: superview!.topAnchor),
            bottomAnchor.constraint(equalTo: superview!.bottomAnchor),
            leadingAnchor.constraint(equalTo: superview!.leadingAnchor),
            trailingAnchor.constraint(equalTo: superview!.trailingAnchor)
        ])
    }
}

// MARK: Networking
private extension BenchmarkingViewController {
    func networkDownload() {
        let span = transaction(for: .network_download)
        let task = session.dataTask(with: URL(string: "https://www.gutenberg.org/files/2701/2701-0.txt")!) { data, response, error in
            span.finish()
        }
        task.resume()
    }

    func networkUpload() {

    }

    func networkStreamUp() {

    }

    func networkStreamDown() {

    }

    func networkStreamBoth() {

    }
}

// MARK: WebKit
private extension BenchmarkingViewController {
    func webkitRender() {

    }
}

// MARK: CoreData
private extension BenchmarkingViewController {
    func loadEmptyDB() {

    }

    func loadDBWithEntities() {

    }

    func createEntity() {

    }

    func fetchEntity() {

    }

    func updateEntity() {

    }

    func deleteEntity() {

    }
}

// MARK: Data
private extension BenchmarkingViewController {
    func dataCompress() {

    }

    func dataEncrypt() {
        let data = mobyDickData
        if #available(iOS 13.0, *) {
            let keyString = UUID().uuidString + ISO8601DateFormatter().string(from: Date())
            let key = SymmetricKey(data: Array(keyString.utf8))
            inTransaction(for: .data_encrypt) {
                let _ = try! CryptoKit.AES.GCM.seal(data, using: key)
            }
        } else {
            fatalError("Only available on iOS 13 or later.")
        }
    }

    func dataSHA() {
        let data = mobyDickData
        if #available(iOS 13.0, *) {
            inTransaction(for: .data_encrypt) {
                var hasher = SHA256()
                hasher.update(data: data)
                let _ = hasher.finalize()
            }
        } else {
            fatalError("Only available on iOS 13 or later.")
        }
    }
}

// MARK: Helpers
private extension BenchmarkingViewController {
    func transaction(for scenario: Scenario) -> Span {
        SentrySDK.startTransaction(name: scenario.transactionName, operation: scenario.operation)
    }

    func inTransaction(for scenario: Scenario, block: () -> Void) {
        let span = transaction(for: scenario)
        block()
        span.finish()
    }

    func stopTest(span: Span, cleanup: () -> Void) {
        defer {
            cleanup()
            span.finish()
        }

        guard let value = SentryBenchmarking.stopBenchmark() else {
            print("Only one CPU sample was taken, can't calculate benchmark deltas.")
            valueTextField.text = "nil"
            return
        }

        valueTextField.text = "\(value)"
    }
}
