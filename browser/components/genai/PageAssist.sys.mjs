/**
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

const APIKEY_PREF = "browser.smartwindow.apiKey";
const CLAUDE_ENDPOINT = "https://api.anthropic.com/v1/messages";
const DEFAULT_MODEL = "claude-opus-4-8";
const MAX_CONTENT_CHARS = 100_000;

/**
 * Page Assistant — calls Claude API with the current page as context.
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

    const apiKey = Services.prefs.getStringPref(APIKEY_PREF, "");
    if (!apiKey) {
      return "API key not configured. Add your Anthropic API key in browser settings.";
    }

    const systemPrompt = _buildSystemPrompt(pageData);

    let response;
    try {
      response = await fetch(CLAUDE_ENDPOINT, {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "x-api-key": apiKey,
          "anthropic-version": "2023-06-01",
        },
        body: JSON.stringify({
          model: DEFAULT_MODEL,
          max_tokens: 1024,
          stream: true,
          system: [
            {
              type: "text",
              text: systemPrompt,
              cache_control: { type: "ephemeral" },
            },
          ],
          messages: [{ role: "user", content: userPrompt }],
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

    return _drainStream(response.body);
  },
};

function _buildSystemPrompt(pageData) {
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

  parts.push("\nAnswer the user's question based on the page above. Be concise.");
  return parts.join("\n");
}

async function _drainStream(body) {
  const decoder = new TextDecoder();
  const reader = body.getReader();
  let text = "";

  try {
    outer: while (true) {
      const { done, value } = await reader.read();
      if (done) {
        break;
      }
      for (const line of decoder.decode(value, { stream: true }).split("\n")) {
        if (!line.startsWith("data: ")) {
          continue;
        }
        const payload = line.slice(6).trim();
        if (payload === "[DONE]") {
          break outer;
        }
        let event;
        try {
          event = JSON.parse(payload);
        } catch {
          continue;
        }
        if (
          event.type === "content_block_delta" &&
          event.delta?.type === "text_delta"
        ) {
          text += event.delta.text;
        }
      }
    }
  } finally {
    reader.releaseLock();
  }

  return text || null;
}
