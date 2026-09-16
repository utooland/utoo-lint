const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const traverser = @import("../semantic_compat.zig").traverser;
const Allocator = std.mem.Allocator;

pub const id = "no-global-assign";

pub const Options = struct {
    exceptions: core.NoShadowAllowNames = .{},
    /// Globals declared through `languageOptions.globals`.
    configured_globals: ?*const core.ConfiguredGlobals = null,
};

pub fn run(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
) Allocator.Error!void {
    try runWithOptions(allocator, diagnostics, tree, symbol_table, .{});
}

pub fn runWithOptions(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    symbol_table: traverser.semantic.SymbolTable,
    options: Options,
) Allocator.Error!void {
    var visitor = Visitor{
        .allocator = allocator,
        .diagnostics = diagnostics,
        .symbol_table = symbol_table,
        .options = options,
    };

    try traverser.basic.traverse(Visitor, tree, &visitor);
}

const Visitor = struct {
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    symbol_table: traverser.semantic.SymbolTable,
    options: Options,

    pub fn enter_assignment_expression(
        self: *Visitor,
        expression: ast.AssignmentExpression,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        try self.checkTarget(ctx.tree, expression.left);
        return .proceed;
    }

    pub fn enter_update_expression(
        self: *Visitor,
        expression: ast.UpdateExpression,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        try self.checkTarget(ctx.tree, expression.argument);
        return .proceed;
    }

    fn checkTarget(
        self: *Visitor,
        tree: *const ast.Tree,
        target: ast.NodeIndex,
    ) Allocator.Error!void {
        if (target == .null) return;

        const unwrapped = unwrapTransparent(tree, target);
        switch (tree.data(unwrapped)) {
            .identifier_reference => |identifier| try self.checkIdentifier(tree, identifier.name, unwrapped),
            .assignment_pattern => |pattern| try self.checkTarget(tree, pattern.left),
            .binding_rest_element => |element| try self.checkTarget(tree, element.argument),
            .array_pattern => |pattern| {
                for (tree.extra(pattern.elements)) |element| {
                    try self.checkTarget(tree, element);
                }
                try self.checkTarget(tree, pattern.rest);
            },
            .object_pattern => |pattern| {
                for (tree.extra(pattern.properties)) |property_index| {
                    const property = switch (tree.data(property_index)) {
                        .binding_property => |property| property,
                        else => continue,
                    };
                    try self.checkTarget(tree, property.value);
                }
                try self.checkTarget(tree, pattern.rest);
            },
            else => {},
        }
    }

    fn checkIdentifier(
        self: *Visitor,
        tree: *const ast.Tree,
        name_string: ast.String,
        node: ast.NodeIndex,
    ) Allocator.Error!void {
        const name = tree.string(name_string);
        if (!self.isReadonly(name)) return;
        if (self.options.exceptions.contains(name)) return;
        if (!isUnresolvedReference(self.symbol_table, node)) return;

        try core.addDiagnosticFmt(
            self.allocator,
            self.diagnostics,
            .warning,
            id,
            tree.span(node),
            "Read-only global '{s}' should not be modified.",
            .{name},
        );
    }

    /// A configured global overrides the built-in table, so
    /// `{ Object: "writable" }` allows the write and `{ APP: "readonly" }`
    /// reports it. `off` removes the global, which `no-undef` reports instead.
    fn isReadonly(self: *const Visitor, name: []const u8) bool {
        if (self.options.configured_globals) |globals| {
            if (globals.lookup(name)) |state| return state == .readonly;
        }
        return isReadonlyGlobal(name);
    }
};

fn isReadonlyGlobal(name: []const u8) bool {
    if (name.len == 0) return false;

    return switch (name[0]) {
        'A' => isOneOf(name, .{ "AggregateError", "Array", "ArrayBuffer", "AsyncDisposableStack", "Atomics" }),
        'B' => isOneOf(name, .{ "BigInt", "BigInt64Array", "BigUint64Array", "Boolean" }),
        'D' => isOneOf(name, .{ "DataView", "Date", "DisposableStack" }),
        'E' => isOneOf(name, .{ "Error", "EvalError" }),
        'F' => isOneOf(name, .{ "FinalizationRegistry", "Float16Array", "Float32Array", "Float64Array", "Function" }),
        'I' => isOneOf(name, .{ "Infinity", "Int8Array", "Int16Array", "Int32Array", "Intl", "Iterator" }),
        'J' => std.mem.eql(u8, name, "JSON"),
        'M' => isOneOf(name, .{ "Map", "Math" }),
        'N' => isOneOf(name, .{ "NaN", "Number" }),
        'O' => std.mem.eql(u8, name, "Object"),
        'P' => isOneOf(name, .{ "Promise", "Proxy" }),
        'R' => isOneOf(name, .{ "RangeError", "ReferenceError", "Reflect", "RegExp" }),
        'S' => isOneOf(name, .{ "Set", "SharedArrayBuffer", "String", "SuppressedError", "Symbol", "SyntaxError" }),
        'T' => isOneOf(name, .{ "Temporal", "TypeError" }),
        'U' => isOneOf(name, .{ "Uint8Array", "Uint8ClampedArray", "Uint16Array", "Uint32Array", "URIError" }),
        'W' => isOneOf(name, .{ "WeakMap", "WeakRef", "WeakSet" }),
        'c' => std.mem.eql(u8, name, "constructor"),
        'd' => isOneOf(name, .{ "decodeURI", "decodeURIComponent" }),
        'e' => isOneOf(name, .{ "encodeURI", "encodeURIComponent", "escape", "eval" }),
        'g' => std.mem.eql(u8, name, "globalThis"),
        'h' => std.mem.eql(u8, name, "hasOwnProperty"),
        'i' => isOneOf(name, .{ "isFinite", "isNaN", "isPrototypeOf" }),
        'p' => isOneOf(name, .{ "parseFloat", "parseInt", "propertyIsEnumerable" }),
        't' => isOneOf(name, .{ "toLocaleString", "toString" }),
        'u' => isOneOf(name, .{ "undefined", "unescape" }),
        'v' => std.mem.eql(u8, name, "valueOf"),
        else => false,
    };
}

fn isOneOf(name: []const u8, comptime values: anytype) bool {
    inline for (values) |value| {
        if (std.mem.eql(u8, name, value)) return true;
    }
    return false;
}

fn isUnresolvedReference(
    symbol_table: traverser.semantic.SymbolTable,
    node: ast.NodeIndex,
) bool {
    const reference = symbol_table.model.referenceOf(node) orelse return true;
    return symbol_table.referenceSymbol(reference) == .none;
}

fn unwrapTransparent(tree: *const ast.Tree, index: ast.NodeIndex) ast.NodeIndex {
    var current = index;

    while (current != .null) {
        switch (tree.data(current)) {
            .chain_expression => |chain| current = chain.expression,
            .parenthesized_expression => |parenthesized| current = parenthesized.expression,
            else => return current,
        }
    }

    return current;
}
