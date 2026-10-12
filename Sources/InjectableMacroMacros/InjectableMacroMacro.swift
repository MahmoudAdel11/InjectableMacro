import Foundation
import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

struct InjectableDiagnosticMessage: DiagnosticMessage {
    let message: String
    let diagnosticID: MessageID
    let severity: DiagnosticSeverity
}

public struct InjectableMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: InjectableDiagnosticMessage(
                        message: "@Injectable can only be attached to a class",
                        diagnosticID: MessageID(domain: "InjectableMacro", id: "onlyClass"),
                        severity: .error
                    )
                )
            )
            return []
        }

        var storedProperties: [(name: String, type: String, defaultValue: String?)] = []

        for member in classDecl.memberBlock.members {
            guard let variableDecl = member.decl.as(VariableDeclSyntax.self) else {
                continue
            }

            // `static`/`class` members are type-level state, not instance state, and `lazy`
            // members are computed on first access, so none of them belong in the init.
            let isExcludedByModifier = variableDecl.modifiers.contains { modifier in
                modifier.name.tokenKind == .keyword(.static)
                    || modifier.name.tokenKind == .keyword(.class)
                    || modifier.name.tokenKind == .keyword(.lazy)
            }
            if isExcludedByModifier {
                continue
            }

            let stateAttribute = variableDecl.attributes.lazy
                .compactMap { $0.as(AttributeSyntax.self) }
                .first { $0.attributeName.as(IdentifierTypeSyntax.self)?.name.text == "State" }

            for binding in variableDecl.bindings {
                let isStored: Bool
                if let accessorBlock = binding.accessorBlock {
                    switch accessorBlock.accessors {
                    case .accessors(let accessors):
                        isStored = accessors.allSatisfy { accessor in
                            accessor.accessorSpecifier.tokenKind == .keyword(.didSet)
                                || accessor.accessorSpecifier.tokenKind == .keyword(.willSet)
                        }
                    case .getter:
                        isStored = false
                    }
                } else {
                    isStored = true
                }

                guard isStored else { continue }

                guard let identifierPattern = binding.pattern.as(IdentifierPatternSyntax.self) else {
                    continue
                }

                let explicitDefaultValue = binding.initializer?.value.description.trimmingCharacters(in: .whitespacesAndNewlines)

                // A `let` property with an EXPLICIT default value is already fully initialized
                // at declaration, so it can't also be assigned in the generated init body
                // (Swift only allows a `let` to be set once). Exclude it entirely. This check
                // must use the explicit initializer only, before the optional/"nil" fallback
                // below, since a `let` optional with no initializer (e.g. `let x: String?`)
                // is NOT yet initialized and must still be included.
                let isLet = variableDecl.bindingSpecifier.tokenKind == .keyword(.let)
                if isLet && explicitDefaultValue != nil {
                    continue
                }

                // Macros only see syntax, so a property without a written type (e.g.
                // `var retryCount = 0`) can't become an init parameter. Reject it loudly rather
                // than silently leaving it out of the init.
                guard let typeAnnotation = binding.typeAnnotation?.type else {
                    context.diagnose(
                        Diagnostic(
                            node: Syntax(binding.pattern),
                            message: InjectableDiagnosticMessage(
                                message: "@Injectable requires an explicit type annotation (e.g. `var retryCount: Int = 0`)",
                                diagnosticID: MessageID(domain: "InjectableMacro", id: "missingTypeAnnotation"),
                                severity: .error
                            )
                        )
                    )
                    continue
                }

                // `typeAnnotation.description` renders the TypeSyntax node back to raw source text
                // including its trivia, so for `let repository: String` it comes back as " String"
                // (leading space from before the type). Trimming removes that so the extracted
                // type name is a clean "String" instead of " String".
                let trimmedType = typeAnnotation.description.trimmingCharacters(in: .whitespacesAndNewlines)

                // An Optional property with no explicit default value gets an implicit
                // "nil" default, matching Swift's own memberwise-init convention for structs.
                var defaultValue = explicitDefaultValue
                if defaultValue == nil && trimmedType.hasSuffix("?") {
                    defaultValue = "nil"
                }

                // `@State` is still injected as before, but it only works inside SwiftUI Views
                // (structs), so flag it at the attribute itself rather than at `@Injectable`.
                if let stateAttribute {
                    context.diagnose(
                        Diagnostic(
                            node: Syntax(stateAttribute),
                            message: InjectableDiagnosticMessage(
                                message: "@State is meant for SwiftUI Views, not classes; consider @Published instead",
                                diagnosticID: MessageID(domain: "InjectableMacro", id: "stateInClass"),
                                severity: .warning
                            )
                        )
                    )
                }

                storedProperties.append((
                    name: identifierPattern.identifier.text,
                    type: parameterType(for: typeAnnotation),
                    defaultValue: defaultValue
                ))
            }
        }

        guard !storedProperties.isEmpty else {
            context.diagnose(
                Diagnostic(
                    node: Syntax(node),
                    message: InjectableDiagnosticMessage(
                        message: "@Injectable found no stored properties to generate an initializer for",
                        diagnosticID: MessageID(domain: "InjectableMacro", id: "noStoredProperties"),
                        severity: .warning
                    )
                )
            )
            return []
        }

        let parameterList = storedProperties
            .map { property -> String in
                if let defaultValue = property.defaultValue {
                    return "\(property.name): \(property.type) = \(defaultValue)"
                } else {
                    return "\(property.name): \(property.type)"
                }
            }
            .joined(separator: ", ")

        let assignmentBody = storedProperties
            .map { "self.\($0.name) = \($0.name)" }
            .joined(separator: "\n")

        // A memberwise init is only useful to callers who can see the class, so mirror the
        // class's access level. `open` maps to `public` because initializers can't be `open`.
        let accessPrefix: String
        if classDecl.modifiers.contains(where: {
            $0.name.tokenKind == .keyword(.public) || $0.name.tokenKind == .keyword(.open)
        }) {
            accessPrefix = "public "
        } else if classDecl.modifiers.contains(where: { $0.name.tokenKind == .keyword(.package) }) {
            accessPrefix = "package "
        } else {
            accessPrefix = ""
        }

        let initializer: DeclSyntax = """
            \(raw: accessPrefix)init(\(raw: parameterList)) {
                \(raw: assignmentBody)
            }
            """

        return [initializer]
    }

    /// The type to use for an init parameter that stores into a property of `type`.
    ///
    /// A stored closure outlives the init call, so a function-typed parameter must be
    /// `@escaping`. Optional closures are already escaping (and `@escaping` on them is a
    /// compile error), so only bare or attributed function types are marked. A typealias'd
    /// closure looks like any other named type in syntax, so it's left unchanged.
    private static func parameterType(for type: TypeSyntax) -> String {
        let unwrapped = removingRedundantParentheses(from: type)

        if unwrapped.is(FunctionTypeSyntax.self) {
            return "@escaping \(unwrapped.trimmedDescription)"
        }
        if let attributed = unwrapped.as(AttributedTypeSyntax.self),
           removingRedundantParentheses(from: attributed.baseType).is(FunctionTypeSyntax.self) {
            return "@escaping \(attributed.trimmedDescription)"
        }
        return type.trimmedDescription
    }

    /// Strips wrapping parentheses like `((Int) -> Void)`, which parse as a single-element
    /// tuple type, so the function type inside can be recognized.
    private static func removingRedundantParentheses(from type: TypeSyntax) -> TypeSyntax {
        var current = type
        while let tuple = current.as(TupleTypeSyntax.self),
              tuple.elements.count == 1,
              let element = tuple.elements.first,
              element.firstName == nil,
              element.ellipsis == nil {
            current = element.type
        }
        return current
    }
}

@main
struct InjectableMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        InjectableMacro.self,
    ]
}
