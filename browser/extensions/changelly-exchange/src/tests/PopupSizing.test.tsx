import { describe, expect, it } from "@jest/globals";
import fs from "node:fs";
import path from "node:path";

describe("Popup sizing baseline", () => {
  it("uses flexible container sizing to avoid sidebar/popup scroll artifacts", () => {
    const cssPath = path.resolve(__dirname, "../popup/styles/globals.css");
    const css = fs.readFileSync(cssPath, "utf8");
    expect(css.includes("width: 100%;")).toBe(true);
    expect(css.includes("height: 100%;")).toBe(true);
    expect(css.includes("overflow: hidden;")).toBe(true);
  });
});
