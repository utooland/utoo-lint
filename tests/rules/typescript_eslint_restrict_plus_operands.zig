const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

test "reports @typescript-eslint/restrict-plus-operands for mixed and invalid primitive operands" {
    const source =
        \\const count: number = 1;
        \\const label: string = "items";
        \\const enabled: boolean = true;
        \\const mystery: unknown = 1;
        \\count + label;
        \\enabled + count;
        \\mystery + count;
        \\1 + "x";
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_unused_expressions = false,
        .typescript_eslint_no_unused_expressions = false,
        .no_unused_vars = false,
        .typescript_eslint_no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), helpers.countRule(result, lint.rules.typescript_eslint_restrict_plus_operands.id));
    for (result.diagnostics) |diagnostic| {
        if (std.mem.eql(u8, diagnostic.rule_id, lint.rules.typescript_eslint_restrict_plus_operands.id)) {
            try std.testing.expectEqual(lint.Severity.warning, diagnostic.severity);
        }
    }
}

test "allows @typescript-eslint/restrict-plus-operands compatible primitive operands" {
    const source =
        \\const left: number = 1;
        \\const right: number = 2;
        \\const first: string = "a";
        \\const second: string = "b";
        \\left + right;
        \\first + second;
        \\(1 as number) + <number>2;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .no_unused_expressions = false,
        .typescript_eslint_no_unused_expressions = false,
        .no_unused_vars = false,
        .typescript_eslint_no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_restrict_plus_operands.id));
}

test "supports configured @typescript-eslint/restrict-plus-operands allowNumberAndString" {
    const source =
        \\const count: number = 1;
        \\const label: string = "items";
        \\const enabled: boolean = true;
        \\const mystery: unknown = 1;
        \\count + label;
        \\enabled + count;
        \\mystery + count;
        \\1 + "x";
    ;

    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"allowNumberAndString\":true}]",
        .{},
    );
    defer config.deinit();

    var options = lint.Options{
        .no_unused_expressions = false,
        .typescript_eslint_no_unused_expressions = false,
        .no_unused_vars = false,
        .typescript_eslint_no_unused_vars = false,
        .parser_semantic_errors = false,
    };
    try options.setByRuleConfigValue("@typescript-eslint/restrict-plus-operands", config.value);

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.typescript_eslint_restrict_plus_operands.id));
}

test "can disable @typescript-eslint/restrict-plus-operands" {
    const source =
        \\const count: number = 1;
        \\const label: string = "items";
        \\count + label;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", .{
        .typescript_eslint_restrict_plus_operands = false,
        .no_unused_expressions = false,
        .typescript_eslint_no_unused_expressions = false,
        .no_unused_vars = false,
        .typescript_eslint_no_unused_vars = false,
        .parser_semantic_errors = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.typescript_eslint_restrict_plus_operands.id));
}

test "explicit any operands respect allowAny" {
    const sources = [_][]const u8{
        "export function example(value: any) { return value + 1; }",
        "export function example(value: any) { return 1 + value; }",
        "export function example(value: any, other) { return value + other; }",
        "const value: any = 1; export const result = value + 1;",
        "export const result = (1 as any) + 1;",
    };
    for ([_][]const u8{ "[\"error\",{\"allowAny\":false}]", "[\"error\",{\"allowAny\":true}]", "error" }) |config_source| {
        const json_source = if (std.mem.eql(u8, config_source, "error")) "\"error\"" else config_source;
        var config = try std.json.parseFromSlice(std.json.Value, std.testing.allocator, json_source, .{});
        defer config.deinit();
        var options = lint.Options.allDisabled();
        try options.setByRuleConfigValue(lint.rules.typescript_eslint_restrict_plus_operands.id, config.value);
        for (sources) |source| {
            var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
            defer result.deinit(std.testing.allocator);
            const count: usize = if (std.mem.indexOf(u8, config_source, "false") != null) 1 else 0;
            try std.testing.expectEqual(count, helpers.countRule(result, lint.rules.typescript_eslint_restrict_plus_operands.id));
        }
    }
}

test "addition operand types follow scoped bindings" {
    var options = lint.Options.allDisabled();
    options.typescript_eslint_restrict_plus_operands = true;
    options.typescript_eslint_restrict_plus_operands_allow_any = false;
    const sources = [_][]const u8{
        "function numeric(value: number) { return value + 1; } function dynamic(value: any) { return value + 1; }",
        "function dynamic(value: any) { return value + 1; } function numeric(value: number) { return value + 1; }",
        "const value: any = 1; function numeric(value: number) { return value + 1; } value + 1;",
        "const value: any = 1; function numeric(value = 0) { return value + 1; } value + 1;",
    };
    for (sources) |source| {
        var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.typescript_eslint_restrict_plus_operands.id));
    }
    options.typescript_eslint_restrict_plus_operands_allow_any = true;
    var result = try lint.lintSource(std.testing.allocator, "(1 as any) + true; false + (1 as any); (1 as any) + 2;", "fixture.ts", options);
    defer result.deinit(std.testing.allocator);
    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.typescript_eslint_restrict_plus_operands.id));
    for (result.diagnostics) |diagnostic| try std.testing.expect(std.mem.indexOf(u8, diagnostic.message, "`boolean`") != null);
}

test "implicit any parameters and any members respect allowAny" {
    const sources = [_][]const u8{
        "export function example(value) { return value + 1; }",
        "export const example = value => value + 1;",
        "export const example = function(value) { return 1 + value; };",
        "export default (value) => value + 1;",
        "export function example(value: unknown) { return (value as any).count + 1; }",
        "export function example(value: any) { return value.nested.count + 1; }",
        "export function example(value: any) { return value['count'] + 1; }",
        "export function example(value: any) { return value?.nested!.count + 1; }",
        "export function example(value = (0 as any)) { return value + 1; }",
        "const value = 0; function example(value) { return value + 1; }",
    };
    for ([_]bool{ false, true }) |allow_any| {
        var options = lint.Options.allDisabled();
        options.typescript_eslint_restrict_plus_operands = true;
        options.typescript_eslint_restrict_plus_operands_allow_any = allow_any;
        for (sources) |source| {
            var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
            defer result.deinit(std.testing.allocator);
            try std.testing.expectEqual(if (allow_any) @as(usize, 0) else @as(usize, 1), helpers.countRule(result, lint.rules.typescript_eslint_restrict_plus_operands.id));
        }
    }
}

test "does not classify inferred and contextual parameters as implicit any" {
    const sources = [_][]const u8{
        "function example(value = 0) { return value + 1; }",
        "function example(value = 'x') { return value + 'y'; }",
        "const example = (value = 0) => value + 1;",
        "const example: (value: number) => number = value => value + 1;",
        "const example: (value: number) => number = function(value) { return value + 1; };",
        "[1, 2].map(value => value + 1);",
        "[1, 2].map(function(value) { return value + 1; });",
        "function example({ value }: { value: number }) { return value + 1; }",
        "function example(value: { count: number }) { return value.count + 1; }",
        "const example: (value: number) => number = (value = (0 as any)) => value + 1;",
        "[1, 2].map((value = (0 as any)) => value + 1);",
        "[1, 2].map(function(value = (0 as any)) { return value + 1; });",
        "function example(value: unknown) { return (value as any as { count: number }).count + 1; }",
        "type Data = { count: number }; function example(value: unknown) { return (value as any as Data).count + 1; }",
        "function example(value: unknown) { return (<{ count: number }><any>value).count + 1; }",
        "function example<T>(value: T) { return value + 1; }",
    };
    var options = lint.Options.allDisabled();
    options.typescript_eslint_restrict_plus_operands = true;
    options.typescript_eslint_restrict_plus_operands_allow_any = false;
    for (sources) |source| {
        var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 0), helpers.countRule(result, lint.rules.typescript_eslint_restrict_plus_operands.id));
    }
}

test "resolves scoped aliases and typed properties for addition" {
    const cases = [_]struct { source: []const u8, count: usize }{
        .{ .source = "type Value=any; function example(a:Value){return a+1;}", .count = 1 },
        .{ .source = "type First=any; type Value=First; function example(a:Value){return a+1;}", .count = 1 },
        .{ .source = "interface Data{value:any} function example(a:Data){return a.value+1;}", .count = 1 },
        .{ .source = "type Data={value:any}; function example(a:Data){return a['value']+1;}", .count = 1 },
        .{ .source = "interface Base{value:any} interface Data extends Base{} function example(a:Data){return a.value+1;}", .count = 1 },
        .{ .source = "interface Data{nested:{value:any}} function example(a:Data){return a.nested.value+1;}", .count = 1 },
        .{ .source = "type Value=any; interface Data{value:Value} function example(a:Data){return a?.value+1;}", .count = 1 },
        .{ .source = "type Value=any; function example(){const a=0 as Value; return a+1;}", .count = 1 },
        .{ .source = "type Value=number; function example(a:Value){return a+1;}", .count = 0 },
        .{ .source = "interface Data{value:number} function example(a:Data){return a.value+1;}", .count = 0 },
        .{ .source = "type Value=any; function example(){type Value=number; const a:Value=0;return a+1;}", .count = 0 },
        .{ .source = "type Value=any; function example<Value extends number>(a:Value){return a+1;}", .count = 0 },
        .{ .source = "interface Data{value:any} function example(){interface Data{value:number} const a:Data={value:0};return a.value+1;}", .count = 0 },
        .{ .source = "type Value=Value; function example(a:Value){return a+1;}", .count = 0 },
    };
    for ([_]bool{ false, true }) |allow_any| {
        var options = lint.Options.allDisabled();
        options.typescript_eslint_restrict_plus_operands = true;
        options.typescript_eslint_restrict_plus_operands_allow_any = allow_any;
        for (cases) |case| {
            var result = try lint.lintSource(std.testing.allocator, case.source, "fixture.ts", options);
            defer result.deinit(std.testing.allocator);
            try std.testing.expectEqual(if (allow_any) @as(usize, 0) else case.count, helpers.countRule(result, lint.rules.typescript_eslint_restrict_plus_operands.id));
        }
    }
}

test "does not infer reassigned variables from stale initializers" {
    const cases = [_][]const u8{
        "let value=null; value=1; value+1;",
        "var value=null; value=1; value+1;",
        "let value=null; [value]=[1]; value+1;",
        "let value=null; function change(){value=1;} change(); value+1;",
    };
    var options = lint.Options.allDisabled();
    options.typescript_eslint_restrict_plus_operands = true;
    options.typescript_eslint_restrict_plus_operands_allow_any = false;
    for (cases) |source| {
        var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 0), helpers.countRule(result, lint.rules.typescript_eslint_restrict_plus_operands.id));
    }
}

test "callbacks to any callees have uncontextualized parameters" {
    const cases = [_]struct { source: []const u8, count: usize }{
        .{ .source = "function example(items:any){return items.map((value,index)=>index+1);}", .count = 1 },
        .{ .source = "function example(items:any){return items['map'](function(value,index){return index+1;});}", .count = 1 },
        .{ .source = "type Dynamic=any; function example(items:Dynamic){return items?.map((value,index)=>index+1);}", .count = 1 },
        .{ .source = "interface Data{map:any} function example(items:Data){return items.map((value,index)=>index+1);}", .count = 1 },
        .{ .source = "function example(fn:any){return fn((value)=>value+1);}", .count = 1 },
        .{ .source = "function example(fn:any){return fn(({value})=>value+1);}", .count = 1 },
        .{ .source = "function example(fn:any){return fn(({data:{value}})=>value+1);}", .count = 1 },
        .{ .source = "function example(fn:any){return fn(([value])=>value+1);}", .count = 1 },
        .{ .source = "function example(fn:any){return fn(({value}:{value:any})=>value+1);}", .count = 1 },
        .{ .source = "function example(fn:any){return fn(({value}:{value:number})=>value+1);}", .count = 0 },
        .{ .source = "function example(fn:any){return fn(({value=0})=>value+1);}", .count = 0 },
        .{ .source = "function example(fn:any){return fn(([value]:number[])=>value+1);}", .count = 0 },
        .{ .source = "function example(items:{value:number}[]){return items.map(({value})=>value+1);}", .count = 0 },

        .{ .source = "const callback:any=(value)=>value+1;", .count = 1 },
        .{ .source = "function example(items:number[]){return items.map((value,index)=>index+1);}", .count = 0 },
        .{ .source = "function example(items:any){return items.map((value,index:number)=>index+1);}", .count = 0 },
        .{ .source = "function example(items:any){return items.map((value,index=0)=>index+1);}", .count = 0 },
        .{ .source = "function example(items:any){return items.map((value,index:number=0 as any)=>index+1);}", .count = 0 },
        .{ .source = "function example(fn:(cb:(value:number)=>number)=>number){return fn(value=>value+1);}", .count = 0 },
        .{ .source = "function example(items:any){function inner(items:number[]){return items.map((value,index)=>index+1);} return inner([]);}", .count = 0 },
    };
    for ([_]bool{ false, true }) |allow_any| {
        var options = lint.Options.allDisabled();
        options.typescript_eslint_restrict_plus_operands = true;
        options.typescript_eslint_restrict_plus_operands_allow_any = allow_any;
        for (cases) |case| {
            var result = try lint.lintSource(std.testing.allocator, case.source, "fixture.ts", options);
            defer result.deinit(std.testing.allocator);
            try std.testing.expectEqual(if (allow_any) @as(usize, 0) else case.count, helpers.countRule(result, lint.rules.typescript_eslint_restrict_plus_operands.id));
        }
    }
}

test "typeof guards narrow operands only on the corresponding live path" {
    const cases = [_]struct { source: []const u8, count: usize }{
        .{ .source = "function example(a:unknown){if(typeof a==='number'){return a+1;}return 0;}", .count = 0 },
        .{ .source = "function example(a:unknown){if(typeof a!=='number')return 0;return a+1;}", .count = 0 },
        .{ .source = "function example(a:unknown){if(typeof a==='string')return a+'x';return '';}", .count = 0 },
        .{ .source = "function example(a:unknown){if('number'===typeof a)return a+1;return 0;}", .count = 0 },
        .{ .source = "function example(a:unknown){if(typeof a!=='number'){}else{return a+1;}return 0;}", .count = 0 },
        .{ .source = "function example(a:unknown){if(typeof a!=='number'){throw new Error();}return a+1;}", .count = 0 },
        .{ .source = "function example(a:unknown){if(!(typeof a==='number'))return 0;return a+1;}", .count = 0 },
        .{ .source = "function example(a:unknown,flag:boolean){if(flag && typeof a==='number')return a+1;return 0;}", .count = 0 },
        .{ .source = "function example(a:unknown,flag:boolean){if(typeof a!=='number'||flag)return 0;return a+1;}", .count = 0 },
        .{ .source = "function example(a:unknown){return typeof a==='number' && a+1;}", .count = 0 },
        .{ .source = "function example(a:unknown){return typeof a==='number' ? a+1 : 0;}", .count = 0 },
        .{ .source = "function example(a:unknown,other:unknown){if(typeof a==='number'){const inner=()=>{a=other;};return a+1;}return 0;}", .count = 0 },
        .{ .source = "function example(a:unknown,other:unknown,flag:boolean){if(typeof a==='number'){while(flag){console.log(a+1);a=other;}}}", .count = 1 },
        .{ .source = "function example(a:unknown,other:unknown,flag:boolean){while(flag){if(typeof a==='number'){console.log(a+1);}a=other;}}", .count = 0 },
        .{ .source = "function example(a:unknown,other:unknown){while(typeof a==='number'){console.log(a+1);a=other;}}", .count = 0 },
        .{ .source = "function example(a:unknown,other:unknown,flag:boolean){if(typeof a==='number'){for(;flag;){console.log(a+1);a=other;}}}", .count = 1 },
        .{ .source = "function example(a:any){a=1;return a+1;}", .count = 1 },
        .{ .source = "function example(a:any){if(typeof a==='number'){a=1;return a+1;}return 0;}", .count = 1 },
        .{ .source = "function example(a:unknown){a=1;return a+1;}", .count = 1 },
        .{ .source = "function example(a:any,values:any[]){if(typeof a==='number'){for(a of values){}return a+1;}return 0;}", .count = 1 },
        .{ .source = "function example(a:any,values:any[]){if(typeof a==='number'){for(a of values){console.log(a+1);}}}", .count = 1 },
        .{ .source = "function example(a:any,values:object){if(typeof a==='number'){for(a in values){}return a+1;}return 0;}", .count = 1 },
        .{ .source = "function example(a:any,values:any[]){for(a of values){if(typeof a==='number')console.log(a+1);}}", .count = 0 },
        .{ .source = "function example(a:unknown){return a+1;}", .count = 1 },
        .{ .source = "function example(a:unknown,b=a+1){if(typeof a!=='number')throw 0;}", .count = 1 },
        .{ .source = "function example(a:unknown){if(typeof a==='number'){}return a+1;}", .count = 1 },
        .{ .source = "function example(a:unknown){if(typeof a==='number')return 0;return a+1;}", .count = 1 },
        .{ .source = "function example(a:unknown,flag:boolean){if(typeof a!=='number'){if(flag)return 0;}return a+1;}", .count = 1 },
        .{ .source = "function example(a:unknown,flag:boolean){if(typeof a==='number'||flag)return a+1;return 0;}", .count = 1 },
        .{ .source = "function example(a:unknown,other:unknown){if(typeof a!=='number')return 0;a=other;return a+1;}", .count = 1 },
        .{ .source = "function example(a:unknown,other:unknown){if(typeof a==='number'){[a]=[other];return a+1;}return 0;}", .count = 1 },
        .{ .source = "function example(a:unknown,other:unknown,flag:boolean){if(typeof a==='number'){while(flag){a=other;}return a+1;}return 0;}", .count = 1 },
        .{ .source = "function example(a:unknown){if(typeof a==='number'){function inner(a:unknown){return a+1;}return inner(a);}return 0;}", .count = 1 },
        .{ .source = "function example(a:unknown){function inner(){if(typeof a!=='number')return 0;}return a+1;}", .count = 1 },
        .{ .source = "function example(a:unknown,other:unknown){if(typeof a==='number' && (a=other,true)){return a+1;}return 0;}", .count = 1 },
    };
    var options = lint.Options.allDisabled();
    options.typescript_eslint_restrict_plus_operands = true;
    options.typescript_eslint_restrict_plus_operands_allow_any = false;
    for (cases) |case| {
        var result = try lint.lintSource(std.testing.allocator, case.source, "fixture.ts", options);
        defer result.deinit(std.testing.allocator);
        const count = helpers.countRule(result, lint.rules.typescript_eslint_restrict_plus_operands.id);
        if (count != case.count) std.debug.print("flow case: {s}\n", .{case.source});
        try std.testing.expectEqual(case.count, count);
    }
}

test "bigint addition accepts matching operands and rejects mixed numeric types" {
    const cases = [_]struct { source: []const u8, count: usize }{
        .{ .source = "export function example(a:bigint,b:bigint){return a+b;}", .count = 0 },
        .{ .source = "export const result=1n+2n+3n;", .count = 0 },
        .{ .source = "export function example(a:bigint,b:number){return a+b;}", .count = 1 },
        .{ .source = "export const result=1+2n;", .count = 1 },
        .{ .source = "export const result=1n+2;", .count = 1 },
        .{ .source = "export const result=1+2;", .count = 0 },
    };
    for ([_]bool{ false, true }) |allow_number_and_string| {
        var options = lint.Options.allDisabled();
        options.typescript_eslint_restrict_plus_operands = true;
        options.typescript_eslint_restrict_plus_operands_allow_number_and_string = allow_number_and_string;
        options.typescript_eslint_restrict_plus_operands_allow_any = false;
        for (cases) |case| {
            var result = try lint.lintSource(std.testing.allocator, case.source, "fixture.ts", options);
            defer result.deinit(std.testing.allocator);
            try std.testing.expectEqual(case.count, helpers.countRule(result, lint.rules.typescript_eslint_restrict_plus_operands.id));
        }
    }
}

test "bigint results do not mask invalid operand diagnostics" {
    var options = lint.Options.allDisabled();
    options.typescript_eslint_restrict_plus_operands = true;
    const cases = [_][]const u8{ "1n + 2n + true;", "true + (1n + 2n);" };
    for (cases) |source| {
        var result = try lint.lintSource(std.testing.allocator, source, "fixture.ts", options);
        defer result.deinit(std.testing.allocator);
        try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.typescript_eslint_restrict_plus_operands.id));
        try std.testing.expect(std.mem.indexOf(u8, result.diagnostics[0].message, "Got `boolean`") != null);
    }
}
