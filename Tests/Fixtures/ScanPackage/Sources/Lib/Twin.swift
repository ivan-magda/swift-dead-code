import Helper

/// Compiles without its import because Greeter.swift imports Helper for the target.
func twinShout() -> String {
  "twin".shouted
}

public let twinValue = twinShout()
