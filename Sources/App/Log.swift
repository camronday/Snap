import os

/// Shared loggers, one subsystem per area of the app.
enum Log {
    static let app = Logger(subsystem: "com.cameronro.Snap", category: "app")
    static let capture = Logger(subsystem: "com.cameronro.Snap", category: "capture")
}
