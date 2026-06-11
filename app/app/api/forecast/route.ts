import { NextRequest, NextResponse } from "next/server";
import {
  TENORS,
  type ForecastLocation,
  type ForecastResponse,
  type TenorPoint,
} from "@/lib/types";
import { BASE_CURVE_PERCENT, mockForecast } from "@/lib/baseCurve";

export const runtime = "nodejs";

const LOOKBACK = 10; // days of history the model expects (10 days x 9 tenors = 90 features)

// Declares where this dashboard instance is running so the UI can show the
// truth: "cloud" for Act 1 (model service in Azure) or "edge" for Act 2
// (Foundry Local on Azure Local). Defaults to cloud.
const DEPLOYMENT_TARGET: ForecastLocation =
  process.env.DEPLOYMENT_TARGET === "edge" ? "edge" : "cloud";

// Allow self-signed edge ingress certs when explicitly opted in (demo only).
// Applied process-wide at module load; scoped to this server-side route.
if (process.env.FOUNDRY_INSECURE_TLS === "true") {
  process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0";
}

/**
 * Build the model's 90-element feature vector: a flattened 10-day lookback of
 * the 9 tenor yields, in DECIMAL (model trained on decimals, e.g. 0.0485). A
 * synthetic flat history of the scenario-shifted base curve is used so the demo
 * is deterministic. Row-major order (day-major, tenor-minor) matches training.
 */
function buildFeatures(scenarioBps: number): number[] {
  const shiftedDecimal = TENORS.map(
    (t) => (BASE_CURVE_PERCENT[t.key] + scenarioBps / 100) / 100,
  );
  const features: number[] = [];
  for (let day = 0; day < LOOKBACK; day++) {
    features.push(...shiftedDecimal);
  }
  return features;
}

/** Decode the Foundry Local predictive response into the 9 predicted yields (percent). */
function decodePrediction(data: unknown): number[] {
  const items = (data as { items?: { data?: string }[] }).items;
  const b64 = items?.[0]?.data;
  if (!b64) throw new Error("predictive response missing items[0].data");
  const obj = JSON.parse(Buffer.from(b64, "base64").toString("utf-8")) as Record<
    string,
    number[][] | number[]
  >;
  const firstKey = Object.keys(obj)[0];
  const raw = obj[firstKey];
  const flat = Array.isArray(raw[0]) ? (raw[0] as number[]) : (raw as number[]);
  // Model outputs decimal yields -> convert to percent for display.
  return flat.map((v) => v * 100);
}

/**
 * POST /api/forecast
 * Body: { scenarioBps: number }
 *
 * Calls a predictive inference endpoint that speaks the Foundry Local contract.
 * In Act 1 this is the cloud service; in Act 2 it is the Azure Local edge
 * deployment — the protocol is identical, so only FOUNDRY_ENDPOINT changes.
 * Falls back to a deterministic mock so the UI works offline.
 */
export async function POST(req: NextRequest) {
  const { scenarioBps = 0 } = await req.json().catch(() => ({ scenarioBps: 0 }));

  const endpoint = process.env.FOUNDRY_ENDPOINT;
  const apiKey = process.env.FOUNDRY_API_KEY;
  const modelId = process.env.FOUNDRY_MODEL_ID ?? "rate-forecast:v1";

  const started = Date.now();

  // ---- Edge/cloud mode: call the live predictive endpoint (Foundry contract) ----
  if (endpoint) {
    try {
      const features = buildFeatures(scenarioBps);
      const encoded = Buffer.from(JSON.stringify([features])).toString("base64");

      const headers: Record<string, string> = { "Content-Type": "application/json" };
      if (apiKey) {
        // Cloud FastAPI checks X-API-KEY; the Foundry Local operator's nginx
        // sidecar checks "api-key" / "Authorization: Bearer". Send all so the
        // same image works against either target.
        headers["X-API-KEY"] = apiKey;
        headers["api-key"] = apiKey;
        headers["Authorization"] = `Bearer ${apiKey}`;
      }

      const res = await fetch(`${endpoint.replace(/\/$/, "")}/v1/predict`, {
        method: "POST",
        headers,
        body: JSON.stringify({
          items: [{ content_type: "application/json", encoder: "base64", data: encoded }],
        }),
      });

      if (!res.ok) throw new Error(`Edge endpoint returned ${res.status}`);
      const data = await res.json();
      const predicted = decodePrediction(data);
      if (predicted.length !== TENORS.length) {
        throw new Error(`expected ${TENORS.length} outputs, got ${predicted.length}`);
      }

      const curve: TenorPoint[] = TENORS.map((t, i) => ({
        label: t.label,
        months: t.months,
        product: t.product,
        base: BASE_CURVE_PERCENT[t.key],
        forecast: Number(predicted[i].toFixed(3)),
      }));

      const payload: ForecastResponse = {
        location: DEPLOYMENT_TARGET,
        modelId,
        latencyMs: Date.now() - started,
        scenarioBps,
        curve,
        generatedAt: new Date().toISOString(),
      };
      return NextResponse.json(payload);
    } catch (err) {
      // Fall through to mock so the demo never hard-fails, but flag it.
      console.error("Live inference failed, using sample data:", err);
    }
  }

  // ---- Offline mode: deterministic built-in sample forecast ----
  const forecast = mockForecast(scenarioBps);
  const curve: TenorPoint[] = TENORS.map((t) => ({
    label: t.label,
    months: t.months,
    product: t.product,
    base: BASE_CURVE_PERCENT[t.key],
    forecast: forecast[t.key],
  }));

  const payload: ForecastResponse = {
    location: "offline",
    modelId,
    latencyMs: Date.now() - started,
    scenarioBps,
    curve,
    generatedAt: new Date().toISOString(),
  };
  return NextResponse.json(payload);
}
