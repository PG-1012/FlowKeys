import OSLog

/// Diagnostics for the parts of FlowKeys that cannot be unit-tested: the
/// event tap and the synthetic paste both depend on system state and
/// Accessibility permission, so when they misbehave the only evidence is
/// what the app itself reports.
///
///     log stream --predicate 'subsystem == "com.pg1012.FlowKeys"' --level debug
///     log show --last 5m --predicate 'subsystem == "com.pg1012.FlowKeys"'
enum Log {
    static let tap = Logger(subsystem: "com.pg1012.FlowKeys", category: "eventtap")
    static let paste = Logger(subsystem: "com.pg1012.FlowKeys", category: "paste")
}
