import tseslint from "typescript-eslint";
import { eslintRuleConfig, rulesForProfile } from "./scripts/shared-rules.mjs";

export default [
  {
    ignores: ["node_modules/**", "results/**"]
  },
  {
    files: ["fixtures/**/*.ts"],
    languageOptions: {
      parser: tseslint.parser,
      parserOptions: {
        ecmaVersion: "latest",
        sourceType: "module"
      }
    },
    rules: eslintRuleConfig("error", rulesForProfile())
  }
];
