/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/**
 * Content actor that extracts a site's dominant color palette from the active
 * web page and returns a normalized { primary, accent, background, surface,
 * text, mode } object for use by the Adaptive BrandSkin engine.
 *
 * Layer 1 — CSS design tokens on :root (:root CSS custom properties)
 * Layer 2 — Computed styles on body / nav / header / primary buttons
 */
export class PageColorChild extends JSWindowActorChild {
  receiveMessage(message) {
    if (message.name === "PageColor:Extract") {
      return this.#extractColors();
    }
    return undefined;
  }

  #extractColors() {
    try {
      const win = this.contentWindow;
      const doc = win.document;
      const rootStyle = win.getComputedStyle(doc.documentElement);

      // Layer 1: CSS design tokens
      const cssVarPrimary = this.#readCSSVars(rootStyle, [
        "--primary",
        "--color-primary",
        "--brand-primary",
        "--theme-primary",
        "--brand-color",
        "--main-color",
      ]);
      const cssVarAccent = this.#readCSSVars(rootStyle, [
        "--accent",
        "--color-accent",
        "--secondary",
        "--color-secondary",
        "--highlight",
        "--color-highlight",
      ]);
      const cssVarBg = this.#readCSSVars(rootStyle, [
        "--background",
        "--background-color",
        "--bg",
        "--bg-color",
        "--color-background",
        "--surface-bg",
        "--page-background",
        "--color-base-background",
      ]);

      // Layer 2: DOM element computed styles
      const bodyStyle = doc.body
        ? win.getComputedStyle(doc.body)
        : null;
      const navEl = doc.querySelector(
        "nav, header, [role='banner'], .navbar, .nav-bar, #header, #nav"
      );
      const btnEl = doc.querySelector(
        "button[type='submit'], .btn-primary, .button-primary, a.primary"
      );
      const navBg = navEl
        ? win.getComputedStyle(navEl).backgroundColor
        : null;
      const btnBg = btnEl
        ? win.getComputedStyle(btnEl).backgroundColor
        : null;
      const bodyBg = bodyStyle?.backgroundColor;

      const rawPrimary = cssVarPrimary || btnBg || navBg;
      const rawBg = cssVarBg || bodyBg;

      if (!rawPrimary && !rawBg) {
        return null;
      }

      const primaryRgb = this.#parseColor(rawPrimary);
      const bgRgb = this.#parseColor(rawBg);

      if (!primaryRgb && !bgRgb) {
        return null;
      }

      const mode =
        bgRgb ? (this.#luminance(bgRgb) < 0.35 ? "dark" : "light") : "dark";
      const accentRgb =
        this.#parseColor(cssVarAccent) || primaryRgb;
      const surfaceRgb = bgRgb
        ? this.#shiftLightness(bgRgb, mode === "dark" ? 0.06 : -0.06)
        : null;

      const candidateText = mode === "dark" ? "#FFFFFF" : "#0D0D0D";
      const textHex =
        bgRgb &&
        this.#contrastRatio(this.#hexToRgb(candidateText), bgRgb) < 4.5
          ? mode === "dark"
            ? "#F0F0F0"
            : "#000000"
          : candidateText;

      return {
        primary: primaryRgb ? this.#toHex(primaryRgb) : null,
        accent: accentRgb ? this.#toHex(accentRgb) : null,
        background: bgRgb ? this.#toHex(bgRgb) : null,
        surface: surfaceRgb ? this.#toHex(surfaceRgb) : null,
        text: textHex,
        mode,
      };
    } catch {
      return null;
    }
  }

  #readCSSVars(style, names) {
    for (const name of names) {
      const val = style.getPropertyValue(name)?.trim();
      if (val && val !== "none" && val !== "initial" && val !== "inherit") {
        return val;
      }
    }
    return null;
  }

  #parseColor(str) {
    if (!str) {
      return null;
    }
    str = str.trim();
    const m = str.match(/^rgba?\(\s*(\d+)\s*,\s*(\d+)\s*,\s*(\d+)/);
    if (m) {
      const r = parseInt(m[1]);
      const g = parseInt(m[2]);
      const b = parseInt(m[3]);
      // Skip transparent-looking or pure default values
      if ((r === 0 && g === 0 && b === 0) || (r === 255 && g === 255 && b === 255)) {
        return null;
      }
      return { r, g, b };
    }
    if (str.startsWith("#")) {
      return this.#hexToRgb(str);
    }
    return null;
  }

  #hexToRgb(hex) {
    hex = hex.replace("#", "");
    if (hex.length === 3) {
      hex = hex[0] + hex[0] + hex[1] + hex[1] + hex[2] + hex[2];
    }
    if (hex.length !== 6) {
      return null;
    }
    return {
      r: parseInt(hex.slice(0, 2), 16),
      g: parseInt(hex.slice(2, 4), 16),
      b: parseInt(hex.slice(4, 6), 16),
    };
  }

  #toHex({ r, g, b }) {
    return (
      "#" +
      [r, g, b].map(v => Math.round(v).toString(16).padStart(2, "0")).join("")
    );
  }

  #linearize(c) {
    c = c / 255;
    return c <= 0.03928
      ? c / 12.92
      : Math.pow((c + 0.055) / 1.055, 2.4);
  }

  #luminance({ r, g, b }) {
    return (
      0.2126 * this.#linearize(r) +
      0.7152 * this.#linearize(g) +
      0.0722 * this.#linearize(b)
    );
  }

  #contrastRatio(c1, c2) {
    if (!c1 || !c2) {
      return 1;
    }
    const l1 = this.#luminance(c1);
    const l2 = this.#luminance(c2);
    const lighter = Math.max(l1, l2);
    const darker = Math.min(l1, l2);
    return (lighter + 0.05) / (darker + 0.05);
  }

  #shiftLightness({ r, g, b }, delta) {
    const clamp = v => Math.max(0, Math.min(255, v));
    const shift = Math.round(delta * 255);
    return { r: clamp(r + shift), g: clamp(g + shift), b: clamp(b + shift) };
  }
}
