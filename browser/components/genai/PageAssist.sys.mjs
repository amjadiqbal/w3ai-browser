/**
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

const lazy = {};
ChromeUtils.defineESModuleGetters(lazy, {
  AgentPluginRegistry:
    "moz-src:///browser/components/aiwindow/services/AgentPluginRegistry.sys.mjs",
});

const ENDPOINT_PREF = "browser.smartwindow.endpoint";
const APIKEY_PREF = "browser.smartwindow.apiKey";
const DEFAULT_MODEL = "claude-opus-4-8";
const MAX_CONTENT_CHARS = 100_000;

/**
 * Page Assistant — sends page context to the configured W3Ai AI endpoint.
 * Endpoint is read from browser.smartwindow.endpoint pref (OpenAI-compatible).
 */
export const PageAssist = {
  /**
   * Fetch AI Response
   *
   * @param {string} userPrompt
   * @param {{
   *   url: string,
   *   title: string,
   *   content: string,
   *   textContent: string,
   *   excerpt: string,
   *   isReaderable: boolean
   * }} pageData
   * @returns {Promise<string|null>}
   */
  async fetchAiResponse(userPrompt, pageData) {
    if (!pageData) {
      return null;
    }

    const endpoint = Services.prefs.getStringPref(ENDPOINT_PREF, "");
    if (!endpoint) {
      return "AI endpoint not configured. Set browser.smartwindow.endpoint in preferences.";
    }

    const apiKey = Services.prefs.getStringPref(APIKEY_PREF, "");

    const plugin = lazy.AgentPluginRegistry.getPluginForUrl(pageData.url);
    const systemPrompt = _buildSystemPrompt(pageData, plugin);

    // Build the messages endpoint URL — append /chat/completions if the endpoint
    // looks like a base URL (e.g. https://ai.plato.ai/v1).
    const messagesUrl = endpoint.endsWith("/messages")
      ? endpoint
      : endpoint.replace(/\/?$/, "") + "/chat/completions";

    const headers = { "Content-Type": "application/json" };
    if (apiKey) {
      headers.Authorization = `Bearer ${apiKey}`;
    }

    let response;
    try {
      response = await fetch(messagesUrl, {
        method: "POST",
        headers,
        body: JSON.stringify({
          model: plugin?.model ?? DEFAULT_MODEL,
          max_tokens: 1024,
          stream: false,
          messages: [
            { role: "system", content: systemPrompt },
            { role: "user", content: userPrompt },
          ],
        }),
      });
    } catch (e) {
      console.error("PageAssist: network request failed", e);
      return `Request failed: ${e.message}`;
    }

    if (!response.ok) {
      const body = await response.text().catch(() => "");
      console.error("PageAssist: API error", response.status, body);
      return `API error ${response.status}`;
    }

    let data;
    try {
      data = await response.json();
    } catch (e) {
      return "Could not parse AI response.";
    }

    return data?.choices?.[0]?.message?.content ?? null;
  },
};

function _buildSystemPrompt(pageData, plugin) {
  const parts = [
    "You are a helpful assistant embedded in the W3Ai Browser. " +
      "You have access to the web page the user is currently viewing.",
    `URL: ${pageData.url}`,
    `Title: ${pageData.title}`,
  ];

  if (pageData.excerpt) {
    parts.push(`Summary: ${pageData.excerpt}`);
  }

  const bodyText = pageData.textContent || pageData.content;
  if (bodyText) {
    const truncated =
      bodyText.length > MAX_CONTENT_CHARS
        ? bodyText.slice(0, MAX_CONTENT_CHARS) + "\n[...truncated]"
        : bodyText;
    parts.push(`\nPage content:\n${truncated}`);
  } else {
    parts.push(
      "\nNote: Page content could not be extracted (non-article page)."
    );
  }

  if (plugin?.systemSuffix) {
    parts.push(`\n${plugin.systemSuffix}`);
  }

  parts.push("\nAnswer the user's question based on the page above. Be concise.");
  return parts.join("\n");
}
