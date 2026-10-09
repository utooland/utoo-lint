const std = @import("std");
const lint = @import("utoo_lint");
const helpers = @import("../helpers.zig");

const test_options = lint.Options{
    .no_undef = false,
    .no_unused_vars = false,
    .typescript_eslint_no_unused_vars = false,
    .react_jsx_no_undef = false,
};

test "reports button elements without explicit type" {
    const source =
        \\const a = <button />;
        \\const b = <button className="primary" />;
        \\const c = <div />;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", test_options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 2), helpers.countRule(result, lint.rules.react_button_has_type.id));
}

test "reports invalid or complex button type values" {
    const source =
        \\const a = <button type="menu" />;
        \\const b = <button type />;
        \\const c = <button type={kind} />;
        \\const d = <button type={`button-${kind}`} />;
        \\const e = <button type={condition ? "button" : "bad"} />;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", test_options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 5), helpers.countRule(result, lint.rules.react_button_has_type.id));
}

test "allows static valid button type values" {
    const source =
        \\const a = <button type="button" />;
        \\const b = <button type={"submit"} />;
        \\const c = <button type={`reset`} />;
        \\const d = <button type={condition ? "button" : "submit"} />;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", test_options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.react_button_has_type.id));
}

test "decodes entities in JSX button type attributes" {
    const source =
        \\const a = <button type="subm&#105;t" />;
        \\const b = <button type="b&#x75;tton" />;
        \\const c = <button type={"subm&#105;t"} />;
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", test_options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 1), helpers.countRule(result, lint.rules.react_button_has_type.id));
}

test "supports configured react/button-has-type allowed values" {
    var config = try std.json.parseFromSlice(
        std.json.Value,
        std.testing.allocator,
        "[\"error\",{\"button\":true,\"submit\":false,\"reset\":false}]",
        .{},
    );
    defer config.deinit();

    var options = test_options;
    try options.setByRuleConfigValue("react/button-has-type", config.value);

    const source =
        \\const a = <button type="button" />;
        \\const b = <button type="submit" />;
        \\const c = <button type={`reset`} />;
        \\const d = React.createElement("button", { type: "submit" });
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 3), helpers.countRule(result, lint.rules.react_button_has_type.id));
}

test "checks React createElement button calls" {
    const source =
        \\import { createElement } from "react";
        \\const a = React.createElement("button");
        \\const b = React.createElement("button", {});
        \\const c = React.createElement("button", { type: "bad" });
        \\const d = React.createElement("button", { type: kind });
        \\const e = createElement("button", { type: "button" });
        \\const f = createElement("div", {});
    ;

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", test_options);
    defer result.deinit(std.testing.allocator);

    try std.testing.expectEqual(@as(usize, 4), helpers.countRule(result, lint.rules.react_button_has_type.id));
}

test "can disable react button has type" {
    const source = "const node = <button />;";

    var result = try lint.lintSource(std.testing.allocator, source, "fixture.jsx", .{
        .no_undef = false,
        .no_unused_vars = false,
        .typescript_eslint_no_unused_vars = false,
        .react_jsx_no_undef = false,
        .react_button_has_type = false,
    });
    defer result.deinit(std.testing.allocator);

    try std.testing.expect(!helpers.hasRule(result, lint.rules.react_button_has_type.id));
}
