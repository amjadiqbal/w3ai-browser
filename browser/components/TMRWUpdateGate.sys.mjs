/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

let _checked = false;

export const TMRWUpdateGate = {
  // Updates are now handled by Firefox's built-in MAR-based updater.
  // The custom org.mozilla.updater binary (no signature check) accepts our MARs.
  async check(_window) {
    _checked = true;
  },
};
