const js = require("@eslint/js");

module.exports = [
  js.configs.recommended,
  {
    files: ["**/*.js"],
    languageOptions: {
      ecmaVersion: 2020,
      sourceType: "commonjs",
      globals: {
        console: "readonly",
        process: "readonly",
        Buffer: "readonly",
        __dirname: "readonly",
        __filename: "readonly",
        global: "readonly",
        module: "readonly",
        require: "readonly",
        exports: "readonly",
      },
    },
    rules: {
      "quotes": ["error", "double"],
      "indent": ["error", 2],
      "max-len": ["error", { "code": 120 }],
      "object-curly-spacing": ["error", "always"],
      "require-jsdoc": "off",
      "valid-jsdoc": "off",
      "no-unused-vars": "warn",
      "no-console": "off",
    },
  },
  {
    ignores: [
      "/lib/**/*",
      "/generated/**/*",
      "node_modules/**/*",
    ],
  },
];