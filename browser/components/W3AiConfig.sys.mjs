/* This Source Code Form is subject to the terms of the Mozilla Public
 * License, v. 2.0. If a copy of the MPL was not distributed with this
 * file, You can obtain one at http://mozilla.org/MPL/2.0/. */

/**
 * W3Ai Browser — Centralized Product Configuration
 *
 * All W3Ai and Plato product-facing identity, endpoints, and URLs should be
 * defined here and imported where needed. This single-source-of-truth approach
 * ensures future brand or endpoint updates only require changes in one place.
 *
 * Upgrade note: This file is additive and does not modify any Firefox core
 * module. Consumers import from this file to avoid scattered hardcoding.
 */

export const W3Ai = Object.freeze({
  // ============================================================
  // PRODUCT IDENTITY
  // ============================================================
  PRODUCT_NAME: "W3Ai",
  PRODUCT_SHORT_NAME: "W3Ai",
  COMPANY_NAME: "Plato",
  VENDOR_NAME: "Plato",

  // ============================================================
  // PRODUCT URLS
  // Centralized so a single update here propagates everywhere.
  // ============================================================
  URLS: Object.freeze({
    HOME: "https://www.plato.ai/",
    PRODUCT: "https://www.plato.ai/w3ai/",
    SUPPORT: "https://support.plato.ai/",
    PRIVACY: "https://www.plato.ai/privacy/",
    TERMS: "https://www.plato.ai/terms/",
    ABOUT: "https://www.plato.ai/about/",

    // Extensions / add-ons
    EXTENSIONS_BASE: "https://extensions.plato.ai/",
    EXTENSIONS_SEARCH: "https://extensions.plato.ai/search/",
    EXTENSIONS_THEMES: "https://extensions.plato.ai/themes/",

    // AI assistant
    AI_ASSISTANT: "https://ai.plato.ai/",
    AI_ASSISTANT_ENDPOINT: "https://ai.plato.ai/v1",

    // New tab / home page
    NEW_TAB: "about:newtab",
    HOME_PAGE: "about:home",

    // Update / release
    RELEASE_NOTES: "https://www.plato.ai/w3ai/releases/",
    UPDATE_CHECK: "https://update.plato.ai/w3ai/",
  }),

  // ============================================================
  // WEB3 EXTENSION CATALOG
  // Curated list of Web3-focused extensions for the W3Ai browser.
  // Add new extensions here; the extensions UI reads from this.
  // ============================================================
  WEB3_EXTENSIONS: [
    {
      id: "metamask@metamask.io",
      name: "MetaMask",
      description: "A crypto wallet and gateway to blockchain apps.",
      category: "Web3 Wallet",
      version: "12.0.0",
      icon: "https://extensions.plato.ai/icons/metamask.png",
      homepage: "https://metamask.io",
      install_url: "https://addons.mozilla.org/firefox/addon/ether-metamask/",
      tags: ["wallet", "ethereum", "defi"],
    },
    {
      id: "phantom@phantom.app",
      name: "Phantom",
      description: "A friendly Solana and multi-chain crypto wallet.",
      category: "Web3 Wallet",
      version: "23.0.0",
      icon: "https://extensions.plato.ai/icons/phantom.png",
      homepage: "https://phantom.app",
      install_url: "https://addons.mozilla.org/firefox/addon/phantom-app/",
      tags: ["wallet", "solana", "multichain"],
    },
    {
      id: "rabby@rabby.io",
      name: "Rabby Wallet",
      description: "The game-changing wallet for Ethereum and all EVM chains.",
      category: "Web3 Wallet",
      version: "0.92.0",
      icon: "https://extensions.plato.ai/icons/rabby.png",
      homepage: "https://rabby.io",
      install_url: "https://addons.mozilla.org/firefox/addon/rabby/",
      tags: ["wallet", "ethereum", "evm"],
    },
    {
      id: "uniswap@uniswap.org",
      name: "Uniswap Wallet",
      description: "Swap, earn, and build on the leading decentralized exchange.",
      category: "DeFi",
      version: "2.0.0",
      icon: "https://extensions.plato.ai/icons/uniswap.png",
      homepage: "https://uniswap.org",
      install_url: "https://addons.mozilla.org/firefox/addon/uniswap-wallet/",
      tags: ["defi", "swap", "ethereum"],
    },
    {
      id: "etherscan@etherscan.io",
      name: "Etherscan Gas Tracker",
      description: "Real-time Ethereum gas price tracker in your browser.",
      category: "Utilities",
      version: "1.5.0",
      icon: "https://extensions.plato.ai/icons/etherscan.png",
      homepage: "https://etherscan.io",
      install_url: "https://addons.mozilla.org/firefox/addon/etherscan-gas/",
      tags: ["ethereum", "gas", "explorer"],
    },
    {
      id: "tally@tallywallet.com",
      name: "Tally Ho",
      description: "The community-owned Web3 wallet.",
      category: "Web3 Wallet",
      version: "24.5.0",
      icon: "https://extensions.plato.ai/icons/tally.png",
      homepage: "https://tally.cash",
      install_url: "https://addons.mozilla.org/firefox/addon/tally-ho/",
      tags: ["wallet", "community", "multichain"],
    },
    {
      id: "argent@argent.xyz",
      name: "Argent X",
      description: "The smart Starknet wallet for DeFi and NFTs.",
      category: "Web3 Wallet",
      version: "5.14.0",
      icon: "https://extensions.plato.ai/icons/argent.png",
      homepage: "https://www.argent.xyz",
      install_url: "https://addons.mozilla.org/firefox/addon/argent-x/",
      tags: ["wallet", "starknet", "l2"],
    },
    {
      id: "coinbase-wallet@coinbase.com",
      name: "Coinbase Wallet",
      description: "The easiest and most secure crypto wallet.",
      category: "Web3 Wallet",
      version: "3.68.0",
      icon: "https://extensions.plato.ai/icons/coinbase-wallet.png",
      homepage: "https://www.coinbase.com/wallet",
      install_url: "https://addons.mozilla.org/firefox/addon/coinbase-wallet-extension/",
      tags: ["wallet", "coinbase", "multichain"],
    },
    {
      id: "ledger@ledger.com",
      name: "Ledger Live",
      description: "Manage your Ledger hardware wallet and crypto assets.",
      category: "Hardware Wallet",
      version: "28.0.0",
      icon: "https://extensions.plato.ai/icons/ledger.png",
      homepage: "https://www.ledger.com",
      install_url: "https://addons.mozilla.org/firefox/addon/ledger-extension/",
      tags: ["hardware-wallet", "security", "cold-storage"],
    },
    {
      id: "debank@debank.com",
      name: "DeBank DeFi Wallet",
      description: "Track and manage your DeFi portfolio across 30+ chains.",
      category: "Portfolio",
      version: "1.12.0",
      icon: "https://extensions.plato.ai/icons/debank.png",
      homepage: "https://debank.com",
      install_url: "https://addons.mozilla.org/firefox/addon/debank/",
      tags: ["portfolio", "defi", "multichain"],
    },
  ],
});
