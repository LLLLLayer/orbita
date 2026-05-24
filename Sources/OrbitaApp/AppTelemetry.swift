import OSLog

enum OrbitaTelemetry {
    static let subsystem = "dev.orbita.app"

    static let app = Logger(subsystem: subsystem, category: "App")
    static let scan = Logger(subsystem: subsystem, category: "Scan")
    static let apply = Logger(subsystem: subsystem, category: "Apply")
}
