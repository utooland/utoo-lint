import { rulesForProfile } from "./scripts/shared-rules.mjs";

export default {
  files: ["fixtures/**/*.ts"],
  rules: Object.fromEntries(rulesForProfile().map((rule) => [rule.name, "error"]))
};
