const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const Allocator = @import("std").mem.Allocator;

pub const id = "@typescript-eslint/no-namespace";

pub fn check(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    declaration: ast.TSModuleDeclaration,
    index: ast.NodeIndex,
    allow_declarations: bool,
) Allocator.Error!void {
    // String-named declarations describe external modules, not namespaces.
    if (tree.data(declaration.id) == .string_literal) return;
    if (allow_declarations and declaration.declare) return;

    try core.addDiagnostic(
        allocator,
        diagnostics,
        .@"error",
        id,
        "TypeScript namespaces are not allowed.",
        tree.span(index),
    );
}
