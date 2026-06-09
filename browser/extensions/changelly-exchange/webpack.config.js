// @ts-check
const path = require("path");
const MiniCssExtractPlugin = require("mini-css-extract-plugin");
const CopyWebpackPlugin = require("copy-webpack-plugin");

const SRC = path.resolve(__dirname, "src");
const DIST = path.resolve(__dirname, "dist");

/** @type {import('webpack').Configuration} */
module.exports = (env, argv) => {
  const isDev = argv.mode === "development";

  return {
    devtool: isDev ? "inline-source-map" : false,
    entry: {
      popup: path.join(SRC, "popup/index.tsx"),
      "background/index": path.join(SRC, "background/index.ts"),
    },
    output: {
      path: DIST,
      filename: "[name].js",
      clean: true,
    },
    resolve: {
      extensions: [".ts", ".tsx", ".js"],
      alias: {
        "@shared": path.join(SRC, "shared"),
        "@config": path.join(SRC, "config"),
        "@services": path.join(SRC, "services"),
      },
    },
    module: {
      rules: [
        {
          test: /\.tsx?$/,
          use: "ts-loader",
          exclude: /node_modules/,
        },
        {
          test: /\.css$/,
          use: [MiniCssExtractPlugin.loader, "css-loader"],
        },
      ],
    },
    plugins: [
      new MiniCssExtractPlugin({ filename: "styles/[name].css" }),
      new CopyWebpackPlugin({
        patterns: [
          { from: "popup/index.html", to: "popup/index.html" },
          { from: "manifest.json", to: "manifest.json" },
          { from: "src/popup/styles/globals.css", to: "styles/globals.css" },
          {
            from: "_locales",
            to: "_locales",
            noErrorOnMissing: true,
          },
          {
            from: "icons",
            to: "icons",
            noErrorOnMissing: true,
          },
        ],
      }),
    ],
    // Build-time constants injection
    plugins: [
      new MiniCssExtractPlugin({ filename: "styles/[name].css" }),
      new CopyWebpackPlugin({
        patterns: [
          { from: "popup/index.html", to: "popup/index.html" },
          { from: "manifest.json", to: "manifest.json" },
          { from: "src/popup/styles/globals.css", to: "styles/globals.css" },
          { from: "_locales", to: "_locales", noErrorOnMissing: true },
          { from: "icons", to: "icons", noErrorOnMissing: true },
        ],
      }),
      new (require("webpack").DefinePlugin)({
        "__CHANGELLY_ENV__": JSON.stringify(isDev ? "development" : "production"),
        "__PROXY_BASE_URL__": JSON.stringify(
          process.env.PROXY_BASE_URL ?? (isDev ? "http://127.0.0.1:3000" : "https://proxy.w3ai.io")
        ),
        "__PROXY_VERSION__": JSON.stringify("v1"),
      }),
    ],
    optimization: {
      minimize: !isDev,
    },
  };
};
