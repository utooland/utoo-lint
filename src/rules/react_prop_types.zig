const std = @import("std");
const parser = @import("parser");
const core = @import("../core.zig");
const ReactContext = @import("react_hooks_helpers.zig").Context;

const ast = parser.ast;
const traverser = parser.traverser;
const Allocator = std.mem.Allocator;
const SymbolTable = @import("../semantic_compat.zig").SymbolTable;

pub const id = "react/prop-types";

const max_prop_depth = 16;

pub const DeclaredKind = enum {
    normal,
    shape,
    exact,
};

pub const DeclaredProp = struct {
    name: []const u8,
    node: ast.NodeIndex,
    kind: DeclaredKind = .normal,
    accepts_any_children: bool = false,
    children: std.ArrayList(DeclaredProp) = .empty,

    fn deinit(self: *DeclaredProp, allocator: Allocator) void {
        for (self.children.items) |*child| {
            child.deinit(allocator);
        }
        self.children.deinit(allocator);
    }
};

pub const UsedProp = struct {
    name: []const u8,
    node: ast.NodeIndex,
};

pub const ComponentInfo = struct {
    name: ?[]const u8 = null,
    node: ast.NodeIndex = .null,
    detected: bool = false,
    ignore_props_validation: bool = false,
    function_nodes: std.ArrayList(ast.NodeIndex) = .empty,
    class_nodes: std.ArrayList(ast.NodeIndex) = .empty,
    declared_props: std.ArrayList(DeclaredProp) = .empty,
    used_props: std.ArrayList(UsedProp) = .empty,
    forwarded_props: std.ArrayList([]const u8) = .empty,

    fn deinit(self: *ComponentInfo, allocator: Allocator) void {
        self.function_nodes.deinit(allocator);
        self.class_nodes.deinit(allocator);
        for (self.declared_props.items) |*prop| {
            prop.deinit(allocator);
        }
        self.declared_props.deinit(allocator);
        for (self.used_props.items) |used| {
            allocator.free(used.name);
        }
        self.used_props.deinit(allocator);
        for (self.forwarded_props.items) |path| allocator.free(path);
        self.forwarded_props.deinit(allocator);
    }
};

const PropPath = struct {
    parts: [max_prop_depth][]const u8 = undefined,
    len: usize,

    fn init(parts: []const []const u8) PropPath {
        var result = PropPath{ .len = parts.len };
        @memcpy(result.parts[0..parts.len], parts);
        return result;
    }
};

pub const State = struct {
    symbols: SymbolTable,
    aliases: std.AutoHashMapUnmanaged(@import("../semantic_compat.zig").traverser.semantic.SymbolId, PropPath) = .empty,
    components: std.ArrayList(ComponentInfo) = .empty,

    pub fn deinit(self: *State, allocator: Allocator) void {
        self.aliases.deinit(allocator);
        for (self.components.items) |*component| {
            component.deinit(allocator);
        }
        self.components.deinit(allocator);
    }

    fn ensureComponent(
        self: *State,
        allocator: Allocator,
        name: ?[]const u8,
        node: ast.NodeIndex,
        detected: bool,
    ) Allocator.Error!usize {
        if (name) |component_name| {
            for (self.components.items, 0..) |*component, index| {
                if (component.name) |existing| {
                    if (std.mem.eql(u8, existing, component_name)) {
                        component.detected = component.detected or detected;
                        if (component.node == .null) component.node = node;
                        return index;
                    }
                }
            }
        }

        try self.components.append(allocator, .{
            .name = name,
            .node = node,
            .detected = detected,
        });
        return self.components.items.len - 1;
    }

    fn componentByFunction(self: *State, node: ast.NodeIndex) ?usize {
        for (self.components.items, 0..) |component, index| {
            for (component.function_nodes.items) |function_node| {
                if (function_node == node) return index;
            }
        }
        return null;
    }

    fn componentByClass(self: *State, node: ast.NodeIndex) ?usize {
        for (self.components.items, 0..) |component, index| {
            for (component.class_nodes.items) |class_node| {
                if (class_node == node) return index;
            }
        }
        return null;
    }
};

pub fn run(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    symbols: SymbolTable,
    skip_undeclared: bool,
    ignore: *const core.ReactPropTypesIgnoreNames,
    custom_validators: *const core.ReactPropTypesIgnoreNames,
) Allocator.Error!void {
    var state = try collectWithCustomValidators(allocator, tree, symbols, custom_validators);
    defer state.deinit(allocator);

    try finish(allocator, diagnostics, tree, &state, skip_undeclared, ignore);
}

pub fn collect(
    allocator: Allocator,
    tree: *const ast.Tree,
    symbols: SymbolTable,
) Allocator.Error!State {
    const custom_validators = core.ReactPropTypesIgnoreNames{};
    return collectWithCustomValidators(allocator, tree, symbols, &custom_validators);
}

pub fn collectWithCustomValidators(
    allocator: Allocator,
    tree: *const ast.Tree,
    symbols: SymbolTable,
    custom_validators: *const core.ReactPropTypesIgnoreNames,
) Allocator.Error!State {
    var state = State{ .symbols = symbols };
    errdefer state.deinit(allocator);

    try collectComponents(allocator, tree, &state, custom_validators);

    var visitor = UsageVisitor{
        .allocator = allocator,
        .state = &state,
    };
    defer visitor.component_stack.deinit(allocator);
    defer visitor.props_stack.deinit(allocator);

    try traverser.basic.traverse(UsageVisitor, tree, &visitor);
    return state;
}

fn collectComponents(
    allocator: Allocator,
    tree: *const ast.Tree,
    state: *State,
    custom_validators: *const core.ReactPropTypesIgnoreNames,
) Allocator.Error!void {
    const program = switch (tree.data(tree.root)) {
        .program => |program| program,
        else => return,
    };

    for (tree.extra(program.body)) |statement_index| {
        try collectTopLevelDeclaration(allocator, tree, statement_index, state, custom_validators);
    }
}

fn collectTopLevelDeclaration(
    allocator: Allocator,
    tree: *const ast.Tree,
    statement_index: ast.NodeIndex,
    state: *State,
    custom_validators: *const core.ReactPropTypesIgnoreNames,
) Allocator.Error!void {
    switch (tree.data(statement_index)) {
        .function => |function| try collectFunctionDeclaration(allocator, tree, function, statement_index, state),
        .class => |class| try collectClassDeclaration(allocator, tree, class, statement_index, state, custom_validators),
        .variable_declaration => |declaration| {
            for (tree.extra(declaration.declarators)) |declarator_index| {
                const declarator = switch (tree.data(declarator_index)) {
                    .variable_declarator => |declarator| declarator,
                    else => continue,
                };
                try collectVariableDeclarator(allocator, tree, declarator, declarator_index, state, custom_validators);
            }
        },
        .expression_statement => |statement| try collectExpressionStatement(allocator, tree, statement.expression, state, custom_validators),
        .export_named_declaration => |declaration| {
            if (declaration.declaration != .null) try collectTopLevelDeclaration(allocator, tree, declaration.declaration, state, custom_validators);
        },
        .export_default_declaration => |declaration| {
            if (declaration.declaration == .null) return;
            const exported = unwrapTransparent(tree, declaration.declaration);
            const anonymous = switch (tree.data(exported)) {
                .arrow_function_expression => true,
                .function => |function| function.id == .null,
                else => false,
            };
            if (anonymous and functionReturnsJSXOrNull(tree, exported)) {
                const component_index = try state.ensureComponent(allocator, null, exported, true);
                try appendNode(allocator, &state.components.items[component_index].function_nodes, exported);
            } else {
                try collectTopLevelDeclaration(allocator, tree, exported, state, custom_validators);
            }
        },
        else => {},
    }
}

fn collectFunctionDeclaration(
    allocator: Allocator,
    tree: *const ast.Tree,
    function: ast.Function,
    index: ast.NodeIndex,
    state: *State,
) Allocator.Error!void {
    if (!functionReturnsJSXOrNull(tree, index)) return;
    const name = bindingIdentifierName(tree, function.id) orelse return;
    if (!startsUppercase(name)) return;
    const component_index = try state.ensureComponent(allocator, name, index, true);
    try appendNode(allocator, &state.components.items[component_index].function_nodes, index);
}

fn collectClassDeclaration(
    allocator: Allocator,
    tree: *const ast.Tree,
    class: ast.Class,
    index: ast.NodeIndex,
    state: *State,
    custom_validators: *const core.ReactPropTypesIgnoreNames,
) Allocator.Error!void {
    if (!isComponentClass(tree, class)) return;
    const name = bindingIdentifierName(tree, class.id) orelse return;
    const component_index = try state.ensureComponent(allocator, name, index, true);
    try appendNode(allocator, &state.components.items[component_index].class_nodes, index);
    try collectClassPropTypes(allocator, tree, class, component_index, state, custom_validators);
}

fn collectVariableDeclarator(
    allocator: Allocator,
    tree: *const ast.Tree,
    declarator: ast.VariableDeclarator,
    index: ast.NodeIndex,
    state: *State,
    custom_validators: *const core.ReactPropTypesIgnoreNames,
) Allocator.Error!void {
    const name = bindingIdentifierName(tree, declarator.id) orelse return;
    if (!startsUppercase(name) or declarator.init == .null) return;

    const init = unwrapTransparent(tree, declarator.init);
    switch (tree.data(init)) {
        .function, .arrow_function_expression => {
            if (!functionReturnsJSXOrNull(tree, init)) return;
            const component_index = try state.ensureComponent(allocator, name, index, true);
            try appendNode(allocator, &state.components.items[component_index].function_nodes, init);
            if (reactFunctionComponentProps(tree, declarator.id)) |props_type| {
                const unresolved = try collectTypeProps(allocator, tree, state.symbols, props_type, &state.components.items[component_index].declared_props, 0);
                state.components.items[component_index].ignore_props_validation = state.components.items[component_index].ignore_props_validation or unresolved;
            }
        },
        .call_expression => |call| {
            if (isCreateReactClassCall(tree, call)) {
                const object = createClassObject(tree, call) orelse return;
                const component_index = try state.ensureComponent(allocator, name, index, true);
                try collectCreateClassPropTypes(allocator, tree, object, component_index, state, custom_validators);
                return;
            }

            const wrapped = wrapperFunctionArgument(tree, state.symbols, call) orelse return;
            if (!functionReturnsJSXOrNull(tree, wrapped)) return;
            const component_index = try state.ensureComponent(allocator, name, index, true);
            try appendNode(allocator, &state.components.items[component_index].function_nodes, wrapped);
            if (wrapperPropsType(tree, state.symbols, call)) |props_type| {
                state.components.items[component_index].ignore_props_validation = try collectTypeProps(allocator, tree, state.symbols, props_type, &state.components.items[component_index].declared_props, 0);
            }
            if (reactFunctionComponentProps(tree, declarator.id)) |props_type| {
                const unresolved = try collectTypeProps(allocator, tree, state.symbols, props_type, &state.components.items[component_index].declared_props, 0);
                state.components.items[component_index].ignore_props_validation = state.components.items[component_index].ignore_props_validation or unresolved;
            }
        },
        else => {},
    }
}

fn reactFunctionComponentProps(tree: *const ast.Tree, binding: ast.NodeIndex) ?ast.NodeIndex {
    const identifier = switch (tree.data(binding)) {
        .binding_identifier => |value| value,
        else => return null,
    };
    if (identifier.type_annotation == .null) return null;
    const annotation = tree.data(identifier.type_annotation).ts_type_annotation.type_annotation;
    const reference = switch (tree.data(annotation)) {
        .ts_type_reference => |value| value,
        else => return null,
    };
    if (reference.type_arguments == .null or !isReactFunctionComponentType(tree, reference.type_name)) return null;
    const arguments = tree.extra(tree.data(reference.type_arguments).ts_type_parameter_instantiation.params);
    return if (arguments.len > 0) arguments[0] else null;
}

fn isReactFunctionComponentType(tree: *const ast.Tree, type_name: ast.NodeIndex) bool {
    const qualified = switch (tree.data(type_name)) {
        .ts_qualified_name => |name| name,
        else => null,
    };
    const local = if (qualified) |name| identifierReferenceName(tree, name.left) else identifierReferenceName(tree, type_name);
    const local_name = local orelse return false;
    if (qualified) |name| {
        const member = propertyName(tree, name.right, false) orelse return false;
        if (!std.mem.eql(u8, member, "FC") and !std.mem.eql(u8, member, "FunctionComponent")) return false;
    }
    for (tree.nodes.items(.data)) |data| {
        const declaration = switch (data) {
            .import_declaration => |value| value,
            else => continue,
        };
        const source = switch (tree.data(declaration.source)) {
            .string_literal => |value| tree.string(value.value),
            else => continue,
        };
        if (!std.mem.eql(u8, source, "react")) continue;
        for (tree.extra(declaration.specifiers)) |specifier| {
            switch (tree.data(specifier)) {
                .import_default_specifier => |value| if (qualified != null and std.mem.eql(u8, bindingIdentifierName(tree, value.local) orelse "", local_name)) {
                    return true;
                },
                .import_namespace_specifier => |value| if (qualified != null and std.mem.eql(u8, bindingIdentifierName(tree, value.local) orelse "", local_name)) {
                    return true;
                },
                .import_specifier => |value| {
                    if (qualified != null or !std.mem.eql(u8, bindingIdentifierName(tree, value.local) orelse "", local_name)) continue;
                    const imported = propertyName(tree, value.imported, false) orelse continue;
                    if (std.mem.eql(u8, imported, "FC") or std.mem.eql(u8, imported, "FunctionComponent")) return true;
                },
                else => {},
            }
        }
    }
    return false;
}

fn collectTypeProps(allocator: Allocator, tree: *const ast.Tree, symbols: SymbolTable, index: ast.NodeIndex, props: *std.ArrayList(DeclaredProp), depth: usize) Allocator.Error!bool {
    if (index == .null) return false;
    if (depth >= max_prop_depth) return true;
    const members = switch (tree.data(index)) {
        .ts_type_annotation => |annotation| return collectTypeProps(allocator, tree, symbols, annotation.type_annotation, props, depth + 1),
        .ts_type_literal => |literal| literal.members,
        .ts_interface_body => |body| body.body,
        .ts_intersection_type => |intersection| {
            var unresolved = false;
            for (tree.extra(intersection.types)) |part| {
                const part_unresolved = try collectTypeProps(allocator, tree, symbols, part, props, depth + 1);
                unresolved = unresolved or part_unresolved;
            }
            return unresolved;
        },
        .ts_type_reference => |reference| return collectReferencedTypeProps(allocator, tree, symbols, reference.type_name, props, depth),
        .ts_interface_heritage => |heritage| return collectReferencedTypeProps(allocator, tree, symbols, heritage.expression, props, depth),
        .ts_type_alias_declaration => |alias| return collectTypeProps(allocator, tree, symbols, alias.type_annotation, props, depth + 1),
        .ts_interface_declaration => |interface| {
            var unresolved = try collectTypeProps(allocator, tree, symbols, interface.body, props, depth + 1);
            for (tree.extra(interface.extends)) |base| {
                const base_unresolved = try collectTypeProps(allocator, tree, symbols, base, props, depth + 1);
                unresolved = unresolved or base_unresolved;
            }
            return unresolved;
        },
        .ts_type_parameter => |parameter| return collectTypeProps(allocator, tree, symbols, parameter.constraint, props, depth + 1),

        else => return true,
    };
    for (tree.extra(members)) |member| {
        const property = switch (tree.data(member)) {
            .ts_property_signature => |value| value,
            .ts_method_signature => |method| {
                const name = propertyName(tree, method.key, method.computed) orelse continue;
                const prop = try ensureDeclaredProp(allocator, props, name, method.key);
                prop.accepts_any_children = true;
                continue;
            },
            else => continue,
        };
        const name = propertyName(tree, property.key, property.computed) orelse continue;
        const prop = try ensureDeclaredProp(allocator, props, name, property.key);
        // TypeScript validates members of a declared prop, including built-in
        // methods and properties of imported types, without runtime validators.
        prop.accepts_any_children = true;
        // eslint-plugin-react collects TypeScript prop declarations at the
        // top level only; nested fields are not runtime PropTypes shapes.
    }
    return false;
}

fn collectReferencedTypeProps(allocator: Allocator, tree: *const ast.Tree, symbols: SymbolTable, name: ast.NodeIndex, props: *std.ArrayList(DeclaredProp), depth: usize) Allocator.Error!bool {
    const symbol = symbols.symbolOf(name) orelse return true;
    var unresolved = false;
    var found = false;
    for (symbols.symbolDecls(symbol)) |declaration| {
        const parent = symbols.parentOf(declaration) orelse continue;
        found = true;
        const part_unresolved = try collectTypeProps(allocator, tree, symbols, parent, props, depth + 1);
        unresolved = unresolved or part_unresolved;
    }
    return !found or unresolved;
}

fn collectExpressionStatement(
    allocator: Allocator,
    tree: *const ast.Tree,
    expression_index: ast.NodeIndex,
    state: *State,
    custom_validators: *const core.ReactPropTypesIgnoreNames,
) Allocator.Error!void {
    const assignment = switch (tree.data(unwrapTransparent(tree, expression_index))) {
        .assignment_expression => |assignment| assignment,
        else => return,
    };
    if (assignment.operator != .assign) return;

    const target = propTypesAssignmentTarget(tree, assignment.left) orelse return;
    const component_index = try state.ensureComponent(allocator, target.component, assignment.left, false);
    if (target.prop) |prop| {
        try addDeclaredPropValue(allocator, tree, &state.components.items[component_index].declared_props, prop, assignment.left, assignment.right, custom_validators);
    } else {
        try collectPropTypesObject(allocator, tree, assignment.right, component_index, state, custom_validators);
    }
}

fn collectClassPropTypes(
    allocator: Allocator,
    tree: *const ast.Tree,
    class: ast.Class,
    component_index: usize,
    state: *State,
    custom_validators: *const core.ReactPropTypesIgnoreNames,
) Allocator.Error!void {
    const body = switch (tree.data(class.body)) {
        .class_body => |body| body,
        else => return,
    };

    for (tree.extra(body.body)) |member_index| {
        const property = switch (tree.data(member_index)) {
            .property_definition => |property| property,
            else => continue,
        };
        if (!property.static) continue;
        const key = propertyName(tree, property.key, property.computed) orelse continue;
        if (!std.mem.eql(u8, key, "propTypes")) continue;
        try collectPropTypesObject(allocator, tree, property.value, component_index, state, custom_validators);
    }
}

fn collectCreateClassPropTypes(
    allocator: Allocator,
    tree: *const ast.Tree,
    object: ast.ObjectExpression,
    component_index: usize,
    state: *State,
    custom_validators: *const core.ReactPropTypesIgnoreNames,
) Allocator.Error!void {
    for (tree.extra(object.properties)) |property_index| {
        const property = switch (tree.data(property_index)) {
            .object_property => |property| property,
            else => continue,
        };
        const key = propertyName(tree, property.key, property.computed) orelse continue;
        if (!std.mem.eql(u8, key, "propTypes")) continue;
        try collectPropTypesObject(allocator, tree, property.value, component_index, state, custom_validators);
    }
}

fn collectPropTypesObject(
    allocator: Allocator,
    tree: *const ast.Tree,
    value: ast.NodeIndex,
    component_index: usize,
    state: *State,
    custom_validators: *const core.ReactPropTypesIgnoreNames,
) Allocator.Error!void {
    const object = switch (tree.data(unwrapTransparent(tree, value))) {
        .object_expression => |object| object,
        else => return,
    };

    for (tree.extra(object.properties)) |property_index| {
        switch (tree.data(property_index)) {
            .object_property => |property| {
                const name = propertyName(tree, property.key, property.computed) orelse continue;
                try addDeclaredPropValue(
                    allocator,
                    tree,
                    &state.components.items[component_index].declared_props,
                    name,
                    property_index,
                    property.value,
                    custom_validators,
                );
            },
            else => {},
        }
    }
}

fn addDeclaredPropValue(
    allocator: Allocator,
    tree: *const ast.Tree,
    props: *std.ArrayList(DeclaredProp),
    name: []const u8,
    node: ast.NodeIndex,
    value: ast.NodeIndex,
    custom_validators: *const core.ReactPropTypesIgnoreNames,
) Allocator.Error!void {
    var prop = try ensureDeclaredProp(allocator, props, name, node);
    const target = stripIsRequired(tree, value);

    if (propTypeTargetName(tree, target)) |target_name| {
        if (acceptsAnyChildren(target_name)) {
            prop.accepts_any_children = true;
        }
    }

    if (propTypeCall(tree, target)) |call| {
        if (isCustomValidatorCall(tree, call, custom_validators)) {
            prop.accepts_any_children = true;
            return;
        }

        const callee_name = propTypeTargetName(tree, call.callee) orelse return;
        if (acceptsAnyChildren(callee_name)) {
            prop.accepts_any_children = true;
            return;
        }
        if (std.mem.eql(u8, callee_name, "shape") or std.mem.eql(u8, callee_name, "exact")) {
            prop.kind = if (std.mem.eql(u8, callee_name, "shape")) .shape else .exact;
            const arguments = tree.extra(call.arguments);
            if (arguments.len == 0) return;
            try collectShapeChildren(allocator, tree, arguments[0], prop, custom_validators);
        } else if (std.mem.eql(u8, callee_name, "arrayOf") or std.mem.eql(u8, callee_name, "objectOf")) {
            const arguments = tree.extra(call.arguments);
            if (arguments.len == 0) return;
            const child_call = propTypeCall(tree, stripIsRequired(tree, arguments[0])) orelse return;
            if (isCustomValidatorCall(tree, child_call, custom_validators)) {
                prop.accepts_any_children = true;
                return;
            }
            const child_name = propTypeTargetName(tree, child_call.callee) orelse return;
            if (std.mem.eql(u8, child_name, "shape") or std.mem.eql(u8, child_name, "exact")) {
                const child_arguments = tree.extra(child_call.arguments);
                if (child_arguments.len > 0) try collectShapeChildren(allocator, tree, child_arguments[0], prop, custom_validators);
            } else if (acceptsAnyChildren(child_name)) {
                prop.accepts_any_children = true;
            }
        }
    }
}

fn collectShapeChildren(
    allocator: Allocator,
    tree: *const ast.Tree,
    value: ast.NodeIndex,
    parent: *DeclaredProp,
    custom_validators: *const core.ReactPropTypesIgnoreNames,
) Allocator.Error!void {
    const object = switch (tree.data(unwrapTransparent(tree, value))) {
        .object_expression => |object| object,
        else => return,
    };

    for (tree.extra(object.properties)) |property_index| {
        const property = switch (tree.data(property_index)) {
            .object_property => |property| property,
            else => continue,
        };
        const name = propertyName(tree, property.key, property.computed) orelse continue;
        try addDeclaredPropValue(allocator, tree, &parent.children, name, property_index, property.value, custom_validators);
    }
}

fn isCustomValidatorCall(tree: *const ast.Tree, call: ast.CallExpression, custom_validators: *const core.ReactPropTypesIgnoreNames) bool {
    const member = switch (tree.data(unwrapTransparent(tree, call.callee))) {
        .member_expression => |member| member,
        else => return false,
    };
    const object_name = identifierReferenceName(tree, member.object) orelse return false;
    return custom_validators.contains(object_name);
}

fn ensureDeclaredProp(
    allocator: Allocator,
    props: *std.ArrayList(DeclaredProp),
    name: []const u8,
    node: ast.NodeIndex,
) Allocator.Error!*DeclaredProp {
    for (props.items) |*prop| {
        if (std.mem.eql(u8, prop.name, name)) return prop;
    }
    try props.append(allocator, .{ .name = name, .node = node });
    return &props.items[props.items.len - 1];
}

const UsageVisitor = struct {
    allocator: Allocator,
    state: *State,
    component_stack: std.ArrayList(?usize) = .empty,
    props_stack: std.ArrayList(?[]const u8) = .empty,

    fn currentComponent(self: *UsageVisitor) ?usize {
        if (self.component_stack.items.len == 0) return null;
        return self.component_stack.items[self.component_stack.items.len - 1];
    }

    fn currentPropsName(self: *UsageVisitor) ?[]const u8 {
        if (self.props_stack.items.len == 0) return null;
        return self.props_stack.items[self.props_stack.items.len - 1];
    }

    fn pushContext(self: *UsageVisitor, allocator: Allocator, component: ?usize, props_name: ?[]const u8) Allocator.Error!void {
        try self.component_stack.append(allocator, component);
        try self.props_stack.append(allocator, props_name);
    }

    fn popContext(self: *UsageVisitor) void {
        _ = self.component_stack.pop();
        _ = self.props_stack.pop();
    }

    pub fn enter_class(
        self: *UsageVisitor,
        _: ast.Class,
        index: ast.NodeIndex,
        _: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        const component = self.state.componentByClass(index) orelse self.currentComponent();
        try self.pushContext(self.allocator, component, self.currentPropsName());
        return .proceed;
    }

    pub fn exit_class(self: *UsageVisitor, _: ast.Class, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        self.popContext();
    }

    pub fn enter_function(
        self: *UsageVisitor,
        function: ast.Function,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        const component = self.state.componentByFunction(index) orelse self.currentComponent();
        var props_name = self.currentPropsName();
        if (self.state.componentByFunction(index)) |component_index| {
            props_name = try collectComponentParams(self.allocator, ctx.tree, function.params, component_index, self.state);
        } else if (props_name != null and paramsContainBinding(ctx.tree, function.params, props_name.?)) {
            props_name = null;
        }
        try self.pushContext(self.allocator, component, props_name);
        return .proceed;
    }

    pub fn exit_function(self: *UsageVisitor, _: ast.Function, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        self.popContext();
    }

    pub fn enter_arrow_function_expression(
        self: *UsageVisitor,
        arrow: ast.ArrowFunctionExpression,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        const component = self.state.componentByFunction(index) orelse self.currentComponent();
        var props_name = self.currentPropsName();
        if (self.state.componentByFunction(index)) |component_index| {
            props_name = try collectComponentParams(self.allocator, ctx.tree, arrow.params, component_index, self.state);
        } else if (props_name != null and paramsContainBinding(ctx.tree, arrow.params, props_name.?)) {
            props_name = null;
        }
        try self.pushContext(self.allocator, component, props_name);
        return .proceed;
    }

    pub fn exit_arrow_function_expression(self: *UsageVisitor, _: ast.ArrowFunctionExpression, _: ast.NodeIndex, _: *traverser.basic.Ctx) void {
        self.popContext();
    }

    fn propPath(self: *UsageVisitor, tree: *const ast.Tree, index: ast.NodeIndex, buffer: *[max_prop_depth][]const u8) ?[]const []const u8 {
        if (propSourcePath(tree, unwrapPropFallback(tree, index), null, buffer)) |path| return path;
        var reversed: [max_prop_depth][]const u8 = undefined;
        var len: usize = 0;
        var current = unwrapPropFallback(tree, index);
        while (current != .null) {
            const member = switch (tree.data(current)) {
                .member_expression => |value| value,
                else => break,
            };
            if (len == reversed.len) return null;
            reversed[len] = propertyName(tree, member.property, member.computed) orelse return null;
            len += 1;
            current = unwrapPropFallback(tree, member.object);
        }
        if (current == .null or tree.data(current) != .identifier_reference) return null;
        const symbol = self.state.symbols.symbolOf(current) orelse return null;
        const alias = self.state.aliases.get(symbol) orelse return null;
        if (alias.len + len > buffer.len) return null;
        @memcpy(buffer[0..alias.len], alias.parts[0..alias.len]);
        for (0..len) |i| buffer[alias.len + i] = reversed[len - i - 1];
        return buffer[0 .. alias.len + len];
    }

    fn clearAssignedAliases(self: *UsageVisitor, tree: *const ast.Tree, index: ast.NodeIndex) void {
        const target = unwrapTransparent(tree, index);
        if (target == .null) return;
        switch (tree.data(target)) {
            .identifier_reference, .binding_identifier => {
                if (self.state.symbols.symbolOf(target)) |symbol| _ = self.state.aliases.remove(symbol);
            },
            .assignment_pattern => |pattern| self.clearAssignedAliases(tree, pattern.left),
            .binding_rest_element => |element| self.clearAssignedAliases(tree, element.argument),
            .array_pattern => |pattern| {
                for (tree.extra(pattern.elements)) |element| self.clearAssignedAliases(tree, element);
                self.clearAssignedAliases(tree, pattern.rest);
            },
            .object_pattern => |pattern| {
                for (tree.extra(pattern.properties)) |property_index| {
                    const property = switch (tree.data(property_index)) {
                        .binding_property => |property| property,
                        else => continue,
                    };
                    self.clearAssignedAliases(tree, property.value);
                }
                self.clearAssignedAliases(tree, pattern.rest);
            },
            else => {},
        }
    }

    pub fn exit_assignment_expression(self: *UsageVisitor, assignment: ast.AssignmentExpression, _: ast.NodeIndex, ctx: *traverser.basic.Ctx) void {
        const target = unwrapTransparent(ctx.tree, assignment.left);
        if (ctx.tree.data(target) != .identifier_reference) {
            self.clearAssignedAliases(ctx.tree, target);
            return;
        }
        const symbol = self.state.symbols.symbolOf(target) orelse return;
        var buffer: [max_prop_depth][]const u8 = undefined;
        if (assignment.operator == .assign) {
            if (self.propPath(ctx.tree, assignment.right, &buffer)) |path| {
                if (self.state.aliases.getPtr(symbol)) |alias| alias.* = PropPath.init(path);
                return;
            }
        }
        _ = self.state.aliases.remove(symbol);
    }

    pub fn enter_member_expression(
        self: *UsageVisitor,
        _: ast.MemberExpression,
        index: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        const component_index = self.currentComponent() orelse return .proceed;
        var parts_buffer: [max_prop_depth][]const u8 = undefined;
        const path = self.propPath(ctx.tree, index, &parts_buffer) orelse return .proceed;
        if (path.len == 0) return .proceed;
        try addUsedProp(self.allocator, &self.state.components.items[component_index], path, memberDiagnosticNode(ctx.tree, index));
        return .proceed;
    }

    pub fn enter_jsx_spread_attribute(self: *UsageVisitor, spread: ast.JSXSpreadAttribute, _: ast.NodeIndex, ctx: *traverser.basic.Ctx) Allocator.Error!traverser.Action {
        const component_index = self.currentComponent() orelse return .proceed;
        var buffer: [max_prop_depth][]const u8 = undefined;
        const path = self.propPath(ctx.tree, spread.argument, &buffer) orelse return .proceed;
        const name = try joinParts(self.allocator, path);
        errdefer self.allocator.free(name);
        try self.state.components.items[component_index].forwarded_props.append(self.allocator, name);
        return .proceed;
    }

    pub fn enter_variable_declarator(
        self: *UsageVisitor,
        declarator: ast.VariableDeclarator,
        _: ast.NodeIndex,
        ctx: *traverser.basic.Ctx,
    ) Allocator.Error!traverser.Action {
        if (declarator.init == .null) return .proceed;
        const component_index = self.currentComponent() orelse return .proceed;
        var parts_buffer: [max_prop_depth][]const u8 = undefined;
        const prefix = self.propPath(ctx.tree, declarator.init, &parts_buffer) orelse return .proceed;
        try collectPatternUsage(self.allocator, ctx.tree, self.state, &self.state.components.items[component_index], declarator.id, prefix);
        return .proceed;
    }
};

fn unwrapPropFallback(tree: *const ast.Tree, index: ast.NodeIndex) ast.NodeIndex {
    var current = unwrapTransparent(tree, index);
    while (current != .null) {
        const logical = switch (tree.data(current)) {
            .logical_expression => |value| value,
            else => break,
        };
        if (logical.operator != .@"or" and logical.operator != .nullish_coalescing) break;
        current = unwrapTransparent(tree, logical.left);
    }
    return current;
}

fn collectComponentParams(
    allocator: Allocator,
    tree: *const ast.Tree,
    params_index: ast.NodeIndex,
    component_index: usize,
    state: *State,
) Allocator.Error!?[]const u8 {
    const params = switch (tree.data(params_index)) {
        .formal_parameters => |params| params,
        else => return null,
    };
    const items = tree.extra(params.items);
    if (items.len == 0) return null;
    const first = switch (tree.data(items[0])) {
        .formal_parameter => |param| param.pattern,
        else => items[0],
    };
    const pattern = unwrapAssignmentPattern(tree, first);
    const annotation = if (tree.data(first) == .assignment_pattern and tree.data(first).assignment_pattern.type_annotation != .null) tree.data(first).assignment_pattern.type_annotation else switch (tree.data(pattern)) {
        .binding_identifier => |binding| binding.type_annotation,
        .object_pattern => |binding| binding.type_annotation,
        .array_pattern => |binding| binding.type_annotation,
        else => .null,
    };
    const unresolved = try collectTypeProps(allocator, tree, state.symbols, annotation, &state.components.items[component_index].declared_props, 0);
    state.components.items[component_index].ignore_props_validation = state.components.items[component_index].ignore_props_validation or unresolved;
    try collectPatternUsage(allocator, tree, state, &state.components.items[component_index], pattern, &.{});
    if (bindingIdentifierName(tree, pattern)) |name| return name;
    return null;
}

fn collectPatternUsage(
    allocator: Allocator,
    tree: *const ast.Tree,
    state: *State,
    component: *ComponentInfo,
    pattern_index: ast.NodeIndex,
    prefix: []const []const u8,
) Allocator.Error!void {
    if (pattern_index == .null) return;
    const binding = unwrapAssignmentPattern(tree, pattern_index);
    if (binding == .null) return;
    const pattern = switch (tree.data(binding)) {
        .binding_identifier => {
            const symbol = state.symbols.symbolOf(binding) orelse return;
            try state.aliases.put(allocator, symbol, PropPath.init(prefix));
            return;
        },
        .binding_rest_element => |rest| return collectPatternUsage(allocator, tree, state, component, rest.argument, prefix),
        .object_pattern => |pattern| pattern,
        else => return,
    };

    try collectPatternUsage(allocator, tree, state, component, pattern.rest, prefix);
    for (tree.extra(pattern.properties)) |property_index| {
        const property = switch (tree.data(property_index)) {
            .binding_property => |property| property,
            else => continue,
        };
        const key = propertyName(tree, property.key, property.computed) orelse continue;
        var path_buffer: [max_prop_depth][]const u8 = undefined;
        if (prefix.len + 1 > path_buffer.len) continue;
        @memcpy(path_buffer[0..prefix.len], prefix);
        path_buffer[prefix.len] = key;
        const path = path_buffer[0 .. prefix.len + 1];
        try addUsedProp(allocator, component, path, property.key);
        try collectPatternUsage(allocator, tree, state, component, property.value, path);
    }
}

fn addUsedProp(
    allocator: Allocator,
    component: *ComponentInfo,
    parts: []const []const u8,
    node: ast.NodeIndex,
) Allocator.Error!void {
    if (parts.len == 0) return;
    const name = try joinParts(allocator, parts);
    errdefer allocator.free(name);
    for (component.used_props.items) |used| {
        if (std.mem.eql(u8, used.name, name)) return allocator.free(name);
    }
    try component.used_props.append(allocator, .{ .name = name, .node = node });
}

fn finish(
    allocator: Allocator,
    diagnostics: *core.DiagnosticList,
    tree: *const ast.Tree,
    state: *State,
    skip_undeclared: bool,
    ignore: *const core.ReactPropTypesIgnoreNames,
) Allocator.Error!void {
    if (skip_undeclared) return;

    for (state.components.items) |component| {
        if (!component.detected or component.ignore_props_validation) continue;
        for (component.used_props.items) |used| {
            if (ignore.ignoresPath(used.name)) continue;
            if (isDeclared(component.declared_props.items, used.name)) continue;
            try core.addDiagnosticFmt(
                allocator,
                diagnostics,
                .warning,
                id,
                tree.span(used.node),
                "'{s}' is missing in props validation",
                .{used.name},
            );
        }
    }
}

fn isDeclared(props: []const DeclaredProp, full_name: []const u8) bool {
    var iter = std.mem.splitScalar(u8, full_name, '.');
    return isDeclaredParts(props, &iter);
}

fn isDeclaredParts(props: []const DeclaredProp, iter: *std.mem.SplitIterator(u8, .scalar)) bool {
    const part = iter.next() orelse return true;
    for (props) |prop| {
        if (!std.mem.eql(u8, prop.name, part)) continue;
        if (iter.peek() == null) return true;
        if (prop.accepts_any_children) return true;
        return isDeclaredParts(prop.children.items, iter);
    }
    return false;
}

fn memberPropPath(
    tree: *const ast.Tree,
    index: ast.NodeIndex,
    props_name: ?[]const u8,
    buffer: *[max_prop_depth][]const u8,
) ?[]const []const u8 {
    return propSourcePath(tree, index, props_name, buffer);
}

fn propSourcePath(
    tree: *const ast.Tree,
    index: ast.NodeIndex,
    props_name: ?[]const u8,
    buffer: *[max_prop_depth][]const u8,
) ?[]const []const u8 {
    var reversed: [max_prop_depth][]const u8 = undefined;
    var len: usize = 0;
    var current = unwrapTransparent(tree, index);

    while (true) {
        const member = switch (tree.data(current)) {
            .member_expression => |member| member,
            else => break,
        };
        if (len == reversed.len) return null;
        reversed[len] = propertyName(tree, member.property, member.computed) orelse return null;
        len += 1;
        current = unwrapTransparent(tree, member.object);
    }

    if (props_name) |name| {
        if (identifierReferenceName(tree, current)) |identifier| {
            if (std.mem.eql(u8, identifier, name)) {
                reverseInto(buffer, reversed[0..len]);
                return buffer[0..len];
            }
        }
    }

    if (tree.data(current) == .this_expression and len >= 1 and std.mem.eql(u8, reversed[len - 1], "props")) {
        const prop_len = len - 1;
        reverseInto(buffer, reversed[0..prop_len]);
        return buffer[0..prop_len];
    }

    return null;
}

fn reverseInto(buffer: *[max_prop_depth][]const u8, reversed: []const []const u8) void {
    for (reversed, 0..) |_, index| {
        buffer[index] = reversed[reversed.len - 1 - index];
    }
}

fn memberDiagnosticNode(tree: *const ast.Tree, index: ast.NodeIndex) ast.NodeIndex {
    const member = switch (tree.data(unwrapTransparent(tree, index))) {
        .member_expression => |member| member,
        else => return index,
    };
    return member.property;
}

fn propTypesAssignmentTarget(tree: *const ast.Tree, index: ast.NodeIndex) ?struct {
    component: []const u8,
    prop: ?[]const u8 = null,
} {
    const member = switch (tree.data(unwrapTransparent(tree, index))) {
        .member_expression => |member| member,
        else => return null,
    };
    const property = propertyName(tree, member.property, member.computed) orelse return null;
    if (std.mem.eql(u8, property, "propTypes")) {
        const component = componentName(tree, member.object) orelse return null;
        return .{ .component = component };
    }

    const parent = switch (tree.data(unwrapTransparent(tree, member.object))) {
        .member_expression => |parent| parent,
        else => return null,
    };
    const parent_property = propertyName(tree, parent.property, parent.computed) orelse return null;
    if (!std.mem.eql(u8, parent_property, "propTypes")) return null;
    const component = componentName(tree, parent.object) orelse return null;
    return .{ .component = component, .prop = property };
}

fn createClassObject(tree: *const ast.Tree, call: ast.CallExpression) ?ast.ObjectExpression {
    const arguments = tree.extra(call.arguments);
    if (arguments.len == 0) return null;
    return switch (tree.data(unwrapTransparent(tree, arguments[0]))) {
        .object_expression => |object| object,
        else => null,
    };
}

fn wrapperFunctionArgument(tree: *const ast.Tree, symbols: SymbolTable, call: ast.CallExpression) ?ast.NodeIndex {
    if (!isComponentWrapperCall(tree, symbols, call)) return null;
    const arguments = tree.extra(call.arguments);
    if (arguments.len == 0) return null;
    const first = unwrapTransparent(tree, arguments[0]);
    switch (tree.data(first)) {
        .function, .arrow_function_expression => return first,
        .call_expression => |inner| return wrapperFunctionArgument(tree, symbols, inner),
        else => return null,
    }
}

fn isComponentClass(tree: *const ast.Tree, class: ast.Class) bool {
    if (class.super_class != .null and isReactComponentSuper(tree, class.super_class)) return true;
    const body = switch (tree.data(class.body)) {
        .class_body => |body| body,
        else => return false,
    };
    for (tree.extra(body.body)) |member_index| {
        const method = switch (tree.data(member_index)) {
            .method_definition => |method| method,
            else => continue,
        };
        const key = propertyName(tree, method.key, method.computed) orelse continue;
        if (std.mem.eql(u8, key, "render") and functionReturnsJSXOrNull(tree, method.value)) return true;
    }
    return false;
}

fn isReactComponentSuper(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    const current = unwrapTransparent(tree, index);
    if (identifierReferenceName(tree, current)) |name| {
        return std.mem.eql(u8, name, "Component") or std.mem.eql(u8, name, "PureComponent");
    }
    const member = switch (tree.data(current)) {
        .member_expression => |member| member,
        else => return false,
    };
    const property = propertyName(tree, member.property, member.computed) orelse return false;
    return std.mem.eql(u8, property, "Component") or std.mem.eql(u8, property, "PureComponent");
}

fn functionReturnsJSXOrNull(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    return switch (tree.data(unwrapTransparent(tree, index))) {
        .function => |function| function.body != .null and bodyReturnsJSXOrNull(tree, function.body),
        .arrow_function_expression => |arrow| if (arrow.expression)
            isJSXOrNullValue(tree, arrow.body)
        else
            bodyReturnsJSXOrNull(tree, arrow.body),
        else => false,
    };
}

fn bodyReturnsJSXOrNull(tree: *const ast.Tree, body_index: ast.NodeIndex) bool {
    const range = switch (tree.data(body_index)) {
        .function_body => |body| body.body,
        .block_statement => |block| block.body,
        else => return false,
    };
    return rangeReturnsJSXOrNull(tree, range);
}

fn rangeReturnsJSXOrNull(tree: *const ast.Tree, range: ast.IndexRange) bool {
    for (tree.extra(range)) |statement_index| {
        if (statementReturnsJSXOrNull(tree, statement_index)) return true;
    }
    return false;
}

fn statementReturnsJSXOrNull(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    if (index == .null) return false;
    return switch (tree.data(index)) {
        .return_statement => |statement| isJSXOrNullValue(tree, statement.argument),
        .block_statement => |block| rangeReturnsJSXOrNull(tree, block.body),
        .if_statement => |statement| statementReturnsJSXOrNull(tree, statement.consequent) or
            statementReturnsJSXOrNull(tree, statement.alternate),
        .switch_statement => |statement| {
            for (tree.extra(statement.cases)) |case_index| {
                const case = switch (tree.data(case_index)) {
                    .switch_case => |case| case,
                    else => continue,
                };
                if (rangeReturnsJSXOrNull(tree, case.consequent)) return true;
            }
            return false;
        },
        .function,
        .arrow_function_expression,
        => false,
        else => false,
    };
}

fn isJSXOrNullValue(tree: *const ast.Tree, index: ast.NodeIndex) bool {
    if (index == .null) return false;
    return switch (tree.data(unwrapTransparent(tree, index))) {
        .jsx_element,
        .jsx_fragment,
        .null_literal,
        => true,
        .call_expression => |call| isCreateElementCall(tree, call),
        .conditional_expression => |expression| isJSXOrNullValue(tree, expression.consequent) or
            isJSXOrNullValue(tree, expression.alternate),
        .logical_expression => |expression| isJSXOrNullValue(tree, expression.right),
        else => false,
    };
}

fn isCreateElementCall(tree: *const ast.Tree, call: ast.CallExpression) bool {
    const member = switch (tree.data(unwrapTransparent(tree, call.callee))) {
        .member_expression => |member| member,
        else => return false,
    };
    const property = propertyName(tree, member.property, member.computed) orelse return false;
    return std.mem.eql(u8, property, "createElement");
}

fn isCreateReactClassCall(tree: *const ast.Tree, call: ast.CallExpression) bool {
    const callee = unwrapTransparent(tree, call.callee);
    if (identifierReferenceName(tree, callee)) |name| {
        return std.mem.eql(u8, name, "createReactClass");
    }
    const member = switch (tree.data(callee)) {
        .member_expression => |member| member,
        else => return false,
    };
    const property = propertyName(tree, member.property, member.computed) orelse return false;
    return std.mem.eql(u8, property, "createClass");
}

fn isComponentWrapperCall(tree: *const ast.Tree, symbols: SymbolTable, call: ast.CallExpression) bool {
    const context = ReactContext{ .tree = tree, .symbols = symbols };
    return context.isReactApi(call.callee, "memo") or context.isReactApi(call.callee, "forwardRef");
}

fn wrapperPropsType(tree: *const ast.Tree, symbols: SymbolTable, call: ast.CallExpression) ?ast.NodeIndex {
    const context = ReactContext{ .tree = tree, .symbols = symbols };
    if (context.isReactApi(call.callee, "forwardRef")) {
        if (call.type_arguments == .null) return null;
        const arguments = tree.extra(tree.data(call.type_arguments).ts_type_parameter_instantiation.params);
        // The first type argument describes the ref, not the component's props.
        return if (arguments.len > 1) arguments[1] else null;
    }
    if (!context.isReactApi(call.callee, "memo") or call.arguments.len == 0) return null;
    return switch (tree.data(unwrapTransparent(tree, tree.extra(call.arguments)[0]))) {
        .call_expression => |inner| wrapperPropsType(tree, symbols, inner),
        else => null,
    };
}

fn acceptsAnyChildren(name: []const u8) bool {
    return std.mem.eql(u8, name, "any") or
        std.mem.eql(u8, name, "array") or
        std.mem.eql(u8, name, "object");
}

fn propTypeCall(tree: *const ast.Tree, node: ast.NodeIndex) ?ast.CallExpression {
    return switch (tree.data(unwrapTransparent(tree, node))) {
        .call_expression => |call| call,
        else => null,
    };
}

fn stripIsRequired(tree: *const ast.Tree, index: ast.NodeIndex) ast.NodeIndex {
    const member = switch (tree.data(unwrapTransparent(tree, index))) {
        .member_expression => |member| member,
        else => return index,
    };
    const property = propertyName(tree, member.property, member.computed) orelse return index;
    if (!std.mem.eql(u8, property, "isRequired")) return index;
    return member.object;
}

fn propTypeTargetName(tree: *const ast.Tree, node: ast.NodeIndex) ?[]const u8 {
    const current = unwrapTransparent(tree, node);
    const member = switch (tree.data(current)) {
        .member_expression => |member| member,
        else => return identifierReferenceName(tree, current),
    };
    return propertyName(tree, member.property, member.computed);
}

fn paramsContainBinding(tree: *const ast.Tree, params_index: ast.NodeIndex, name: []const u8) bool {
    const params = switch (tree.data(params_index)) {
        .formal_parameters => |params| params,
        else => return false,
    };
    for (tree.extra(params.items)) |item| {
        const pattern = switch (tree.data(item)) {
            .formal_parameter => |param| param.pattern,
            else => item,
        };
        if (patternContainsBinding(tree, pattern, name)) return true;
    }
    if (params.rest != .null and patternContainsBinding(tree, params.rest, name)) return true;
    return false;
}

fn patternContainsBinding(tree: *const ast.Tree, pattern_index: ast.NodeIndex, name: []const u8) bool {
    switch (tree.data(unwrapAssignmentPattern(tree, pattern_index))) {
        .binding_identifier => |identifier| return std.mem.eql(u8, tree.string(identifier.name), name),
        .binding_rest_element => |rest| return patternContainsBinding(tree, rest.argument, name),
        .object_pattern => |pattern| {
            for (tree.extra(pattern.properties)) |property_index| {
                const property = switch (tree.data(property_index)) {
                    .binding_property => |property| property,
                    else => continue,
                };
                if (patternContainsBinding(tree, property.value, name)) return true;
            }
            if (pattern.rest != .null and patternContainsBinding(tree, pattern.rest, name)) return true;
            return false;
        },
        .array_pattern => |pattern| {
            for (tree.extra(pattern.elements)) |element| {
                if (element != .null and patternContainsBinding(tree, element, name)) return true;
            }
            if (pattern.rest != .null and patternContainsBinding(tree, pattern.rest, name)) return true;
            return false;
        },
        else => return false,
    }
}

fn appendNode(allocator: Allocator, list: *std.ArrayList(ast.NodeIndex), node: ast.NodeIndex) Allocator.Error!void {
    for (list.items) |existing| {
        if (existing == node) return;
    }
    try list.append(allocator, node);
}

fn joinParts(allocator: Allocator, parts: []const []const u8) Allocator.Error![]const u8 {
    var len: usize = 0;
    for (parts, 0..) |part, index| {
        len += part.len;
        if (index != 0) len += 1;
    }
    const out = try allocator.alloc(u8, len);
    var offset: usize = 0;
    for (parts, 0..) |part, index| {
        if (index != 0) {
            out[offset] = '.';
            offset += 1;
        }
        @memcpy(out[offset .. offset + part.len], part);
        offset += part.len;
    }
    return out;
}

fn componentName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    return switch (tree.data(unwrapTransparent(tree, index))) {
        .identifier_reference => |identifier| tree.string(identifier.name),
        else => null,
    };
}

fn unwrapAssignmentPattern(tree: *const ast.Tree, index: ast.NodeIndex) ast.NodeIndex {
    const current = unwrapTransparent(tree, index);
    return switch (tree.data(current)) {
        .assignment_pattern => |pattern| unwrapAssignmentPattern(tree, pattern.left),
        else => current,
    };
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

fn propertyName(tree: *const ast.Tree, index: ast.NodeIndex, computed: bool) ?[]const u8 {
    if (index == .null) return null;
    return if (computed)
        switch (tree.data(index)) {
            .string_literal => |literal| tree.string(literal.value),
            else => null,
        }
    else switch (tree.data(index)) {
        .identifier_name => |identifier| tree.string(identifier.name),
        .string_literal => |literal| tree.string(literal.value),
        else => null,
    };
}

fn identifierReferenceName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;
    return switch (tree.data(unwrapTransparent(tree, index))) {
        .identifier_reference => |identifier| tree.string(identifier.name),
        else => null,
    };
}

fn bindingIdentifierName(tree: *const ast.Tree, index: ast.NodeIndex) ?[]const u8 {
    if (index == .null) return null;
    return switch (tree.data(unwrapTransparent(tree, index))) {
        .binding_identifier => |identifier| tree.string(identifier.name),
        else => null,
    };
}

fn startsUppercase(name: []const u8) bool {
    return name.len > 0 and std.ascii.isUpper(name[0]);
}
