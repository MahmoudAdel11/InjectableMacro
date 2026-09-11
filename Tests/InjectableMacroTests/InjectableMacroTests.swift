import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros
import SwiftSyntaxMacrosTestSupport
import XCTest

// Macro implementations build for the host, so the corresponding module is not available when cross-compiling. Cross-compiled tests may still make use of the macro itself in end-to-end tests.
#if canImport(InjectableMacroMacros)
import InjectableMacroMacros

let injectableMacros: [String: Macro.Type] = [
    "Injectable": InjectableMacro.self,
]
#endif

final class InjectableMacroTests: XCTestCase {
    func testInjectableBasicStoredProperties() throws {
        #if canImport(InjectableMacroMacros)
        assertMacroExpansion(
            """
            @Injectable
            class TripBookingViewModel {
                let repository: String
                let geocoder: String
            }
            """,
            expandedSource: """
            class TripBookingViewModel {
                let repository: String
                let geocoder: String

                init(repository: String, geocoder: String) {
                    self.repository = repository
                    self.geocoder = geocoder
                }
            }
            """,
            macros: injectableMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testInjectableExcludesComputedProperty() throws {
        #if canImport(InjectableMacroMacros)
        assertMacroExpansion(
            """
            @Injectable
            class Placeholder {
                let id: String
                var label: String {
                    "x"
                }
            }
            """,
            expandedSource: """
            class Placeholder {
                let id: String
                var label: String {
                    "x"
                }

                init(id: String) {
                    self.id = id
                }
            }
            """,
            macros: injectableMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testInjectableIncludesDidSetProperty() throws {
        #if canImport(InjectableMacroMacros)
        assertMacroExpansion(
            """
            @Injectable
            class Placeholder {
                let id: String
                var count: Int {
                    didSet {
                        print(count)
                    }
                }
            }
            """,
            expandedSource: """
            class Placeholder {
                let id: String
                var count: Int {
                    didSet {
                        print(count)
                    }
                }

                init(id: String, count: Int) {
                    self.id = id
                    self.count = count
                }
            }
            """,
            macros: injectableMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testInjectableVarWithDefaultValue() throws {
        #if canImport(InjectableMacroMacros)
        assertMacroExpansion(
            """
            @Injectable
            class Placeholder {
                let id: String
                var retryCount: Int = 0
            }
            """,
            expandedSource: """
<<<<<<< Updated upstream
            class Placeholder {
                let id: String
                var retryCount: Int = 0

                init(id: String, retryCount: Int = 0) {
                    self.id = id
                    self.retryCount = retryCount
                }
            }
=======
            PLACEHOLDER
>>>>>>> Stashed changes
            """,
            macros: injectableMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testInjectableLetWithDefaultIsExcluded() throws {
        #if canImport(InjectableMacroMacros)
        assertMacroExpansion(
            """
            @Injectable
            class Placeholder {
                let id: String
                let retryLimit: Int = 3
            }
            """,
            expandedSource: """
<<<<<<< Updated upstream
            class Placeholder {
                let id: String
                let retryLimit: Int = 3

                init(id: String) {
                    self.id = id
                }
            }
=======
            PLACEHOLDER
>>>>>>> Stashed changes
            """,
            macros: injectableMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testInjectableOptionalGetsImplicitNil() throws {
        #if canImport(InjectableMacroMacros)
        assertMacroExpansion(
            """
            @Injectable
            class Placeholder {
                let id: String
                let backupContact: String?
            }
            """,
            expandedSource: """
<<<<<<< Updated upstream
            class Placeholder {
                let id: String
                let backupContact: String?

                init(id: String, backupContact: String? = nil) {
                    self.id = id
                    self.backupContact = backupContact
                }
            }
            """,
            macros: injectableMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testInjectableEmitsErrorOnNonClass() throws {
        #if canImport(InjectableMacroMacros)
        assertMacroExpansion(
            """
            @Injectable
            struct BadUsage {
                let x: Int
            }
            """,
            expandedSource: """
            struct BadUsage {
                let x: Int
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Injectable can only be attached to a class",
                    line: 1,
                    column: 1,
                    severity: .error
                )
            ],
            macros: injectableMacros
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }

    func testInjectableEmitsWarningOnEmptyClass() throws {
        #if canImport(InjectableMacroMacros)
        assertMacroExpansion(
            """
            @Injectable
            class EmptyViewModel {
            }
            """,
            expandedSource: """
            class EmptyViewModel {
            }
            """,
            diagnostics: [
                DiagnosticSpec(
                    message: "@Injectable found no stored properties to generate an initializer for",
                    line: 1,
                    column: 1,
                    severity: .warning
                )
            ],
            macros: injectableMacros
=======
            PLACEHOLDER
            """,
            macros: injectableMacros
>>>>>>> Stashed changes
        )
        #else
        throw XCTSkip("macros are only supported when running tests for the host platform")
        #endif
    }
}
