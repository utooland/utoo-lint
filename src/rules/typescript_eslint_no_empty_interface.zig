const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");

const ast = parser.ast;
const traverser = @import("../semantic_compat.zig").traverser;
const Allocator = std.mem.Allocator;

pub const id = "@typescript-eslint/no-empty-interface";

pub const Options = struct {
    allow_single_extends: bool = false,
};

pub fn runWithOptions(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    symbols: traverser.semantic.SymbolTable,
    options: Options,
) Allocator.Error!void {
    var visitor = Visitor{ .allocator = allocator, .diagnostics = diagnostics, .symbols = symbols, .options = options };
    try traverser.basic.traverse(Visitor, tree, &visitor);
}

const Visitor = struct {
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    symbols: traverser.semantic.SymbolTable,
    options: Options,

    pub fn enter_ts_interface_declaration(
        self: *Visitor,
        declaration: ast.TSInterfaceDeclaration,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        const tree = ctx.tree;
        const body = switch (tree.data(declaration.body)) {
            .ts_interface_body => |value| value,
            else => return .proceed,
        };
        if (body.body.len != 0) return .proceed;

        const message = if (declaration.extends.len == 0)
            "An empty interface is equivalent to `{}`."
        else if (declaration.extends.len == 1 and !self.options.allow_single_extends)
            "An interface declaring no members is equivalent to its supertype."
        else
            return .proceed;

        const diagnostic_span = tree.span(declaration.id);
        if (try self.safeFix(tree, declaration, index)) |fix| {
            defer self.allocator.free(fix.replacement);
            try core.addDiagnosticWithFix(self.allocator, self.diagnostics, .warning, id, message, diagnostic_span, fix);
        } else {
            try core.addDiagnostic(self.allocator, self.diagnostics, .warning, id, message, diagnostic_span);
        }
        return .proceed;
    }

    fn safeFix(self: *const Visitor, tree: *const ast.Tree, declaration: ast.TSInterfaceDeclaration, index: ast.NodeIndex) Allocator.Error!?core.Fix {
        const conversion = self.eligibleConversion(tree, declaration, index) orelse return null;
        const base = tree.span(tree.extra(declaration.extends)[0]);
        if (try self.aliasDependsOnInterface(tree, base, conversion.symbol)) return null;
        const header_start = tree.span(declaration.id).start;
        const header_end = tree.span(if (declaration.type_parameters == .null) declaration.id else declaration.type_parameters).end;
        const header = tree.source[header_start..header_end];
        const supertype = tree.source[base.start..base.end];
        const replacement = if (conversion.default_export)
            try std.fmt.allocPrint(self.allocator, "type {s} = {s}; export type {{ {s} as default }};", .{ header, supertype, tree.source[header_start..tree.span(declaration.id).end] })
        else
            try std.fmt.allocPrint(self.allocator, "type {s} = {s}{s}", .{ header, supertype, if (needsTerminator(tree.source, conversion.span.end)) ";" else "" });
        return .{ .span = conversion.span, .replacement = replacement };
    }

    const Conversion = struct {
        symbol: traverser.semantic.SymbolId,
        span: ast.Span,
        default_export: bool,
    };

    fn eligibleConversion(self: *const Visitor, tree: *const ast.Tree, declaration: ast.TSInterfaceDeclaration, index: ast.NodeIndex) ?Conversion {
        if (declaration.extends.len != 1 or declaration.declare or declaration.id == .null or tree.lang == .dts) return null;
        if (tree.data(declaration.body) != .ts_interface_body or tree.data(declaration.body).ts_interface_body.body.len != 0) return null;
        const symbol = self.symbols.symbolOf(declaration.id) orelse return null;
        if (self.symbols.symbolDecls(symbol).len != 1) return null;

        var parent = self.symbols.parentOf(index);
        var default_export: ?ast.NodeIndex = null;
        while (parent) |ancestor| {
            switch (tree.data(ancestor)) {
                .ts_global_declaration => return null,
                .ts_module_declaration => |module| {
                    if (module.declare or tree.data(module.id) == .string_literal) return null;
                },
                .export_default_declaration => if (parent == self.symbols.parentOf(index)) {
                    default_export = ancestor;
                },
                .program => {
                    // Script-scope interfaces can merge with declarations from
                    // other files, which are outside this lint invocation.
                    if (!hasModuleStatement(tree)) return null;
                },
                .function, .arrow_function_expression => break,
                else => {},
            }
            parent = self.symbols.parentOf(ancestor);
        }

        const fix_span = tree.span(default_export orelse index);
        for (tree.comments) |comment| {
            if (comment.span.start < fix_span.end and comment.span.end > fix_span.start) return null;
        }
        return .{ .symbol = symbol, .span = fix_span, .default_export = default_export != null };
    }

    fn aliasDependsOnInterface(self: *const Visitor, tree: *const ast.Tree, base: ast.Span, target: traverser.semantic.SymbolId) Allocator.Error!bool {
        const Dependency = struct { symbol: traverser.semantic.SymbolId, value_query: bool };
        var visited: std.AutoHashMapUnmanaged(Dependency, void) = .empty;
        defer visited.deinit(self.allocator);
        var pending: std.ArrayList(ast.Span) = .empty;
        defer pending.deinit(self.allocator);
        try pending.append(self.allocator, base);
        while (pending.pop()) |dependency| {
            var references = self.symbols.iterReferences();
            while (references.next()) |reference| {
                const span = tree.span(reference.reference.node);
                if (span.start < dependency.start or span.end > dependency.end) continue;
                const symbol = self.dependencySymbol(tree, reference.id);
                if (symbol == .none) continue;
                if (symbol == target) return true;
                const value_query = self.isTypeQueryReference(tree, reference.reference.node);
                const entry = try visited.getOrPut(self.allocator, .{ .symbol = symbol, .value_query = value_query });
                if (entry.found_existing) continue;
                for (self.symbols.symbolDecls(symbol)) |declaration| {
                    if (tree.data(declaration) == .binding_identifier) {
                        const annotation = tree.data(declaration).binding_identifier.type_annotation;
                        if (annotation != .null) try pending.append(self.allocator, tree.span(annotation));
                    }
                    const parent = self.symbols.parentOf(declaration) orelse continue;
                    switch (tree.data(parent)) {
                        .ts_type_alias_declaration => |alias| {
                            try pending.append(self.allocator, tree.span(alias.type_annotation));
                            // Defaults and constraints can hide a reference
                            // that becomes circular after interface conversion.
                            if (alias.type_parameters != .null) {
                                try pending.append(self.allocator, tree.span(alias.type_parameters));
                            }
                        },
                        .ts_interface_declaration => |other| {
                            // Another empty interface can be converted in the
                            // same fix pass, removing its recursion barrier.
                            if (self.eligibleConversion(tree, other, parent) != null) {
                                try pending.append(self.allocator, tree.span(tree.extra(other.extends)[0]));
                                if (other.type_parameters != .null) {
                                    try pending.append(self.allocator, tree.span(other.type_parameters));
                                }
                            }
                        },
                        .variable_declarator => |variable| {
                            if (variable.init != .null) try pending.append(self.allocator, tree.span(variable.init));
                        },
                        .function => |function| {
                            if (function.return_type != .null) try pending.append(self.allocator, tree.span(function.return_type));
                            if (function.type_parameters != .null) try pending.append(self.allocator, tree.span(function.type_parameters));
                            try pending.append(self.allocator, tree.span(function.params));
                        },
                        .class => |class| {
                            // A class type retains an object barrier, while a
                            // query of its static members can expose an alias cycle.
                            if (value_query) try pending.append(self.allocator, tree.span(class.body));
                        },
                        // Non-convertible interfaces retain the indirection
                        // that permits recursive object types.
                        else => {},
                    }
                }
            }
        }
        return false;
    }

    fn dependencySymbol(self: *const Visitor, tree: *const ast.Tree, reference: traverser.semantic.ReferenceId) traverser.semantic.SymbolId {
        var current = self.symbols.getReference(reference).node;
        while (self.symbols.parentOf(current)) |parent| {
            switch (tree.data(parent)) {
                .ts_qualified_name => |qualified| if (qualified.left != current) break,
                .member_expression => |member| if (member.object != current or member.computed) break,
                else => break,
            }
            current = parent;
        }
        return self.entityNameSymbol(tree, current, self.symbols.symbols.len);
    }

    fn entityNameSymbol(self: *const Visitor, tree: *const ast.Tree, index: ast.NodeIndex, aliases_remaining: usize) traverser.semantic.SymbolId {
        const parts: ?struct { owner: ast.NodeIndex, property: ast.NodeIndex } = switch (tree.data(index)) {
            .ts_qualified_name => |qualified| .{ .owner = qualified.left, .property = qualified.right },
            .member_expression => |member| if (!member.computed) .{ .owner = member.object, .property = member.property } else return .none,
            else => null,
        };
        const symbol = if (parts) |qualified| block: {
            const owner = self.entityNameSymbol(tree, qualified.owner, aliases_remaining);
            if (owner == .none) return .none;
            const name = switch (tree.data(qualified.property)) {
                .identifier_name => |identifier| tree.string(identifier.name),
                else => return .none,
            };
            // Namespace exports have their own symbols. Object properties use
            // their owner's type-bearing metadata conservatively instead.
            break :block self.symbols.model.member(owner, name, .any) orelse owner;
        } else self.symbols.symbolOf(index) orelse return .none;
        for (self.symbols.symbolDecls(symbol)) |declaration| {
            const parent = self.symbols.parentOf(declaration) orelse continue;
            if (tree.data(parent) != .ts_import_equals_declaration) continue;
            const alias = tree.data(parent).ts_import_equals_declaration;
            if (tree.data(alias.module_reference) == .ts_external_module_reference) continue;
            if (aliases_remaining == 0) return .none;
            return self.entityNameSymbol(tree, alias.module_reference, aliases_remaining - 1);
        }
        return symbol;
    }

    fn isTypeQueryReference(self: *const Visitor, tree: *const ast.Tree, node: ast.NodeIndex) bool {
        var current = node;
        while (self.symbols.parentOf(current)) |parent| {
            switch (tree.data(parent)) {
                .ts_qualified_name, .member_expression => {},
                .ts_type_query => return true,
                else => return false,
            }
            current = parent;
        }
        return false;
    }
};

fn needsTerminator(source: []const u8, start: usize) bool {
    var index = start;
    while (index < source.len and std.ascii.isWhitespace(source[index])) : (index += 1) {}
    return index < source.len and switch (source[index]) {
        ';', '}' => false,
        else => true,
    };
}

fn hasModuleStatement(tree: *const ast.Tree) bool {
    const program = tree.data(tree.root).program;
    for (tree.extra(program.body)) |statement| {
        switch (tree.data(statement)) {
            .import_declaration,
            .export_named_declaration,
            .export_default_declaration,
            .export_all_declaration,
            .ts_export_assignment,
            => return true,
            .ts_import_equals_declaration => |declaration| {
                if (tree.data(declaration.module_reference) == .ts_external_module_reference) return true;
            },
            else => {},
        }
    }
    return false;
}
