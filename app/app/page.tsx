"use client";

import { useCallback, useEffect, useState } from "react";
import { CurveChart } from "@/components/CurveChart";
import type { ForecastResponse } from "@/lib/types";

const PRESETS = [
  { label: "Raise rates a lot", sub: "+1.0%", bps: 100 },
  { label: "Raise rates", sub: "+0.5%", bps: 50 },
  { label: "No change", sub: "0%", bps: 0 },
  { label: "Cut rates", sub: "−0.25%", bps: -25 },
  { label: "Cut rates a lot", sub: "−1.0%", bps: -100 },
];

const LOCATION_LABEL: Record<string, string> = {
  cloud: "Running in Azure (Cloud)",
  edge: "Running at the Edge — Foundry Local on Azure Local",
  offline: "Offline — showing sample data",
};

type ChatTurn = { role: "user" | "assistant"; content: string };

export default function Home() {
  const [scenarioBps, setScenarioBps] = useState(0);
  const [data, setData] = useState<ForecastResponse | null>(null);
  const [loading, setLoading] = useState(false);

  const [chatInput, setChatInput] = useState("");
  const [chatTurns, setChatTurns] = useState<ChatTurn[]>([]);
  const [chatLoading, setChatLoading] = useState(false);

  const runForecast = useCallback(async (bps: number) => {
    setLoading(true);
    try {
      const res = await fetch("/api/forecast", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ scenarioBps: bps }),
      });
      setData(await res.json());
    } finally {
      setLoading(false);
    }
  }, []);

  const askAnalyst = useCallback(
    async (question: string) => {
      const q = question.trim();
      if (!q || chatLoading) return;
      setChatTurns((t) => [...t, { role: "user", content: q }]);
      setChatInput("");
      setChatLoading(true);
      try {
        const res = await fetch("/api/chat", {
          method: "POST",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({ message: q, scenarioBps }),
        });
        const json = await res.json();
        setChatTurns((t) => [
          ...t,
          { role: "assistant", content: json.reply ?? "(no response)" },
        ]);
      } catch {
        setChatTurns((t) => [
          ...t,
          { role: "assistant", content: "Sorry — the AI analyst is unavailable right now." },
        ]);
      } finally {
        setChatLoading(false);
      }
    },
    [scenarioBps, chatLoading],
  );

  // Re-run the forecast shortly after the scenario changes.
  useEffect(() => {
    const id = setTimeout(() => runForecast(scenarioBps), 150);
    return () => clearTimeout(id);
  }, [scenarioBps, runForecast]);

  const pct = (n: number) => `${n >= 0 ? "+" : ""}${(n / 100).toFixed(2)}%`;
  const highlights = data?.curve.filter((c) =>
    ["1Y", "2Y", "5Y", "10Y"].includes(c.label),
  );

  return (
    <main className="container">
      <header className="header">
        <div>
          <h1 className="title">Interest Rate Forecaster</h1>
          <p className="subtitle">
            A bank uses its own AI model to predict where savings and mortgage
            rates are heading. Try a what-if below and watch the forecast update.
          </p>
        </div>
        <div className="badges">
          {data && (
            <span className={`badge ${data.location}`}>
              ● {LOCATION_LABEL[data.location]}
            </span>
          )}
        </div>
      </header>

      <div className="grid">
        <section className="panel">
          <h2>What if the central bank…</h2>
          <p className="hint">
            Pick a scenario. The AI model predicts how customer rates would
            respond.
          </p>

          <div className="preset-buttons">
            {PRESETS.map((p) => (
              <button
                key={p.label}
                className={`preset ${scenarioBps === p.bps ? "active" : ""}`}
                onClick={() => setScenarioBps(p.bps)}
              >
                <span className="preset-main">{p.label}</span>
                <span className="preset-sub">{p.sub}</span>
              </button>
            ))}
          </div>

          <div className="slider-row" style={{ marginTop: 24 }}>
            <label>
              <span>Fine-tune the rate change</span>
              <span className="value">{pct(scenarioBps)}</span>
            </label>
            <input
              type="range"
              min={-150}
              max={150}
              step={5}
              value={scenarioBps}
              onChange={(e) => setScenarioBps(Number(e.target.value))}
            />
          </div>

          <div className="stat-row" style={{ marginTop: 24 }}>
            <div className="stat">
              <div className="k">Where it ran</div>
              <div className="v small">
                {data ? (data.location === "edge" ? "Edge" : data.location === "cloud" ? "Cloud" : "Offline") : "—"}
              </div>
            </div>
            <div className="stat">
              <div className="k">Prediction time</div>
              <div className="v">{data ? `${data.latencyMs} ms` : "—"}</div>
            </div>
          </div>
        </section>

        <section className="panel">
          <h2>{loading ? "Predicting…" : "Forecast"}</h2>

          {highlights && (
            <div className="cards">
              {highlights.map((c) => {
                const delta = (c.forecast - c.base) * 100;
                return (
                  <div className="card" key={c.label}>
                    <div className="card-product">{c.product}</div>
                    <div className="card-rate">{c.forecast.toFixed(2)}%</div>
                    <div className={`card-delta ${delta >= 0 ? "up" : "down"}`}>
                      {delta >= 0 ? "▲" : "▼"} {Math.abs(delta).toFixed(0)} bps vs
                      today ({c.base.toFixed(2)}%)
                    </div>
                  </div>
                );
              })}
            </div>
          )}

          {data && <CurveChart curve={data.curve} />}
          <p className="hint" style={{ textAlign: "center" }}>
            Left = short-term rates (savings). Right = long-term rates (loans).
          </p>
        </section>
      </div>

      <section className="panel chat-panel">
        <h2>Ask the AI analyst</h2>
        <p className="hint">
          A second AI model (phi-4) running on the same edge appliance explains
          the forecast in plain language. Ask anything about the scenario.
        </p>

        <div className="chat-suggestions">
          {[
            "What does this mean for savers?",
            "Should we adjust our mortgage rates?",
            "Explain this forecast in one sentence.",
          ].map((s) => (
            <button
              key={s}
              className="chip"
              onClick={() => askAnalyst(s)}
              disabled={chatLoading}
            >
              {s}
            </button>
          ))}
        </div>

        {chatTurns.length > 0 && (
          <div className="chat-log">
            {chatTurns.map((turn, i) => (
              <div key={i} className={`chat-turn ${turn.role}`}>
                <span className="chat-who">
                  {turn.role === "user" ? "You" : "AI analyst"}
                </span>
                <p>{turn.content}</p>
              </div>
            ))}
            {chatLoading && (
              <div className="chat-turn assistant">
                <span className="chat-who">AI analyst</span>
                <p className="chat-thinking">Thinking…</p>
              </div>
            )}
          </div>
        )}

        <form
          className="chat-input-row"
          onSubmit={(e) => {
            e.preventDefault();
            askAnalyst(chatInput);
          }}
        >
          <input
            type="text"
            placeholder="Ask about the forecast…"
            value={chatInput}
            onChange={(e) => setChatInput(e.target.value)}
            disabled={chatLoading}
          />
          <button type="submit" disabled={chatLoading || !chatInput.trim()}>
            Ask
          </button>
        </form>
      </section>

      <p className="footer">
        AI model: {data?.modelId ?? "rate-forecast"} · Updated{" "}
        {data ? new Date(data.generatedAt).toLocaleTimeString() : "—"} ·{" "}
        {data?.location === "edge"
          ? "All predictions made on-premises — no data leaves the bank."
          : data?.location === "cloud"
            ? "Predictions made by the bank's model service in Azure."
            : "Showing built-in sample data (no live model connected)."}
      </p>
    </main>
  );
}

