/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import { AppConstants } from "resource://gre/modules/AppConstants.sys.mjs";

const UPDATE_XML_URL = "https://tmrw.w3ai.io/updates/update.xml";
const SKIP_PREF = "tmrw.updateGate.skippedVersion";

let _checked = false;

export const TMRWUpdateGate = {
  async check(window) {
    if (_checked) {
      return;
    }
    _checked = true;

    let serverVersion, dmgUrl;
    try {
      const resp = await fetch(UPDATE_XML_URL, {
        cache: "no-store",
        signal: AbortSignal.timeout(8000),
      });
      const xml = await resp.text();
      const verMatch = xml.match(/appVersion="([^"]+)"/);
      const urlMatch = xml.match(/URL="([^"]+\.dmg)"/);
      if (!verMatch) {
        return;
      }
      serverVersion = verMatch[1];
      dmgUrl = urlMatch ? urlMatch[1] : null;
    } catch {
      return;
    }

    const currentVersion = AppConstants.MOZ_APP_VERSION;
    const vc = Cc["@mozilla.org/xpcom/version-comparator;1"].getService(
      Ci.nsIVersionComparator
    );

    if (vc.compare(serverVersion, currentVersion) <= 0) {
      return;
    }

    // Skip if the user already dismissed this exact version
    const skipped = Services.prefs.getCharPref(SKIP_PREF, "");
    if (skipped === serverVersion) {
      return;
    }

    await new Promise(resolve => {
      window.openDialog(
        "chrome://browser/content/browser/update-gate.xhtml",
        "tmrw-update-gate",
        "chrome,centerscreen,modal,resizable=no,width=480,height=420",
        { serverVersion, currentVersion, dmgUrl, resolve }
      );
    });
  },
};
