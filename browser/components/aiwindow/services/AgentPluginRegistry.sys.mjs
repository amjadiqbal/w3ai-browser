/**
 * This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/.
 */

/**
 * @typedef {object} AgentPlugin
 * @property {string}   name            Display name shown in sidebar header
 * @property {string}   description     One-line description of the agent's role
 * @property {string}   systemSuffix    Appended to the base system prompt when this plugin is active
 * @property {string[]} suggestedPrompts Chips shown below the input field
 * @property {string}   [model]         Override model for this plugin (optional)
 */

/**
 * Built-in site-specific agent plugins.
 * Entries are tested in order; first match wins.
 * Patterns are matched against the full URL string (case-insensitive).
 */
const REGISTRY = [
  {
    pattern: /c100\.w3ai\.io/i,
    plugin: {
      name: "CIP Concierge",
      description: "Carbon Index Protocol — DeFi analytics and on-chain insights",
      systemSuffix:
        "You are the CIP Concierge, a specialized agent for the Carbon Index Protocol (CIP) on the W3Ai platform. " +
        "You understand DeFi mechanics, carbon credit tokenomics, staking yields, and on-chain governance. " +
        "Provide precise, actionable insights. When discussing transactions always note risk and slippage.",
      suggestedPrompts: [
        "What is the current CIP staking APY?",
        "Explain the carbon credit burn mechanism",
        "How do I participate in governance?",
        "Summarize today's index performance",
      ],
    },
  },
  {
    pattern: /w3ai\.io/i,
    plugin: {
      name: "W3Ai Assistant",
      description: "W3Ai platform — AI-native Web3 browser features",
      systemSuffix:
        "You are the W3Ai Assistant, an expert on the W3Ai Browser platform built by PlatoAi. " +
        "You know the four-layer verifiable execution pipeline (Local, Hybrid, Network, Enterprise), " +
        "the stake→compute→burn economy, and the Solana-based agent SDK.",
      suggestedPrompts: [
        "What can I do on this page?",
        "How does W3Ai protect my privacy?",
        "Explain the stake-compute-burn model",
        "What Web3 features are available?",
      ],
    },
  },
  {
    pattern: /uniswap\.org|app\.uniswap/i,
    plugin: {
      name: "DeFi Analyst",
      description: "Uniswap — liquidity pool and swap analysis",
      systemSuffix:
        "You are a DeFi analyst specializing in Uniswap. " +
        "Explain liquidity provision, impermanent loss, fee tiers, and swap routing clearly. " +
        "Always include risk disclosures when discussing financial operations.",
      suggestedPrompts: [
        "What are the risks of providing liquidity here?",
        "Explain the fee tier for this pool",
        "What is impermanent loss?",
        "How is the swap price determined?",
      ],
    },
  },
  {
    pattern: /github\.com/i,
    plugin: {
      name: "Code Review Agent",
      description: "GitHub — code review, PR summary, issue analysis",
      systemSuffix:
        "You are a code review agent on GitHub. " +
        "Summarize pull requests, flag potential bugs or security issues, explain unfamiliar code, " +
        "and suggest improvements. Be concise and technical.",
      suggestedPrompts: [
        "Summarize this pull request",
        "Are there any obvious bugs?",
        "Explain the main changes",
        "What tests should be added?",
      ],
    },
  },
];

/** Default plugin used when no pattern matches the current URL. */
const DEFAULT_PLUGIN = {
  name: "Page Assistant",
  description: "Ask anything about the current page",
  systemSuffix: "",
  suggestedPrompts: [
    "Summarize this page",
    "What are the key points?",
    "Explain this in simple terms",
    "What actions can I take here?",
  ],
};

/**
 * Look up the agent plugin for a given URL.
 *
 * @param {string} url
 * @returns {AgentPlugin}
 */
function getPluginForUrl(url) {
  for (const entry of REGISTRY) {
    if (entry.pattern.test(url)) {
      return entry.plugin;
    }
  }
  return DEFAULT_PLUGIN;
}

export const AgentPluginRegistry = {
  getPluginForUrl,
  DEFAULT_PLUGIN,
};
