import Foundation
import SwiftCompilerPlugin
import SwiftDiagnostics
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct InjectableMacro: MemberMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        guard let classDecl = declaration.as(ClassDeclSyntax.self) else {
            return []
        }

        var storedProperties: [(name: String, type: String)] = []

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
                storedProperties.append((name: identifierPattern.identifier.text, type: typeAnnotation.description.trimmingCharacters(in: .whitespacesAndNewlines)))
            }
        }

        guard !storedProperties.isEmpty else {
            return []
        }

        let parameterList = storedProperties
            .map { "\($0.name): \($0.type)" }
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
