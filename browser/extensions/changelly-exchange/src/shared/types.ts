/**
 * Shared type definitions and Zod schemas for Changelly Exchange extension.
 * These types are shared between popup, background, and backend API contracts.
 */

// ---------------------------------------------------------------------------
// Primitives
// ---------------------------------------------------------------------------

export type NetworkId = string;
export type TokenId = string;
export type SwapId = string;

// ---------------------------------------------------------------------------
// Currency / Token / Network
// ---------------------------------------------------------------------------

export interface Currency {
  id: TokenId;
  name: string;
  symbol: string;
  fullName: string;
  enabled: boolean;
  fixRateEnabled: boolean;
  blockchain?: NetworkId;
  iconUrl: string;
  /** Minimum swap amount in this currency */
  minAmount?: number;
  /** Maximum swap amount in this currency */
  maxAmount?: number;
  /** Extra ID field name (e.g. "memo", "tag") if required */
  extraIdName?: string;
  /** Whether this currency requires an extraId */
  requiresExtraId: boolean;
}

export interface Network {
  id: NetworkId;
  name: string;
  nativeToken: string;
  chainId?: number;
  logoUrl: string;
  /** Whether we can use DeFi swap on this network */
  defiSupported: boolean;
  isTestnet: boolean;
}

export interface TradingPair {
  from: TokenId;
  to: TokenId;
  minAmount: number;
  maxAmount: number;
  available: boolean;
}

// ---------------------------------------------------------------------------
// Quotes
// ---------------------------------------------------------------------------

export interface FloatingQuote {
  type: "floating";
  from: TokenId;
  to: TokenId;
  amountFrom: number;
  estimatedAmountTo: number;
  rate: number;
  networkFee: number;
  /** Expires at epoch-ms */
  expiresAt: number;
  ttlSeconds: number;
}

export interface FixedQuote {
  type: "fixed";
  from: TokenId;
  to: TokenId;
  amountFrom: number;
  amountTo: number;
  rate: number;
  networkFee: number;
  /** Server-issued rate lock ID; required in swap creation */
  rateId: string;
  expiresAt: number;
  ttlSeconds: number;
}

export type Quote = FloatingQuote | FixedQuote;

export interface FeeBreakdown {
  networkFee: number;
  networkFeeCurrency: TokenId;
  changeFee: number;
  changeFeeCurrency: TokenId;
  totalFeeUsd?: number;
}

// ---------------------------------------------------------------------------
// Address Validation
// ---------------------------------------------------------------------------

export interface AddressValidationResult {
  address: string;
  currency: TokenId;
  result: boolean;
  message?: string;
}

// ---------------------------------------------------------------------------
// Swap Lifecycle
// ---------------------------------------------------------------------------

export type SwapStatus =
  | "new"
  | "waiting"
  | "confirming"
  | "exchanging"
  | "sending"
  | "finished"
  | "failed"
  | "refunded"
  | "hold"
  | "expired"
  | "overdue";

export interface SwapDraft {
  from: TokenId;
  to: TokenId;
  amountFrom: number;
  recipientAddress: string;
  recipientExtraId?: string;
  rateType: "floating" | "fixed";
  quote?: Quote;
  createdAt?: number;
}

export interface SwapReviewState {
  draft: SwapDraft;
  quote: Quote;
  fees: FeeBreakdown;
  addressValidation: AddressValidationResult;
  /** Whether the review was confirmed by user viewport */
  termsAcknowledged: boolean;
}

export interface SwapExecutionState {
  id: SwapId;
  payinAddress: string;
  payinExtraId?: string;
  expectedAmountFrom: number;
  expectedAmountTo: number;
  from: TokenId;
  to: TokenId;
  recipientAddress: string;
  status: SwapStatus;
  createdAt: number;
  updatedAt: number;
  trackingUrl?: string;
}

export interface TransactionDetail extends SwapExecutionState {
  amountFrom?: number;
  amountTo?: number;
  txTo?: string;
  payoutAddress: string;
  moneyReceived?: number;
  moneySent?: number;
  networkFee?: number;
  currencyFrom: TokenId;
  currencyTo: TokenId;
  payinHash?: string;
  payoutHash?: string;
  recipientExtraId?: string;
}

export interface TransactionStatus {
  id: SwapId;
  status: SwapStatus;
  updatedAt: number;
}

// ---------------------------------------------------------------------------
// DeFi (Changelly DeFi Swap API)
// ---------------------------------------------------------------------------

export interface DefiToken {
  address: string;
  symbol: string;
  name: string;
  decimals: number;
  logoUrl?: string;
  network: NetworkId;
  verified: boolean;
}

export interface DefiQuoteRoute {
  fromToken: DefiToken;
  toToken: DefiToken;
  fromAmount: string;
  toAmount: string;
  priceImpact: number;
  estimatedGas: string;
  protocols?: string[];
  /** Seconds until route expires */
  ttlSeconds: number;
}

export interface ApprovalContext {
  type: "eip712" | "raw_tx";
  /** For eip712: typed data object; for raw_tx: tx params */
  // eslint-disable-next-line @typescript-eslint/no-explicit-any
  data: any;
  tokenAddress: string;
  spenderAddress: string;
}

export interface DefiIntent {
  intentId: string;
  fromNetwork: NetworkId;
  toNetwork: NetworkId;
  fromToken: DefiToken;
  toToken: DefiToken;
  amount: string;
  walletAddress: string;
  approvalRequired: boolean;
  approvalContext?: ApprovalContext;
  status: "pending" | "approved" | "executed" | "failed";
  createdAt: number;
}

// ---------------------------------------------------------------------------
// User Settings
// ---------------------------------------------------------------------------

export interface UserSetting {
  preferredRateType: "floating" | "fixed";
  slippageTolerance: number;
  defaultFromToken?: TokenId;
  defaultToToken?: TokenId;
  showAdvancedFees: boolean;
  locale: string;
  currency: string;
  termsAccepted: boolean;
  termsAcceptedVersion?: string;
  onboardingCompleted: boolean;
}

// ---------------------------------------------------------------------------
// Feature Flags
// ---------------------------------------------------------------------------

export interface FeatureFlagSet {
  fiatEnabled: boolean;
  defiEnabled: boolean;
  fixedRateEnabled: boolean;
  customTokensEnabled: boolean;
  testnetsEnabled: boolean;
  historyEnabled: boolean;
  referralEnabled: boolean;
  maintenanceMode: boolean;
  maintenanceMessage?: string;
}

// ---------------------------------------------------------------------------
// API Error
// ---------------------------------------------------------------------------

export type ApiErrorCode =
  | "INVALID_ADDRESS"
  | "AMOUNT_TOO_LOW"
  | "AMOUNT_TOO_HIGH"
  | "PAIR_UNAVAILABLE"
  | "RATE_EXPIRED"
  | "QUOTE_FAILED"
  | "SWAP_CREATE_FAILED"
  | "NETWORK_ERROR"
  | "RATE_LIMITED"
  | "MAINTENANCE"
  | "UNKNOWN";

export interface ApiError {
  code: ApiErrorCode;
  message: string;
  recoverable: boolean;
  retryAfterMs?: number;
}

// ---------------------------------------------------------------------------
// Background / Popup messaging
// ---------------------------------------------------------------------------

export type MessageType =
  | "GET_CONFIG"
  | "GET_ASSETS"
  | "GET_PAIRS"
  | "GET_QUOTE"
  | "VALIDATE_ADDRESS"
  | "CREATE_SWAP"
  | "GET_SWAP_STATUS"
  | "GET_HISTORY"
  | "GET_SETTINGS"
  | "SAVE_SETTINGS"
  | "GET_FEATURE_FLAGS"
  | "DEFI_GET_QUOTE"
  | "DEFI_CREATE_INTENT"
  | "DEFI_GET_APPROVAL"
  | "FIAT_GET_PROVIDERS"
  | "FIAT_GET_CURRENCIES"
  | "FIAT_GET_COUNTRIES"
  | "FIAT_GET_OFFERS_ON_RAMP"
  | "FIAT_GET_OFFERS_OFF_RAMP"
  | "FIAT_CREATE_ORDER_ON_RAMP"
  | "FIAT_CREATE_ORDER_OFF_RAMP"
  | "FIAT_GET_ORDERS"
  | "FIAT_VALIDATE_ADDRESS"
  | "BACKGROUND_READY";

export interface ExtensionMessage<T = unknown> {
  type: MessageType;
  requestId?: string;
  payload?: T;
}

export interface ExtensionMessageResponse<T = unknown> {
  success: boolean;
  requestId?: string;
  data?: T;
  error?: ApiError;
}

// ---------------------------------------------------------------------------
// Public runtime config (safe to ship, no secrets)
// ---------------------------------------------------------------------------

export interface PublicRuntimeConfig {
  proxyBaseUrl: string;
  proxyVersion: string;
  environment: "development" | "staging" | "production";
  featureFlags: FeatureFlagSet;
  termsUrl: string;
  privacyUrl: string;
  supportUrl: string;
  changellySupportUrl: string;
}

// ---------------------------------------------------------------------------
// Fiat API
// ---------------------------------------------------------------------------

export interface FiatProvider {
  code: string;
  name: string;
  trustPilotRating?: string;
  iconUrl?: string;
}

export interface FiatCurrencyLimit {
  min?: number;
  max?: number;
}

export interface FiatCurrencyProvider {
  providerCode: string;
  supportedFlow: Array<"buy" | "sell">;
  limits?: {
    send?: FiatCurrencyLimit;
    get?: FiatCurrencyLimit;
  };
}

export interface FiatCurrency {
  type: "crypto" | "fiat";
  ticker: string;
  name: string;
  extraIdName?: string | null;
  iconUrl?: string;
  iconColoredUrl?: string;
  precision?: string;
  network?: string;
  protocol?: string;
  providers?: FiatCurrencyProvider[];
}

export interface FiatCountry {
  code: string;
  name: string;
  states?: Array<{ code: string; name: string }>;
  providers?: Array<{
    providerCode: string;
    supportedFlow: Array<"buy" | "sell">;
  }>;
}

export interface FiatPaymentMethodOffer {
  offerId?: string;
  method: string;
  methodName: string;
  amountExpectedTo: string;
  rate: string;
  invertedRate: string;
  fee: string;
}

export interface FiatOffer {
  providerCode: string;
  offerId?: string;
  rate: string;
  invertedRate: string;
  fee: string;
  amountFrom: string;
  amountExpectedTo: string;
  paymentMethodOffer: FiatPaymentMethodOffer[];
}

export interface FiatOffersResponse {
  offers: FiatOffer[];
}

export interface FiatBaseOrder {
  externalOrderId: string;
  externalUserId: string;
  providerCode: string;
  currencyFrom: string;
  currencyTo: string;
  amountFrom: string | number;
  country: string;
  state?: string;
  ip?: string;
  paymentMethod?: string;
  userAgent?: string;
  metadata?: Record<string, unknown>;
}

export interface FiatCreateOnRampOrderRequest extends FiatBaseOrder {
  walletAddress: string;
  walletExtraId?: string;
  returnSuccessUrl?: string;
  returnFailedUrl?: string;
}

export interface FiatCreateOffRampOrderRequest extends FiatBaseOrder {
  refundAddress: string;
}

export interface FiatOrder {
  redirectUrl: string;
  orderId: string;
  externalUserId: string;
  externalOrderId: string;
  type: "buy" | "sell";
  providerCode: string;
  currencyFrom: string;
  currencyTo: string;
  amountFrom: string;
  country: string;
  state?: string;
  ip?: string;
  walletAddress?: string;
  walletExtraId?: string;
  refundAddress?: string;
  paymentMethod?: string;
  userAgent?: string;
  metadata?: Record<string, unknown> | null;
  returnSuccessUrl?: string;
  returnFailedUrl?: string;
  payinAmount?: string;
  payoutAmount?: string;
  payinCurrency?: string;
  payoutCurrency?: string;
  status?: string;
  createdAt?: string;
  updatedAt?: string;
  transactionHash?: string;
}

export interface FiatOrdersResponse {
  orders: FiatOrder[];
  total: number;
  limit: number;
  offset: number;
}

export interface FiatValidateAddressRequest {
  currency: string;
  walletAddress: string;
  walletExtraId?: string;
}

export interface FiatValidateAddressResponse {
  result: boolean;
  cause?: "walletAddress" | "walletExtraId" | null;
}
