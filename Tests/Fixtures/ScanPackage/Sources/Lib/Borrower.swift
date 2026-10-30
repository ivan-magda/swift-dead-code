/// Uses Helper's `shouted` without importing Helper: it borrows Greeter.swift's import.
func borrowedShout() -> String {
  "borrowed".shouted
}

public let borrowedValue = borrowedShout()
