import { isConfigPath, withConfigPath } from "./lib/config-path.cjs";

let globalIgnoreCount = 0;

export function defineConfig(...args) {
  if (args.length === 0) {
    throw new TypeError("Expected one or more arguments.");
  }
  return flattenConfigArgs(args).flatMap((config, index) => expandConfigExtends(config, `UserConfig[${index}]`));
}

export function globalIgnores(ignorePatterns, name) {
  if (!Array.isArray(ignorePatterns)) {
    throw new TypeError("ignorePatterns must be an array");
  }
  if (ignorePatterns.length === 0) {
    throw new TypeError("ignorePatterns must contain at least one pattern");
  }
  const id = globalIgnoreCount++;
  return {
    name: name || `globalIgnores ${id}`,
    ignores: ignorePatterns
  };
}

function flattenConfigArgs(values) {
  const configs = [];
  for (const value of values) {
    if (Array.isArray(value)) {
      configs.push(...flattenConfigArgs(value));
    } else if (typeof value === "object" && value !== null) {
      configs.push(value);
    } else {
      throw new TypeError(`Expected an object but received ${String(value)}.`);
    }
  }
  return configs;
}

function expandConfigExtends(config, baseConfigName) {
  if (!("extends" in config)) {
    return [config];
  }
  if (typeof config.extends !== "string" && !Array.isArray(config.extends)) {
    throw new TypeError("The `extends` property must be a string or an array.");
  }

  const { extends: extensions, ...baseConfig } = config;
  const extendsList = typeof extensions === "string" ? [extensions] : extensions;
  const expanded = [];
  for (const [index, extension] of flattenConfigArgs(resolveConfigExtends(config, extendsList)).entries()) {
    if ("basePath" in extension) {
      throw new TypeError("'basePath' in `extends` is not allowed.");
    }
    if ("extends" in extension) {
      throw new TypeError("Nested 'extends' is not allowed.");
    }
    expanded.push(extendConfig(baseConfig, extension, baseConfigName, extension.name ?? extension.__utooLintConfigName ?? `ExtendedConfig[${index}]`));
  }
  if (!isGlobalIgnores(baseConfig)) {
    expanded.push(baseConfig);
  }
  return expanded;
}

function resolveConfigExtends(config, extendsList) {
  return extendsList.map((extension) => {
    if (typeof extension !== "string") {
      return extension;
    }
    if (isConfigPath(extension)) {
      return withConfigPath(extension, (loaded) => {
        const resolved = flattenConfigArgs([loaded]).flatMap((entry, index) =>
          expandConfigExtends(entry, `${extension}[${index}]`)
        );
        return withConfigNames(resolved, extension);
      });
    }
    const pluginConfig = pluginConfigForName(config, extension);
    if (!pluginConfig) {
      const { namespace, configName } = splitPluginConfigName(extension);
      throw new TypeError(`Plugin config "${configName}" not found in plugin "${namespace}".`);
    }
    return withConfigNames(pluginConfig, extension);
  });
}

function pluginConfigForName(config, name) {
  const { namespace, configName } = splitPluginConfigName(name);
  const plugin = config.plugins?.[namespace];
  if (!plugin) {
    throw new TypeError(`Plugin "${namespace}" not found.`);
  }
  return plugin.configs?.[configName] ?? plugin.configs?.[`flat/${configName}`];
}

function splitPluginConfigName(name) {
  const slashIndex = name.indexOf("/");
  if (slashIndex <= 0 || slashIndex === name.length - 1) {
    throw new TypeError(`Invalid plugin config name "${name}".`);
  }
  return {
    namespace: name.slice(0, slashIndex),
    configName: name.slice(slashIndex + 1)
  };
}

function extendConfig(baseConfig, extension, baseConfigName, extensionName) {
  const { __utooLintConfigName: _name, ...extensionConfig } = extension;
  const result = { ...extensionConfig };
  if (!isGlobalIgnores(extension)) {
    if (baseConfig.files) {
      result.files = extendConfigFiles(baseConfig.files, extension.files);
    }
    if (baseConfig.ignores) {
      result.ignores = baseConfig.ignores.concat(extension.ignores ?? []);
    }
  }
  result.name = `${baseConfig.name ?? baseConfigName} > ${extensionName}`;
  if (baseConfig.basePath) {
    result.basePath = baseConfig.basePath;
  }
  return result;
}

function extendConfigFiles(baseFiles = [], extensionFiles = []) {
  if (!extensionFiles.length) {
    return baseFiles.concat();
  }
  if (!baseFiles.length) {
    return extensionFiles.concat();
  }
  const result = [];
  for (const baseFile of baseFiles) {
    for (const extensionFile of extensionFiles) {
      result.push([
        ...(Array.isArray(baseFile) ? baseFile : [baseFile]),
        ...(Array.isArray(extensionFile) ? extensionFile : [extensionFile])
      ]);
    }
  }
  return result;
}

function isGlobalIgnores(config) {
  const keys = Object.keys(config);
  return keys.includes("ignores") && keys.every((key) => key === "name" || key === "ignores" || key === "__utooLintConfigName");
}

function withConfigNames(config, name) {
  if (Array.isArray(config)) {
    return config.map((entry, index) => ({
      ...entry,
      __utooLintConfigName: `${name}[${index}]`
    }));
  }
  return {
    ...config,
    __utooLintConfigName: name
  };
}
