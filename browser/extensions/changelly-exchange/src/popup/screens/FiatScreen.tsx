import React, { useEffect, useMemo, useState } from "react";
import { sendMessage } from "../messaging";
import { useAppState, useDispatch } from "../state/AppStore";
import type {
  FiatCountry,
  FiatCreateOffRampOrderRequest,
  FiatCreateOnRampOrderRequest,
  FiatCurrency,
  FiatOffer,
  FiatOffersResponse,
  FiatProvider,
} from "../../shared/types";

type FiatFlow = "buy" | "sell";

function uid(prefix: string): string {
  return `${prefix}-${Date.now()}`;
}

export default function FiatScreen() {
  const dispatch = useDispatch();
  const state = useAppState();

  const [flow, setFlow] = useState<FiatFlow>("buy");
  const [loading, setLoading] = useState(false);
  const [submitting, setSubmitting] = useState(false);
  const [error, setError] = useState<string | null>(null);
  const [providers, setProviders] = useState<FiatProvider[]>([]);
  const [fiatCurrencies, setFiatCurrencies] = useState<FiatCurrency[]>([]);
  const [cryptoCurrencies, setCryptoCurrencies] = useState<FiatCurrency[]>([]);
  const [countries, setCountries] = useState<FiatCountry[]>([]);
  const [offers, setOffers] = useState<FiatOffer[]>([]);

  const [providerCode, setProviderCode] = useState("");
  const [currencyFrom, setCurrencyFrom] = useState("USD");
  const [currencyTo, setCurrencyTo] = useState("BTC");
  const [country, setCountry] = useState("US");
  const [amountFrom, setAmountFrom] = useState("100");
  const [walletAddress, setWalletAddress] = useState("");

  async function bootstrap() {
    setLoading(true);
    setError(null);
    try {
      const [providersRes, fiatRes, cryptoRes, countriesRes] = await Promise.all([
        sendMessage<FiatProvider[]>("FIAT_GET_PROVIDERS"),
        sendMessage<FiatCurrency[]>("FIAT_GET_CURRENCIES", { type: "fiat", supportedFlow: flow }),
        sendMessage<FiatCurrency[]>("FIAT_GET_CURRENCIES", { type: "crypto", supportedFlow: flow }),
        sendMessage<FiatCountry[]>("FIAT_GET_COUNTRIES", { supportedFlow: flow }),
      ]);
      setProviders(providersRes ?? []);
      setFiatCurrencies(fiatRes ?? []);
      setCryptoCurrencies(cryptoRes ?? []);
      setCountries(countriesRes ?? []);

      if (providersRes[0]?.code) setProviderCode((prev) => prev || providersRes[0].code);
      if (fiatRes[0]?.ticker) setCurrencyFrom((prev) => prev || fiatRes[0].ticker);
      if (cryptoRes[0]?.ticker) {
        setCurrencyTo((prev) => prev || cryptoRes[0].ticker);
      }
      if (countriesRes[0]?.code) setCountry((prev) => prev || countriesRes[0].code);
    } catch (err) {
      setError((err as Error)?.message ?? "Failed to initialize fiat data.");
    } finally {
      setLoading(false);
    }
  }

  async function loadOffers() {
    setLoading(true);
    setError(null);
    try {
      const payload = {
        providerCode: providerCode || undefined,
        currencyFrom,
        currencyTo,
        amountFrom,
        country,
      };
      const res =
        flow === "buy"
          ? await sendMessage<FiatOffersResponse>("FIAT_GET_OFFERS_ON_RAMP", payload)
          : await sendMessage<FiatOffersResponse>("FIAT_GET_OFFERS_OFF_RAMP", payload);
      setOffers(res?.offers ?? []);
    } catch (err) {
      setError((err as Error)?.message ?? "Failed to load offers.");
      setOffers([]);
    } finally {
      setLoading(false);
    }
  }

  async function createOrder() {
    if (!walletAddress.trim()) {
      setError("Wallet address is required.");
      return;
    }

    setSubmitting(true);
    setError(null);
    try {
      const base = {
        externalOrderId: uid("w3ai"),
        externalUserId: uid("user"),
        providerCode,
        currencyFrom,
        currencyTo,
        amountFrom,
        country,
        userAgent: typeof navigator !== "undefined" ? navigator.userAgent : "W3Ai",
      };

      const order =
        flow === "buy"
          ? await sendMessage<any>("FIAT_CREATE_ORDER_ON_RAMP", {
              ...(base as FiatCreateOnRampOrderRequest),
              walletAddress,
              returnSuccessUrl: "https://w3ai.io/swap/success",
              returnFailedUrl: "https://w3ai.io/swap/failure",
            })
          : await sendMessage<any>("FIAT_CREATE_ORDER_OFF_RAMP", {
              ...(base as FiatCreateOffRampOrderRequest),
              refundAddress: walletAddress,
            });

      if (order?.redirectUrl) {
        await browser.tabs.create({ url: order.redirectUrl });
      }
    } catch (err) {
      setError((err as Error)?.message ?? "Failed to create fiat order.");
    } finally {
      setSubmitting(false);
    }
  }

  const fromOptions = useMemo(
    () => (flow === "buy" ? fiatCurrencies : cryptoCurrencies),
    [flow, fiatCurrencies, cryptoCurrencies]
  );
  const toOptions = useMemo(
    () => (flow === "buy" ? cryptoCurrencies : fiatCurrencies),
    [flow, fiatCurrencies, cryptoCurrencies]
  );

  useEffect(() => {
    if (!state.featureFlags.fiatEnabled) {
      setOffers([]);
      return;
    }
    void bootstrap();
  }, [flow, state.featureFlags.fiatEnabled]);

  return (
    <div className="screen">
      <header className="screen-header">
        <button className="btn btn-ghost" onClick={() => dispatch({ type: "SET_SCREEN", payload: "swap" })}>
          Back
        </button>
        <span className="screen-title">Buy / Sell Crypto</span>
        <button className="btn btn-ghost" onClick={bootstrap}>
          Refresh
        </button>
      </header>

      <div className="fiat-hero">
        <div className="fiat-eyebrow">Changelly Fiat</div>
        <h2>Card and bank payouts in one flow</h2>
        <p>Powered by Changelly Fiat API providers with live offers.</p>
        <div className="fiat-kpi-row">
          <div className="fiat-kpi">
            <span>Providers</span>
            <strong>{providers.length}</strong>
          </div>
          <div className="fiat-kpi">
            <span>Currencies</span>
            <strong>{fromOptions.length + toOptions.length}</strong>
          </div>
          <div className="fiat-kpi">
            <span>Countries</span>
            <strong>{countries.length}</strong>
          </div>
        </div>
      </div>

      <div className="fiat-flow-toggle" role="tablist" aria-label="Fiat flow">
        <button className={`btn fiat-flow-btn ${flow === "buy" ? "btn-primary" : "btn-ghost"}`} onClick={() => setFlow("buy")}>
          Buy
        </button>
        <button className={`btn fiat-flow-btn ${flow === "sell" ? "btn-primary" : "btn-ghost"}`} onClick={() => setFlow("sell")}>
          Sell
        </button>
      </div>

      <div className="card fiat-form-grid">
        <label className="fiat-field">
          <span>Provider</span>
          <select className="input-field" value={providerCode} onChange={(e) => setProviderCode(e.target.value)}>
            <option value="">Best available</option>
            {providers.map((p) => (
              <option key={p.code} value={p.code}>{p.name}</option>
            ))}
          </select>
        </label>

        <label className="fiat-field">
          <span>From</span>
          <select className="input-field" value={currencyFrom} onChange={(e) => setCurrencyFrom(e.target.value)}>
            {fromOptions.map((c) => (
              <option key={c.ticker} value={c.ticker}>{c.ticker}</option>
            ))}
          </select>
        </label>

        <label className="fiat-field">
          <span>To</span>
          <select className="input-field" value={currencyTo} onChange={(e) => setCurrencyTo(e.target.value)}>
            {toOptions.map((c) => (
              <option key={c.ticker} value={c.ticker}>{c.ticker}</option>
            ))}
          </select>
        </label>

        <label className="fiat-field">
          <span>Country</span>
          <select className="input-field" value={country} onChange={(e) => setCountry(e.target.value)}>
            {countries.map((c) => (
              <option key={c.code} value={c.code}>{c.name}</option>
            ))}
          </select>
        </label>

        <label className="fiat-field">
          <span>Amount</span>
          <input className="input-field" value={amountFrom} onChange={(e) => setAmountFrom(e.target.value)} />
        </label>

        <label className="fiat-field">
          <span>{flow === "buy" ? "Wallet address" : "Refund address"}</span>
          <input className="input-field" value={walletAddress} onChange={(e) => setWalletAddress(e.target.value)} />
        </label>

        <button className="btn btn-primary fiat-submit-btn" onClick={loadOffers} disabled={loading}>
          {loading ? "Loading offers..." : "Get offers"}
        </button>
      </div>

      {error && <div className="banner banner-danger">{error}</div>}

      {offers.length > 0 && (
        <div className="card fiat-offers-grid">
          <div className="fiat-offers-title">Top offers</div>
          {offers.slice(0, 3).map((offer, idx) => (
            <div key={`${offer.providerCode}-${idx}`} className="fiat-offer-card">
              <div className="fiat-offer-head">
                <span className="fiat-provider-pill">{offer.providerCode.toUpperCase()}</span>
                <span>{offer.amountExpectedTo} {currencyTo}</span>
              </div>
              <div className="fiat-offer-row">
                <span>Rate</span>
                <span>{offer.rate}</span>
              </div>
              <div className="fiat-offer-row">
                <span>Fee</span>
                <span>{offer.fee}</span>
              </div>
            </div>
          ))}
          <button className="btn btn-primary" onClick={createOrder} disabled={submitting || !providerCode}>
            {submitting ? "Creating order..." : "Continue to provider"}
          </button>
        </div>
      )}

      {!state.featureFlags.fiatEnabled && (
        <div className="banner banner-info">Fiat API is disabled. Add Fiat API keys in backend .env to enable buy/sell flows.</div>
      )}
    </div>
  );
}
