/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// This file contains branding-specific prefs.

pref("startup.homepage_override_url", "");
pref("startup.homepage_welcome_url", "about:welcome");
pref("startup.homepage_welcome_url.additional", "");
// Interval: Time between checks for a new version (in seconds)
pref("app.update.interval", 21600); // 6 hours
// Give the user x seconds to react before showing the big UI. default=192 hours
pref("app.update.promptWaitTime", 691200);
// app.update.url.manual: URL user can browse to manually if for some reason
// all update installation attempts fail.
// app.update.url.details: a default value for the "More information about this
// update" link supplied in the "An update is available" page of the update
// wizard.
#if MOZ_UPDATE_CHANNEL == beta
  pref("app.update.url.manual", "");
  pref("app.update.url.details", "");
  pref("app.releaseNotesURL", "");
  pref("app.releaseNotesURL.aboutDialog", "");
#elifdef MOZ_ESR
  pref("app.update.url.manual", "");
  pref("app.update.url.details", "");
  pref("app.releaseNotesURL", "");
  pref("app.releaseNotesURL.aboutDialog", "");
#else
  pref("app.update.url.manual", "");
  pref("app.update.url.details", "");
  pref("app.releaseNotesURL", "");
  pref("app.releaseNotesURL.aboutDialog", "");
#endif
pref("app.releaseNotesURL.prompt", "");

// The number of days a binary is permitted to be old
// without checking for an update.  This assumes that
// app.update.checkInstallTime is true.
pref("app.update.checkInstallTime.days", 63);

// Give the user x seconds to reboot before showing a badge on the hamburger
// button. default=4 days
pref("app.update.badgeWaitTime", 345600);

// Number of usages of the web console.
// If this is less than 5, then pasting code into the web console is disabled
pref("devtools.selfxss.count", 0);

// Disable Mozilla Account sync and remote endpoints by default
pref("identity.fxaccounts.enabled", false);
pref("identity.fxaccounts.toolbar.enabled", false);
pref("identity.fxaccounts.toolbar.defaultVisible", false);
pref("identity.fxaccounts.toolbar.pxiToolbarEnabled", false);
pref("identity.fxaccounts.toolbar.pxiToolbarEnabled.monitorEnabled", false);
pref("identity.fxaccounts.toolbar.pxiToolbarEnabled.relayEnabled", false);
pref("identity.fxaccounts.toolbar.pxiToolbarEnabled.vpnEnabled", false);

// Clear Mozilla-hosted endpoints; set your own later if needed
pref("identity.fxaccounts.remote.pairing.uri", "");
pref("identity.sync.tokenserver.uri", "");
pref("identity.fxaccounts.autoconfig.uri", "");
pref("identity.sendtabpromo.url", "");
pref("identity.mobilepromo.android", "");
pref("identity.mobilepromo.ios", "");

// Hide experimental "Firefox Labs" section and disable "More from Mozilla"
pref("browser.preferences.experimental.hidden", true);
pref("browser.preferences.moreFromMozilla", false);

// Point support links to a local blank page
pref("app.support.baseURL", "about:blank#");

// About:addons: disable AMO links and use local recommendations
pref("extensions.getAddons.link.url", "about:blank#");
pref("extensions.getAddons.search.browseURL", "");
pref("extensions.recommendations.privacyPolicyUrl", "about:blank#");
pref("extensions.getAddons.discovery.api_url", "about:blank#");
pref("extensions.htmlaboutaddons.recommendations.enabled", true);
pref("extensions.recommendations.hideNotice", true);
