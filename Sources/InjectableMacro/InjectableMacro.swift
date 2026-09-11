// The Swift Programming Language
// https://docs.swift.org/swift-book

@attached(member, names: arbitrary)
public macro Injectable() = #externalMacro(module: "InjectableMacroMacros", type: "InjectableMacro")
