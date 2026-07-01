/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

// This file contains branding-specific prefs.

pref("startup.homepage_override_url", "");
pref("startup.homepage_welcome_url", "https://tmrw.w3ai.io/");
pref("startup.homepage_welcome_url.additional", "");

// Default homepage and new tab page
pref("browser.startup.homepage", "https://tmrw.w3ai.io/");
pref("browser.startup.page", 1);

// Disable new tab preloading — prevents content process crash (NS_ERROR_UNEXPECTED
// in nsIScriptSecurityManager.getLoadContextContentPrincipal) that stalls page loads
pref("browser.newtab.preload", false);

// Redirect about:newtab to our homepage instead of Activity Stream
pref("browser.newtabpage.enabled", false);
pref("browser.newtab.url", "https://tmrw.w3ai.io/");
// Interval: Time between checks for a new version (in seconds)
pref("app.update.interval", 21600); // 6 hours
// Give the user x seconds to react before showing the big UI. default=192 hours
pref("app.update.promptWaitTime", 691200);

// TMRW uses a custom updater (no MAR signature check) with MAR-based patches.
// update.xml served at this URL describes complete .mar packages.
pref("app.update.url", "https://tmrw-update.w3ai.io/updates/update.xml");
pref("app.update.enabled", true);
pref("app.update.auto", false);


#if MOZ_UPDATE_CHANNEL == beta
  pref("app.update.url.manual", "https://tmrw.w3ai.io/download");
  pref("app.update.url.details", "https://tmrw.w3ai.io/releases");
  pref("app.releaseNotesURL", "https://tmrw.w3ai.io/releases");
  pref("app.releaseNotesURL.aboutDialog", "https://tmrw.w3ai.io/releases");
#elifdef MOZ_ESR
  pref("app.update.url.manual", "https://tmrw.w3ai.io/download");
  pref("app.update.url.details", "https://tmrw.w3ai.io/releases");
  pref("app.releaseNotesURL", "https://tmrw.w3ai.io/releases");
  pref("app.releaseNotesURL.aboutDialog", "https://tmrw.w3ai.io/releases");
#else
  pref("app.update.url.manual", "https://tmrw.w3ai.io/download");
  pref("app.update.url.details", "https://tmrw.w3ai.io/releases");
  pref("app.releaseNotesURL", "https://tmrw.w3ai.io/releases");
  pref("app.releaseNotesURL.aboutDialog", "https://tmrw.w3ai.io/releases");
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

// Zero out all Mozilla-hosted FxA and Sync endpoints
pref("identity.fxaccounts.remote.root", "");
pref("identity.fxaccounts.remote.profile.uri", "");
pref("identity.fxaccounts.remote.oauth.uri", "");
pref("identity.fxaccounts.remote.pairing.uri", "");
pref("identity.fxaccounts.autoconfig.uri", "");
pref("identity.sync.tokenserver.uri", "");
pref("identity.sendtabpromo.url", "");
pref("identity.mobilepromo.android", "");
pref("identity.mobilepromo.ios", "");

// Hide experimental "Firefox Labs" section and disable "More from Mozilla"
pref("browser.preferences.experimental.hidden", true);
pref("browser.preferences.moreFromMozilla", false);

// Point support links to a local blank page
pref("app.support.baseURL", "about:blank#");

// W3Ai firstrun: bypass all Firefox onboarding — AIWindow has its own firstrun flow
pref("browser.aboutwelcome.enabled", false);
pref("browser.preonboarding.enabled", false);
pref("termsofuse.bypassNotification", true);
pref("messaging-system.askForFeedback", false);

// About:addons: disable remote discovery API (server not live yet); hide data-sharing notice
pref("extensions.getAddons.discovery.api_url", "");
pref("extensions.htmlaboutaddons.recommendations.enabled", false);
pref("extensions.recommendations.hideNotice", true);

// --- Milestone 8: Privacy Hardening ---

// Disable Glean/telemetry data submission and upload
pref("datareporting.policy.dataSubmissionEnabled", false);
pref("datareporting.healthreport.uploadEnabled", false);

// Disable all classic telemetry pings
pref("toolkit.telemetry.unified", false);
pref("toolkit.telemetry.server", "");
pref("toolkit.telemetry.archive.enabled", false);
pref("toolkit.telemetry.shutdownPingSender.enabled", false);
pref("toolkit.telemetry.firstShutdownPing.enabled", false);
pref("toolkit.telemetry.newProfilePing.enabled", false);
pref("toolkit.telemetry.updatePing.enabled", false);
pref("toolkit.telemetry.bhrPing.enabled", false);
pref("toolkit.telemetry.user_characteristics_ping.opt-out", true);

// Disable DAP (Distributed Aggregation Protocol) privacy-preserving measurements
pref("toolkit.telemetry.dap_enabled", false);
pref("toolkit.telemetry.dap_task1_enabled", false);
pref("toolkit.telemetry.dap_visit_counting_enabled", false);

// Disable Normandy/Shield remote recipe execution and studies
pref("app.normandy.enabled", false);
pref("app.normandy.api_url", "");
pref("app.shield.optoutstudies.enabled", false);
pref("nimbus.telemetry.targetingContextEnabled", false);

// Disable crash report auto-submission
pref("browser.crashReports.unsubmittedCheck.enabled", false);
pref("browser.crashReports.unsubmittedCheck.autoSubmit2", false);
pref("browser.tabs.crashReporting.sendReport", false);

// Zero out Mozilla analytics/suggestions service endpoints
pref("browser.urlbar.merino.endpointURL", "");
pref("browser.urlbar.merino.ohttpConfigURL", "");
pref("browser.urlbar.merino.ohttpRelayURL", "");
pref("browser.urlbar.merino.weather.reportEndpointURL", "");
pref("browser.urlbar.merino.weather.hourlyEndpointURL", "");
pref("browser.newtabpage.activity-stream.discoverystream.merino-provider.endpoint", "");
pref("browser.newtabpage.trainhopAddon.xpiBaseURL", "");

// Zero out Mozilla partner/attribution/coverage endpoints
pref("browser.topsites.contile.endpoint", "");
pref("browser.partnerlink.attributionURL", "");
pref("toolkit.coverage.endpoint.base", "");
pref("security.certerrors.mitm.priming.endpoint", "");
pref("app.feedback.baseURL", "");
pref("browser.ipProtection.guardian.endpoint", "");

// Disable FxAccounts telemetry association ping
pref("identity.fxaccounts.telemetry.clientAssociationPing.enabled", false);

// Disable search SERP event telemetry
pref("browser.search.serpEventTelemetryCategorization.enabled", false);
