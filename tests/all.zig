comptime {
    _ = @import("autofix.zig");
}

comptime {
    _ = @import("flat_config");
}

comptime {
    _ = @import("suppressions.zig");
}

comptime {
    _ = @import("frontend_preset.zig");
}

comptime {
    _ = @import("rules/accessor_pairs.zig");
}

comptime {
    _ = @import("rules/array_callback_return.zig");
}

comptime {
    _ = @import("rules/arrow_body_style.zig");
}

comptime {
    _ = @import("rules/block_scoped_var.zig");
}

comptime {
    _ = @import("rules/camelcase.zig");
}

comptime {
    _ = @import("rules/capitalized_comments.zig");
}

comptime {
    _ = @import("rules/class_methods_use_this.zig");
}

comptime {
    _ = @import("rules/complexity.zig");
}

comptime {
    _ = @import("rules/consistent_return.zig");
}

comptime {
    _ = @import("rules/consistent_this.zig");
}

comptime {
    _ = @import("rules/constructor_super.zig");
}

comptime {
    _ = @import("rules/curly.zig");
}

comptime {
    _ = @import("rules/dot_notation.zig");
}

comptime {
    _ = @import("rules/default_case.zig");
}

comptime {
    _ = @import("rules/default_case_last.zig");
}

comptime {
    _ = @import("rules/default_param_last.zig");
}

comptime {
    _ = @import("rules/eol_last.zig");
}

comptime {
    _ = @import("rules/eslint_comments_no_restricted_disable.zig");
}

comptime {
    _ = @import("rules/for_direction.zig");
}

comptime {
    _ = @import("rules/func_names.zig");
}

comptime {
    _ = @import("rules/func_name_matching.zig");
}

comptime {
    _ = @import("rules/func_style.zig");
}

comptime {
    _ = @import("rules/getter_return.zig");
}

comptime {
    _ = @import("rules/grouped_accessor_pairs.zig");
}

comptime {
    _ = @import("rules/guard_for_in.zig");
}

comptime {
    _ = @import("rules/id_denylist.zig");
}

comptime {
    _ = @import("rules/id_length.zig");
}

comptime {
    _ = @import("rules/id_match.zig");
}

comptime {
    _ = @import("rules/init_declarations.zig");
}

comptime {
    _ = @import("rules/alipay_ant_disallow_typos.zig");
}

comptime {
    _ = @import("rules/alipay_ant_exhaustive_deps.zig");
}

comptime {
    _ = @import("rules/alipay_ant_no_import_src.zig");
}

comptime {
    _ = @import("rules/alipay_ant_jsx_handler_names.zig");
}

comptime {
    _ = @import("rules/alipay_ant_no_deprecated_variable.zig");
}

comptime {
    _ = @import("rules/alipay_ant_no_import_files_from_pages_in_common.zig");
}

comptime {
    _ = @import("rules/alipay_ant_no_negative_conditionals.zig");
}

comptime {
    _ = @import("rules/alipay_ant_no_too_large_file.zig");
}

comptime {
    _ = @import("rules/alipay_ant_prefer_elseif_end_with_else.zig");
}

comptime {
    _ = @import("rules/alipay_ant_prefer_catch_unsafe_func_call.zig");
}

comptime {
    _ = @import("rules/alipay_ant_no_spread_params.zig");
}

comptime {
    _ = @import("rules/alipay_ant_prefer_import_from_stdlib.zig");
}

comptime {
    _ = @import("rules/alipay_ant_prefer_import_as_required.zig");
}

comptime {
    _ = @import("rules/alipay_ant_prefer_managed_resource.zig");
}

comptime {
    _ = @import("rules/alipay_ant_prefer_safe_image_renderer.zig");
}

comptime {
    _ = @import("rules/alipay_ant_no_deprecated_dependence.zig");
}

comptime {
    _ = @import("rules/alipay_ant_prefer_click_with_debounce.zig");
}

comptime {
    _ = @import("rules/alipay_spmlint_use_labeled_spm.zig");
}

comptime {
    _ = @import("rules/alipay_spmlint_valid_manual_click.zig");
}

comptime {
    _ = @import("rules/alipay_spmlint_valid_manual_expo.zig");
}

comptime {
    _ = @import("rules/alipay_spmlint_valid_manual_param.zig");
}

comptime {
    _ = @import("rules/alipay_spmlint_valid_manual_pv.zig");
}

comptime {
    _ = @import("rules/import_default.zig");
}

comptime {
    _ = @import("rules/import_export.zig");
}

comptime {
    _ = @import("rules/import_first.zig");
}

comptime {
    _ = @import("rules/import_named.zig");
}

comptime {
    _ = @import("rules/import_namespace.zig");
}

comptime {
    _ = @import("rules/import_newline_after_import.zig");
}

comptime {
    _ = @import("rules/import_no_amd.zig");
}

comptime {
    _ = @import("rules/import_no_cycle.zig");
}

comptime {
    _ = @import("rules/import_no_duplicates.zig");
}

comptime {
    _ = @import("rules/import_no_named_as_default.zig");
}

comptime {
    _ = @import("rules/import_no_named_as_default_member.zig");
}

comptime {
    _ = @import("rules/import_no_unresolved.zig");
}

comptime {
    _ = @import("rules/import_no_self_import.zig");
}

comptime {
    _ = @import("rules/jest_no_conditional_expect.zig");
    _ = @import("rules/jest_no_deprecated_functions.zig");
    _ = @import("rules/jest_no_export.zig");
    _ = @import("rules/jest_no_focused_tests.zig");
    _ = @import("rules/jest_no_identical_title.zig");
    _ = @import("rules/jest_no_interpolation_in_snapshots.zig");
    _ = @import("rules/jest_no_jasmine_globals.zig");
    _ = @import("rules/jest_no_mocks_import.zig");
    _ = @import("rules/jest_no_standalone_expect.zig");
    _ = @import("rules/jest_valid_describe_callback.zig");
    _ = @import("rules/jest_valid_expect_in_promise.zig");
    _ = @import("rules/jest_valid_expect.zig");
    _ = @import("rules/jest_valid_title.zig");
}

comptime {
    _ = @import("rules/jsx_a11y_alt_text.zig");
}

comptime {
    _ = @import("rules/jsx_a11y_anchor_has_content.zig");
}

comptime {
    _ = @import("rules/jsx_a11y_aria_props.zig");
}

comptime {
    _ = @import("rules/jsx_a11y_aria_proptypes.zig");
}

comptime {
    _ = @import("rules/jsx_a11y_aria_role.zig");
}

comptime {
    _ = @import("rules/jsx_a11y_aria_unsupported_elements.zig");
}

comptime {
    _ = @import("rules/jsx_a11y_iframe_has_title.zig");
}

comptime {
    _ = @import("rules/jsx_a11y_img_redundant_alt.zig");
}

comptime {
    _ = @import("rules/jsx_a11y_no_access_key.zig");
}

comptime {
    _ = @import("rules/jsx_a11y_no_distracting_elements.zig");
}

comptime {
    _ = @import("rules/jsx_a11y_role_has_required_aria_props.zig");
}

comptime {
    _ = @import("rules/jsx_a11y_role_supports_aria_props.zig");
}

comptime {
    _ = @import("rules/jsx_a11y_scope.zig");
}

comptime {
    _ = @import("rules/linebreak_style.zig");
}

comptime {
    _ = @import("rules/logical_assignment_operators.zig");
}

comptime {
    _ = @import("rules/max_classes_per_file.zig");
}

comptime {
    _ = @import("rules/max_depth.zig");
}

comptime {
    _ = @import("rules/max_lines.zig");
}

comptime {
    _ = @import("rules/max_lines_per_function.zig");
}

comptime {
    _ = @import("rules/max_nested_callbacks.zig");
}

comptime {
    _ = @import("rules/max_params.zig");
}

comptime {
    _ = @import("rules/max_statements.zig");
}

comptime {
    _ = @import("rules/new_cap.zig");
}

comptime {
    _ = @import("rules/new_parens.zig");
}

comptime {
    _ = @import("rules/eqeqeq.zig");
}

comptime {
    _ = @import("rules/no_alert.zig");
}

comptime {
    _ = @import("rules/no_async_promise_executor.zig");
}

comptime {
    _ = @import("rules/no_await_in_loop.zig");
}

comptime {
    _ = @import("rules/no_bitwise.zig");
}

comptime {
    _ = @import("rules/no_buffer_constructor.zig");
}

comptime {
    _ = @import("rules/no_array_constructor.zig");
}

comptime {
    _ = @import("rules/no_caller.zig");
}

comptime {
    _ = @import("rules/no_case_declarations.zig");
}

comptime {
    _ = @import("rules/no_class_assign.zig");
}

comptime {
    _ = @import("rules/no_confusing_arrow.zig");
}

comptime {
    _ = @import("rules/no_comma_operator.zig");
}

comptime {
    _ = @import("rules/no_cond_assign.zig");
}

comptime {
    _ = @import("rules/no_console.zig");
}

comptime {
    _ = @import("rules/no_continue.zig");
}

comptime {
    _ = @import("rules/no_constructor_return.zig");
}

comptime {
    _ = @import("rules/no_const_assign.zig");
}

comptime {
    _ = @import("rules/no_constant_binary_expression.zig");
}

comptime {
    _ = @import("rules/no_constant_condition.zig");
}

comptime {
    _ = @import("rules/no_control_regex.zig");
}

comptime {
    _ = @import("rules/no_compare_neg_zero.zig");
}

comptime {
    _ = @import("rules/no_debugger.zig");
}

comptime {
    _ = @import("rules/no_delete_var.zig");
}

comptime {
    _ = @import("rules/no_div_regex.zig");
}

comptime {
    _ = @import("rules/no_duplicate_case.zig");
}

comptime {
    _ = @import("rules/no_dupe_args.zig");
}

comptime {
    _ = @import("rules/no_dupe_class_members.zig");
}

comptime {
    _ = @import("rules/no_dupe_else_if.zig");
}

comptime {
    _ = @import("rules/no_dupe_keys.zig");
}

comptime {
    _ = @import("rules/no_duplicate_imports.zig");
}

comptime {
    _ = @import("rules/no_empty.zig");
}

comptime {
    _ = @import("rules/no_empty_block_statements.zig");
}

comptime {
    _ = @import("rules/no_empty_character_class.zig");
}

comptime {
    _ = @import("rules/no_empty_function.zig");
}

comptime {
    _ = @import("rules/no_empty_pattern.zig");
}

comptime {
    _ = @import("rules/no_empty_static_block.zig");
}

comptime {
    _ = @import("rules/no_else_return.zig");
}

comptime {
    _ = @import("rules/no_eval.zig");
}

comptime {
    _ = @import("rules/no_eq_null.zig");
}

comptime {
    _ = @import("rules/no_ex_assign.zig");
}

comptime {
    _ = @import("rules/no_extend_native.zig");
}

comptime {
    _ = @import("rules/no_extra_bind.zig");
}

comptime {
    _ = @import("rules/no_extra_label.zig");
}

comptime {
    _ = @import("rules/no_extra_boolean_cast.zig");
}

comptime {
    _ = @import("rules/no_extra_semi.zig");
}

comptime {
    _ = @import("rules/no_floating_decimal.zig");
}

comptime {
    _ = @import("rules/no_fallthrough.zig");
}

comptime {
    _ = @import("rules/no_for_in.zig");
}

comptime {
    _ = @import("rules/no_func_assign.zig");
}

comptime {
    _ = @import("rules/no_global_assign.zig");
}

comptime {
    _ = @import("rules/no_global_is_finite.zig");
}

comptime {
    _ = @import("rules/no_global_is_nan.zig");
}

comptime {
    _ = @import("rules/no_implicit_coercion.zig");
}

comptime {
    _ = @import("rules/no_implicit_globals.zig");
}

comptime {
    _ = @import("rules/no_implied_eval.zig");
}

comptime {
    _ = @import("rules/no_import_assign.zig");
}

comptime {
    _ = @import("rules/no_inline_comments.zig");
}

comptime {
    _ = @import("rules/no_inner_declarations.zig");
}

comptime {
    _ = @import("rules/no_invalid_regexp.zig");
}

comptime {
    _ = @import("rules/no_invalid_this.zig");
}

comptime {
    _ = @import("rules/no_irregular_whitespace.zig");
}

comptime {
    _ = @import("rules/no_iterator.zig");
}

comptime {
    _ = @import("rules/no_label_var.zig");
}

comptime {
    _ = @import("rules/no_labels.zig");
}

comptime {
    _ = @import("rules/no_lone_blocks.zig");
}

comptime {
    _ = @import("rules/no_lonely_if.zig");
}

comptime {
    _ = @import("rules/no_loss_of_precision.zig");
}

comptime {
    _ = @import("rules/no_magic_numbers.zig");
}

comptime {
    _ = @import("rules/no_mixed_spaces_and_tabs.zig");
}

comptime {
    _ = @import("rules/no_misleading_character_class.zig");
}

comptime {
    _ = @import("rules/no_multi_assign.zig");
}

comptime {
    _ = @import("rules/no_multi_str.zig");
}

comptime {
    _ = @import("rules/no_multi_spaces.zig");
}

comptime {
    _ = @import("rules/no_multiple_empty_lines.zig");
}

comptime {
    _ = @import("rules/no_nonoctal_decimal_escape.zig");
}

comptime {
    _ = @import("rules/no_negated_condition.zig");
}

comptime {
    _ = @import("rules/no_new.zig");
}

comptime {
    _ = @import("rules/no_nested_ternary.zig");
}

comptime {
    _ = @import("rules/no_new_native_nonconstructor.zig");
}

comptime {
    _ = @import("rules/no_obj_calls.zig");
}

comptime {
    _ = @import("rules/no_new_func.zig");
}

comptime {
    _ = @import("rules/no_new_require.zig");
}

comptime {
    _ = @import("rules/no_new_object.zig");
}

comptime {
    _ = @import("rules/no_new_symbol.zig");
}

comptime {
    _ = @import("rules/no_new_wrappers.zig");
}

comptime {
    _ = @import("rules/no_octal.zig");
}

comptime {
    _ = @import("rules/no_octal_escape.zig");
}

comptime {
    _ = @import("rules/no_object_constructor.zig");
}

comptime {
    _ = @import("rules/no_param_reassign.zig");
}

comptime {
    _ = @import("rules/no_path_concat.zig");
}

comptime {
    _ = @import("rules/no_plusplus.zig");
}

comptime {
    _ = @import("rules/no_promise_executor_return.zig");
}

comptime {
    _ = @import("rules/no_proto.zig");
}

comptime {
    _ = @import("rules/no_process_env.zig");
}

comptime {
    _ = @import("rules/no_process_exit.zig");
}

comptime {
    _ = @import("rules/no_prototype_builtins.zig");
}

comptime {
    _ = @import("rules/no_redeclare.zig");
}

comptime {
    _ = @import("rules/no_restricted_exports.zig");
}

comptime {
    _ = @import("rules/no_restricted_globals.zig");
}

comptime {
    _ = @import("rules/no_restricted_imports.zig");
}

comptime {
    _ = @import("rules/no_restricted_modules.zig");
}

comptime {
    _ = @import("rules/no_restricted_properties.zig");
}

comptime {
    _ = @import("rules/no_restricted_syntax.zig");
}

comptime {
    _ = @import("rules/no_regex_spaces.zig");
}

comptime {
    _ = @import("rules/no_return_await.zig");
}

comptime {
    _ = @import("rules/no_return_assign.zig");
}

comptime {
    _ = @import("rules/no_useless_return.zig");
}

comptime {
    _ = @import("rules/no_script_url.zig");
}

comptime {
    _ = @import("rules/no_self_assign.zig");
}

comptime {
    _ = @import("rules/no_self_compare.zig");
}

comptime {
    _ = @import("rules/no_setter_return.zig");
}

comptime {
    _ = @import("rules/no_shadow.zig");
}

comptime {
    _ = @import("rules/no_loop_func.zig");
}

comptime {
    _ = @import("rules/no_sequences.zig");
}

comptime {
    _ = @import("rules/no_sparse_arrays.zig");
}

comptime {
    _ = @import("rules/no_tabs.zig");
}

comptime {
    _ = @import("rules/no_ternary.zig");
}

comptime {
    _ = @import("rules/no_template_curly_in_string.zig");
}

comptime {
    _ = @import("rules/no_throw_literal.zig");
}

comptime {
    _ = @import("rules/no_this_before_super.zig");
}

comptime {
    _ = @import("rules/no_trailing_spaces.zig");
}

comptime {
    _ = @import("rules/no_unreachable.zig");
}

comptime {
    _ = @import("rules/no_unreachable_loop.zig");
}

comptime {
    _ = @import("rules/no_undef_init.zig");
}

comptime {
    _ = @import("rules/no_underscore_dangle.zig");
}

comptime {
    _ = @import("rules/no_undefined.zig");
}

comptime {
    _ = @import("rules/no_shadow_restricted_names.zig");
}

comptime {
    _ = @import("rules/no_unneeded_ternary.zig");
}

comptime {
    _ = @import("rules/no_unexpected_multiline.zig");
}

comptime {
    _ = @import("rules/no_unmodified_loop_condition.zig");
}

comptime {
    _ = @import("rules/no_unused_labels.zig");
}

comptime {
    _ = @import("rules/no_unsafe_finally.zig");
}

comptime {
    _ = @import("rules/no_unsafe_negation.zig");
}

comptime {
    _ = @import("rules/no_unsafe_optional_chaining.zig");
}

comptime {
    _ = @import("rules/no_useless_computed_key.zig");
}

comptime {
    _ = @import("rules/no_useless_backreference.zig");
}

comptime {
    _ = @import("rules/no_useless_call.zig");
}

comptime {
    _ = @import("rules/no_useless_concat.zig");
}

comptime {
    _ = @import("rules/no_useless_constructor.zig");
}

comptime {
    _ = @import("rules/no_useless_assignment.zig");
}

comptime {
    _ = @import("rules/no_useless_catch.zig");
}

comptime {
    _ = @import("rules/no_useless_escape.zig");
}

comptime {
    _ = @import("rules/no_useless_rename.zig");
}

comptime {
    _ = @import("rules/no_unused_expressions.zig");
}

comptime {
    _ = @import("rules/no_unused_private_class_members.zig");
}

comptime {
    _ = @import("rules/no_unused_vars.zig");
}

comptime {
    _ = @import("rules/no_use_before_define.zig");
}

comptime {
    _ = @import("rules/no_undef.zig");
}

comptime {
    _ = @import("rules/no_unassigned_vars.zig");
}

comptime {
    _ = @import("rules/no_warning_comments.zig");
}

comptime {
    _ = @import("rules/no_var.zig");
}

comptime {
    _ = @import("rules/no_void.zig");
}

comptime {
    _ = @import("rules/no_with.zig");
}

comptime {
    _ = @import("rules/object_shorthand.zig");
}

comptime {
    _ = @import("rules/one_var.zig");
}

comptime {
    _ = @import("rules/operator_assignment.zig");
}

comptime {
    _ = @import("rules/sort_imports.zig");
}

comptime {
    _ = @import("rules/sort_keys.zig");
}

comptime {
    _ = @import("rules/sort_vars.zig");
}

comptime {
    _ = @import("rules/prefer_arrow_callback.zig");
}

comptime {
    _ = @import("rules/prefer_const.zig");
}

comptime {
    _ = @import("rules/prefer_destructuring.zig");
}

comptime {
    _ = @import("rules/prefer_exponentiation_operator.zig");
}

comptime {
    _ = @import("rules/prefer_named_capture_group.zig");
}

comptime {
    _ = @import("rules/prefer_numeric_literals.zig");
}

comptime {
    _ = @import("rules/prefer_object_has_own.zig");
}

comptime {
    _ = @import("rules/prefer_object_spread.zig");
}

comptime {
    _ = @import("rules/prefer_promise_reject_errors.zig");
    _ = @import("rules/promise_valid_params.zig");
}

comptime {
    _ = @import("rules/promise_no_return_wrap.zig");
}

comptime {
    _ = @import("rules/promise_no_promise_in_callback.zig");
}

comptime {
    _ = @import("rules/promise_always_return.zig");
}

comptime {
    _ = @import("rules/promise_catch_or_return.zig");
}

comptime {
    _ = @import("rules/promise_no_callback_in_promise.zig");
}

comptime {
    _ = @import("rules/promise_no_nesting.zig");
}

comptime {
    _ = @import("rules/promise_no_new_statics.zig");
}

comptime {
    _ = @import("rules/promise_no_return_in_finally.zig");
}

comptime {
    _ = @import("rules/promise_param_names.zig");
}

comptime {
    _ = @import("rules/preserve_caught_error.zig");
}

comptime {
    _ = @import("rules/prefer_regex_literals.zig");
}

comptime {
    _ = @import("rules/prefer_rest_params.zig");
}

comptime {
    _ = @import("rules/prefer_spread.zig");
}

comptime {
    _ = @import("rules/prefer_template.zig");
}

comptime {
    _ = @import("rules/radix.zig");
}

comptime {
    _ = @import("rules/require_unicode_regexp.zig");
}

comptime {
    _ = @import("rules/react_no_danger.zig");
}

comptime {
    _ = @import("rules/react_no_danger_with_children.zig");
}

comptime {
    _ = @import("rules/react_display_name.zig");
}

comptime {
    _ = @import("rules/react_jsx_filename_extension.zig");
}

comptime {
    _ = @import("rules/react_no_access_state_in_setstate.zig");
}

comptime {
    _ = @import("rules/react_no_direct_mutation_state.zig");
}

comptime {
    _ = @import("rules/react_no_deprecated.zig");
}

comptime {
    _ = @import("rules/react_forbid_prop_types.zig");
}

comptime {
    _ = @import("rules/react_no_children_prop.zig");
}

comptime {
    _ = @import("rules/react_no_array_index_key.zig");
}

comptime {
    _ = @import("rules/react_no_find_dom_node.zig");
    _ = @import("rules/react_no_forward_ref.zig");
}

comptime {
    _ = @import("rules/react_no_is_mounted.zig");
}

comptime {
    _ = @import("rules/react_no_render_return_value.zig");
}

comptime {
    _ = @import("rules/react_no_this_in_sfc.zig");
}

comptime {
    _ = @import("rules/react_no_typos.zig");
}

comptime {
    _ = @import("rules/react_no_unknown_property.zig");
}

comptime {
    _ = @import("rules/react_prop_types.zig");
}

comptime {
    _ = @import("rules/react_no_unused_prop_types.zig");
}

comptime {
    _ = @import("rules/react_no_unused_state.zig");
}

comptime {
    _ = @import("rules/react_no_redundant_should_component_update.zig");
}

comptime {
    _ = @import("rules/react_no_multi_comp.zig");
    _ = @import("rules/react_no_unstable_nested_components.zig");
}

comptime {
    _ = @import("rules/react_no_string_refs.zig");
}

comptime {
    _ = @import("rules/react_no_unescaped_entities.zig");
}

comptime {
    _ = @import("rules/react_no_will_update_set_state.zig");
}

comptime {
    _ = @import("rules/react_jsx_boolean_value.zig");
}

comptime {
    _ = @import("rules/react_jsx_no_duplicate_props.zig");
}

comptime {
    _ = @import("rules/react_jsx_no_target_blank.zig");
}

comptime {
    _ = @import("rules/react_jsx_no_undef.zig");
}

comptime {
    _ = @import("rules/react_jsx_no_comment_textnodes.zig");
}

comptime {
    _ = @import("rules/react_jsx_no_bind.zig");
}

comptime {
    _ = @import("rules/react_jsx_key.zig");
}

comptime {
    _ = @import("rules/react_button_has_type.zig");
}

comptime {
    _ = @import("rules/react_default_props_match_prop_types.zig");
}

comptime {
    _ = @import("rules/react_require_render_return.zig");
}

comptime {
    _ = @import("rules/react_jsx_pascal_case.zig");
}

comptime {
    _ = @import("rules/react_jsx_uses_react.zig");
}

comptime {
    _ = @import("rules/react_jsx_uses_vars.zig");
}

comptime {
    _ = @import("rules/react_prefer_es6_class.zig");
}

comptime {
    _ = @import("rules/react_self_closing_comp.zig");
}

comptime {
    _ = @import("rules/react_style_prop_object.zig");
}

comptime {
    _ = @import("rules/react_void_dom_elements_no_children.zig");
}

comptime {
    _ = @import("rules/react_hooks_exhaustive_deps.zig");
}

comptime {
    _ = @import("rules/react_hooks_rules_of_hooks.zig");
    _ = @import("rules/react_hooks_use_memo.zig");
    _ = @import("rules/react_hooks_void_use_memo.zig");
}

comptime {
    _ = @import("rules/require_await.zig");
}

comptime {
    _ = @import("rules/require_atomic_updates.zig");
}

comptime {
    _ = @import("rules/require_yield.zig");
}

comptime {
    _ = @import("rules/spaced_comment.zig");
}

comptime {
    _ = @import("rules/strict.zig");
}

comptime {
    _ = @import("rules/symbol_description.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_adjacent_overload_signatures.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_array_type.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_class_literal_property_style.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_consistent_type_assertions.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_consistent_type_definitions.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_dot_notation.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_explicit_member_accessibility.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_method_signature_style.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_array_constructor.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_ban_types.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_ban_ts_comment.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_ban_tslint_comment.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_member_ordering.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_confusing_non_null_assertion.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_dupe_class_members.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_duplicate_enum_values.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_empty_function.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_empty_interface.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_empty_object_type.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_extra_semi.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_extra_non_null_assertion.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_inferrable_types.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_invalid_void_type.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_loss_of_precision.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_misused_new.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_namespace.zig");
    _ = @import("rules/typescript_eslint_no_explicit_any.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_non_null_asserted_optional_chain.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_redeclare.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_require_imports.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_shadow.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_this_alias.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_unsafe_declaration_merging.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_unsafe_function_type.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_triple_slash_reference.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_typedef.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_unified_signatures.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_unnecessary_parameter_property_assignment.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_unnecessary_type_constraint.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_useless_constructor.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_useless_empty_export.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_unused_expressions.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_loop_func.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_unused_vars.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_use_before_define.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_var_requires.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_no_wrapper_object_types.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_prefer_as_const.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_prefer_namespace_keyword.zig");
}

comptime {
    _ = @import("rules/typescript_eslint_restrict_plus_operands.zig");
}

comptime {
    _ = @import("rules/unused_imports_no_unused_imports.zig");
}

comptime {
    _ = @import("rules/unicode_bom.zig");
}

comptime {
    _ = @import("rules/use_isnan.zig");
}

comptime {
    _ = @import("rules/valid_typeof.zig");
}

comptime {
    _ = @import("rules/vars_on_top.zig");
}

comptime {
    _ = @import("rules/wrap_iife.zig");
}

comptime {
    _ = @import("rules/yoda.zig");
}
