import os

/// Unified-log diagnostics (Console.app / `log stream`). No user content is
/// logged beyond app names and outcome summaries.
enum Diag {
    static let log = Logger(subsystem: "io.github.neuralfoundry-coder.AutoAlignPanels", category: "align")
}
