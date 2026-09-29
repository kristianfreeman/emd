import Foundation
import SwiftParser
import SwiftSyntax

/// if / guard / for / while / switch / catch nesting inside one function or closure.
/// An else-if stays at the same depth as the if it continues.
/// Warning at 2, error at 3. The outer function starts at 0, so one if is fine.
let warnDepth = 2
let errorDepth = 3

struct Scope {
    var name: String
    var depth: Int
}

final class DepthVisitor: SyntaxVisitor {
    let path: String
    let converter: SourceLocationConverter
    var scopes: [Scope] = []
    var failed = false

    init(path: String, tree: SourceFileSyntax) {
        self.path = path
        self.converter = SourceLocationConverter(fileName: path, tree: tree)
        super.init(viewMode: .sourceAccurate)
    }

    func push(_ name: String) {
        scopes.append(Scope(name: name, depth: 0))
    }

    func pop() {
        _ = scopes.popLast()
    }

    func bump(_ node: some SyntaxProtocol, _ kind: String) {
        guard !scopes.isEmpty else { return }
        scopes[scopes.count - 1].depth += 1
        let depth = scopes[scopes.count - 1].depth
        guard depth >= warnDepth else { return }
        let severity = depth >= errorDepth ? "error" : "warning"
        let location = node.startLocation(converter: converter, afterLeadingTrivia: true)
        let line = location.line
        let column = location.column
        let name = scopes[scopes.count - 1].name
        print(
            "\(path):\(line):\(column): \(severity): [branch-depth] \(kind) is depth \(depth) in \(name) (warn \(warnDepth), error \(errorDepth))"
        )
        failed = true
    }

    func unbump() {
        guard !scopes.isEmpty, scopes[scopes.count - 1].depth > 0 else { return }
        scopes[scopes.count - 1].depth -= 1
    }

    override func visit(_ node: FunctionDeclSyntax) -> SyntaxVisitorContinueKind {
        push(node.name.text)
        return .visitChildren
    }

    override func visitPost(_ node: FunctionDeclSyntax) {
        pop()
    }

    override func visit(_ node: InitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        push("init")
        return .visitChildren
    }

    override func visitPost(_ node: InitializerDeclSyntax) {
        pop()
    }

    override func visit(_ node: DeinitializerDeclSyntax) -> SyntaxVisitorContinueKind {
        push("deinit")
        return .visitChildren
    }

    override func visitPost(_ node: DeinitializerDeclSyntax) {
        pop()
    }

    override func visit(_ node: AccessorDeclSyntax) -> SyntaxVisitorContinueKind {
        push(node.accessorSpecifier.text)
        return .visitChildren
    }

    override func visitPost(_ node: AccessorDeclSyntax) {
        pop()
    }

    override func visit(_ node: ClosureExprSyntax) -> SyntaxVisitorContinueKind {
        push("closure")
        return .visitChildren
    }

    override func visitPost(_ node: ClosureExprSyntax) {
        pop()
    }

    override func visit(_ node: IfExprSyntax) -> SyntaxVisitorContinueKind {
        var current: IfExprSyntax? = node
        while let item = current {
            bump(item, "if")
            walk(item.conditions)
            walk(item.body)
            if let next = item.elseBody?.as(IfExprSyntax.self) {
                unbump()
                current = next
                continue
            }
            if let elseBody = item.elseBody {
                walk(elseBody)
            }
            unbump()
            current = nil
        }
        return .skipChildren
    }

    override func visit(_ node: GuardStmtSyntax) -> SyntaxVisitorContinueKind {
        bump(node, "guard")
        return .visitChildren
    }

    override func visitPost(_ node: GuardStmtSyntax) {
        unbump()
    }

    override func visit(_ node: ForStmtSyntax) -> SyntaxVisitorContinueKind {
        bump(node, "for")
        return .visitChildren
    }

    override func visitPost(_ node: ForStmtSyntax) {
        unbump()
    }

    override func visit(_ node: WhileStmtSyntax) -> SyntaxVisitorContinueKind {
        bump(node, "while")
        return .visitChildren
    }

    override func visitPost(_ node: WhileStmtSyntax) {
        unbump()
    }

    override func visit(_ node: RepeatStmtSyntax) -> SyntaxVisitorContinueKind {
        bump(node, "repeat")
        return .visitChildren
    }

    override func visitPost(_ node: RepeatStmtSyntax) {
        unbump()
    }

    override func visit(_ node: SwitchExprSyntax) -> SyntaxVisitorContinueKind {
        bump(node, "switch")
        return .visitChildren
    }

    override func visitPost(_ node: SwitchExprSyntax) {
        unbump()
    }

    override func visit(_ node: CatchClauseSyntax) -> SyntaxVisitorContinueKind {
        bump(node, "catch")
        return .visitChildren
    }

    override func visitPost(_ node: CatchClauseSyntax) {
        unbump()
    }
}

let roots = Array(CommandLine.arguments.dropFirst())
if roots.isEmpty {
    fputs("usage: branch-depth <dir-or-swift-file>...\n", stderr)
    exit(2)
}

var failed = false
let manager = FileManager.default
for root in roots {
    var isDir: ObjCBool = false
    guard manager.fileExists(atPath: root, isDirectory: &isDir) else {
        fputs("missing \(root)\n", stderr)
        failed = true
        continue
    }
    var files: [String] = []
    if isDir.boolValue {
        guard let enumerator = manager.enumerator(atPath: root) else { continue }
        while let relative = enumerator.nextObject() as? String {
            if relative.contains("/.build/") || relative.hasPrefix(".build/") { continue }
            if relative.hasSuffix(".swift") {
                files.append((root as NSString).appendingPathComponent(relative))
            }
        }
    } else if root.hasSuffix(".swift") {
        files.append(root)
    }
    for file in files.sorted() {
        let source = try String(contentsOfFile: file, encoding: .utf8)
        let tree = Parser.parse(source: source)
        let visitor = DepthVisitor(path: file, tree: tree)
        visitor.walk(tree)
        if visitor.failed { failed = true }
    }
}

exit(failed ? 1 : 0)
