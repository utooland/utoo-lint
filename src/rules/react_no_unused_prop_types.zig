const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");
const react_prop_types = @import("react_prop_types.zig");

const ast = parser.ast;
const Allocator = std.mem.Allocator;

pub const id = "react/no-unused-prop-types";

pub fn run(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    symbols: @import("../semantic_compat.zig").SymbolTable,
    skip_shape_props: bool,
    ignore: *const core.ReactPropTypesIgnoreNames,
    custom_validators: *const core.ReactPropTypesIgnoreNames,
) Allocator.Error!void {
    var state = try react_prop_types.collectWithCustomValidators(allocator, tree, symbols, custom_validators);
    defer state.deinit(allocator);

    for (state.components.items) |component| {
        if (!component.detected) continue;
        try reportUnusedProps(allocator, diagnostics, tree, component, component.declared_props.items, "", skip_shape_props, ignore);
    }
}

fn reportUnusedProps(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    component: react_prop_types.ComponentInfo,
    props: []const react_prop_types.DeclaredProp,
    prefix: []const u8,
    skip_shape_props: bool,
    ignore: *const core.ReactPropTypesIgnoreNames,
) Allocator.Error!void {
    for (props) |prop| {
        const full_name = if (prefix.len == 0)
            try allocator.dupe(u8, prop.name)
        else
            try std.fmt.allocPrint(allocator, "{s}.{s}", .{ prefix, prop.name });
        defer allocator.free(full_name);

        if (ignore.ignoresPath(full_name)) continue;

        if (skip_shape_props and (prop.kind == .shape or prop.kind == .exact)) {
            continue;
        }

        if (!componentUsesProp(component, prop.name) and !componentUsesProp(component, full_name)) {
            try core.addDiagnosticFmt(
                allocator,
                diagnostics,
                .@"error",
                id,
                tree.span(prop.node),
                "'{s}' PropType is defined but prop is never used",
                .{full_name},
            );
        }

        try reportUnusedProps(allocator, diagnostics, tree, component, prop.children.items, full_name, skip_shape_props, ignore);
    }
}

fn componentUsesProp(component: react_prop_types.ComponentInfo, name: []const u8) bool {
    for (component.forwarded_props.items) |prefix| {
        if (prefix.len == 0 or std.mem.eql(u8, prefix, name)) return true;
        if (name.len > prefix.len and std.mem.startsWith(u8, name, prefix) and name[prefix.len] == '.') return true;
    }
    for (component.used_props.items) |used| {
        if (std.mem.eql(u8, used.name, name)) return true;
    }
    return false;
}
