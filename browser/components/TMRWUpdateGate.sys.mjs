/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

import { AppConstants } from "resource://gre/modules/AppConstants.sys.mjs";

const UPDATE_XML_URL = "https://tmrw.w3ai.io/updates/update.xml";
const SKIP_PREF = "tmrw.updateGate.skippedVersion";
const DMG_DOWNLOAD_URL = "https://tmrw.w3ai.io/download";

let _checked = false;

export const TMRWUpdateGate = {
  // Used for the v1.0.3 → v1.0.4 bootstrap transition.
  // v1.0.3 has Mozilla's Nightly updater which rejects unsigned MARs.
  // So we show a banner directing users to download v1.0.4 DMG manually.
  // Once all users are on v1.0.4+ (which has the custom updater), this
  // no-ops because the built-in MAR updater handles updates from there.
  async check(window) {
    if (_checked) {
      return;
    }
    _checked = true;

    // v1.0.4+ has the custom updater — built-in MAR updater takes over.
    const currentVersion = AppConstants.MOZ_APP_VERSION;
    const vc = Cc["@mozilla.org/xpcom/version-comparator;1"].getService(
      Ci.nsIVersionComparator
    );
    if (vc.compare(currentVersion, "1.0.4") >= 0) {
      return;
    }

    // v1.0.3 and below: check for newer version and show download banner.
    let serverVersion;
    try {
      const resp = await fetch(UPDATE_XML_URL, {
        cache: "no-store",
        signal: AbortSignal.timeout(8000),
      });
      const xml = await resp.text();
      const verMatch = xml.match(/appVersion="([^"]+)"/);
      if (!verMatch) {
        return;
      }
      serverVersion = verMatch[1];
    } catch {
      return;
    }

    if (vc.compare(serverVersion, currentVersion) <= 0) {
      return;
    }

    const skipped = Services.prefs.getCharPref(SKIP_PREF, "");
    if (skipped === serverVersion) {
      return;
    }

    await new Promise(resolve => {
      window.openDialog(
        "chrome://browser/content/browser/update-gate.xhtml",
        "tmrw-update-gate",
        "chrome,centerscreen,modal,resizable=no,width=480,height=420",
        { serverVersion, currentVersion, dmgUrl: DMG_DOWNLOAD_URL, resolve }
      );
    });
  },
};
