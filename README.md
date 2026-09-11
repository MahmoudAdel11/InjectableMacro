# InjectableMacro

A Swift macro that generates a memberwise initializer for a class's stored properties, so you don't have to write one by hand.

## The Problem

Unlike structs, classes don't get a free memberwise initializer from the compiler. As a class grows, you end up hand-writing (and hand-maintaining) an `init` like this:

```swift
class TripBookingViewModel {
    let repository: String
    let geocoder: String

    init(repository: String, geocoder: String) {
        self.repository = repository
        self.geocoder = geocoder
    }
}
```

Every time a property is added, removed, or renamed, this `init` has to be updated by hand to match — it's pure boilerplate that just restates information already declared above it.

## The Solution

With `@Injectable` attached to the class, you only declare the properties. The initializer above is generated for you:

```swift
@Injectable
class TripBookingViewModel {
    let repository: String
    let geocoder: String
}
```

This expands, at compile time, into exactly the same class with the initializer added as a real member:

```swift
class TripBookingViewModel {
    let repository: String
    let geocoder: String

    init(repository: String, geocoder: String) {
        self.repository = repository
        self.geocoder = geocoder
    }
}
```

This is a **compile-time source transformation**, not runtime reflection or `Mirror`-based introspection. The generated `init` is ordinary Swift source that exists in the compiled binary like any code you'd have typed yourself — there's no runtime cost, and you can inspect the expansion directly in Xcode.

## How It Works

`@Injectable` is implemented as a Swift `MemberMacro`. At compile time, for each class it's attached to, it:

1. Parses the class's declaration as a SwiftSyntax tree and walks its members.
2. Identifies which properties are *stored* (as opposed to computed) by inspecting each property's accessors.
3. Extracts each stored property's name, type, and default value (if any) from the syntax tree.
4. Uses SwiftSyntaxBuilder to synthesize a new `init` declaration from that information and adds it as a member of the class.

No part of this happens at runtime — the macro only runs while the compiler is parsing your code, and by the time you build and run the app, the generated `init` is just a normal initializer.

## Supported Behavior / Edge Cases

| Property shape | Behavior | Why |
|---|---|---|
| Plain stored property (`let`/`var`, no default) | Required parameter | Nothing to default it to |
| Computed property (`var x: T { ... }`, get-only) | **Excluded** from the init entirely | It has no storage to initialize |
| Stored property with `didSet`/`willSet` only | **Included** as a normal parameter | These observers don't make a property computed — it's still backed by storage |
| `let` with an explicit default value | **Excluded** from both the parameter list and the assignment body | A `let` with a default is already initialized at declaration; Swift doesn't allow assigning it again in `init` |
| `var` with an explicit default value | Included as an **optional parameter**, defaulting to that value | Mirrors the property's own default, so callers can opt in to override it |
| Optional-typed property (`T?`) with no explicit default | Included as an optional parameter, defaulting to `= nil` | Matches Swift's own memberwise-init convention for structs |
| `@Injectable` attached to something other than a `class` | Emits a compiler **error**: `"@Injectable can only be attached to a class"` | The macro only knows how to inspect class members |
| `@Injectable` attached to a class with no stored properties | Emits a compiler **warning**: `"@Injectable found no stored properties to generate an initializer for"`, generates nothing | There's nothing to build an initializer from, and a useless empty `init` would be worse than no `init` |

## A Complete Example

This single class exercises every behavior from the table above at once:

```swift
@Injectable
class Config {
    let apiKey: String
    let timeout: Int = 30
    var retryCount: Int = 3
    var lastError: String? = nil {
        didSet { print("error changed") }
    }
    let backupContact: String?
    var displayName: String {
        "Config: \(apiKey)"
    }
}
```

This expands to (verified via `-dump-macro-expansions` against the actual macro):

```swift
init(apiKey: String, retryCount: Int = 3, lastError: String? = nil, backupContact: String? = nil) {
    self.apiKey = apiKey
    self.retryCount = retryCount
    self.lastError = lastError
    self.backupContact = backupContact
}
```

- `apiKey` — plain stored property, no default → required parameter.
- `timeout` — `let` + default value, excluded from the init entirely.
- `retryCount` — `var` + default value, included as an optional parameter defaulting to `3`.
- `lastError` — stored property with `didSet` (not excluded by the observer); its `= nil` in the generated init comes from the **explicit default the developer wrote** in the source (`var lastError: String? = nil`), which the macro simply carries over — it happens to be `nil`, but the macro doesn't know or care that it's Optional here, only that a default was written.
- `backupContact` — declared with **no default at all** (`let backupContact: String?`); its `= nil` in the generated init is **synthesized by the macro itself**, purely because the property's type is Optional — a different mechanism from `lastError`'s that happens to produce the same visible `= nil`.
- `displayName` — computed property (get-only), excluded from the init entirely.

## Running the Tests

```bash
swift test
```

This runs 8 tests, each using SwiftSyntaxMacros' `assertMacroExpansion` to expand a small class definition and assert on the exact generated source (or the exact diagnostic emitted), covering every behavior listed above: basic stored-property extraction, computed-property exclusion, `didSet` handling, `var`-with-default, `let`-with-default exclusion, optional-with-implicit-nil, the non-class error, and the empty-class warning.

## What I Learned

- Swift macros operate purely on syntax, not on type information — a `MemberMacro` only ever sees a `SwiftSyntax` tree, so distinguishing "stored" from "computed" properties means inspecting accessor blocks yourself rather than asking a type-checker.
- `assertMacroExpansion` does an exact string comparison against the expanded source, whitespace and all — I learned not to guess the expected string by hand, but to run the test with a placeholder first and take the actual output from the failure diff as ground truth.
- Getting a `let` property with a default value wrong taught me a real Swift semantics lesson, not just a macro one: a `let` is only allowed to be assigned once, so a naively-generated `init` that always assigns every property will fail to compile for that specific case — the macro has to special-case it.
- Diagnostics (`context.diagnose`) are how a macro communicates failure to the *caller* of the macro, at their call site — very different from throwing inside the macro implementation, which surfaces as a much less useful generic error.
- The macro attribute declaration (`@attached(member, names: arbitrary)`) has to declare upfront what kinds of names it might introduce; the compiler enforces this before the macro even runs, which was a good reminder that macros have to declare their "contract" outside of just their implementation code.
- Writing tests for a macro forced me to think about the macro's behavior as a specification (one test per behavior/edge case) rather than just eyeballing generated code in a sample app.
