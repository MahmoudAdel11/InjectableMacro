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

                guard
                    let identifierPattern = binding.pattern.as(IdentifierPatternSyntax.self),
                    let typeAnnotation = binding.typeAnnotation?.type
                else {
                    continue
                }

                // `typeAnnotation.description` renders the TypeSyntax node back to raw source text
                // including its trivia, so for `let repository: String` it comes back as " String"
                // (leading space from before the type). Trimming removes that so the extracted
                // type name is a clean "String" instead of " String".
                let trimmedType = typeAnnotation.description.trimmingCharacters(in: .whitespacesAndNewlines)
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

                // An Optional property with no explicit default value gets an implicit
                // "nil" default, matching Swift's own memberwise-init convention for structs.
                var defaultValue = explicitDefaultValue
                if defaultValue == nil && trimmedType.hasSuffix("?") {
                    defaultValue = "nil"
                }

                storedProperties.append((
                    name: identifierPattern.identifier.text,
                    type: trimmedType,
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

        let initializer: DeclSyntax = """
            init(\(raw: parameterList)) {
                \(raw: assignmentBody)
            }
            """

        return [initializer]
    }
}

@main
struct InjectableMacroPlugin: CompilerPlugin {
    let providingMacros: [Macro.Type] = [
        InjectableMacro.self,
    ]
}
