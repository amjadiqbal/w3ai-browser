/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

let _checked = false;

export const TMRWUpdateGate = {
  // v1.0.4+ uses the built-in MAR-based updater with a custom org.mozilla.updater
  // binary that skips signature verification. This gate is a no-op from v1.0.4 onward.
  async check(_window) {
    _checked = true;
  },
};
