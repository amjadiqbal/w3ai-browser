/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/**
 * Parent side of the PageColor actor pair.
 *
 * Called by AIWindowUI.applyPageTheme() to request a color palette from the
 * content process of the active web tab.
 */
export class PageColorParent extends JSWindowActorParent {
  /**
   * Ask the content process to extract the page's color palette.
   *
   * @returns {Promise<{
   *   primary: string|null,
   *   accent: string|null,
   *   background: string|null,
   *   surface: string|null,
   *   text: string,
   *   mode: "light"|"dark"
   * }|null>}
   */
  async extractColors() {
    try {
      return await this.sendQuery("PageColor:Extract");
    } catch {
      return null;
    }
  }
}
