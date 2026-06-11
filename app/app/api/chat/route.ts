import { NextRequest, NextResponse } from "next/server";

export const runtime = "nodejs";

// Where the generative model runs. In Act 3 this is the phi-4-cpu generative
// deployment on Foundry Local (Azure Local edge). Same sovereign story as the
// predictive model: in-cluster endpoint, no data leaves the appliance.
const DEPLOYMENT_TARGET = process.env.DEPLOYMENT_TARGET === "edge" ? "edge" : "cloud";

// Allow self-signed edge ingress certs when explicitly opted in (demo only).
if (process.env.FOUNDRY_INSECURE_TLS === "true") {
  process.env.NODE_TLS_REJECT_UNAUTHORIZED = "0";
}

const SYSTEM_PROMPT =
  "You are a concise banking assistant for a rate-forecasting dashboard. " +
  "Answer in plain language for a non-technical banker, in at most three short sentences. " +
  "Focus on what interest-rate moves mean for savings and mortgage products.";

/**
 * POST /api/chat
 * Body: { message: string, scenarioBps?: number }
 *
 * Calls a generative chat endpoint that speaks the Foundry Local
 * OpenAI-compatible contract (/v1/chat/completions). At the edge this is the
 * phi-4-cpu model running on Azure Local.
 */
export async function POST(req: NextRequest) {
  const { message = "", scenarioBps } = await req
    .json()
    .catch(() => ({ message: "" }));

  const endpoint = process.env.FOUNDRY_CHAT_ENDPOINT;
  const apiKey = process.env.FOUNDRY_CHAT_API_KEY;
  const model = process.env.FOUNDRY_CHAT_MODEL ?? "Phi-4-generic-cpu";

  if (!message.trim()) {
    return NextResponse.json({ error: "message is required" }, { status: 400 });
  }

  // No generative model wired up (e.g. cloud Act 1) — be honest about it.
  if (!endpoint) {
    return NextResponse.json({
      location: "offline",
      model,
      reply:
        "The AI analyst is only available at the edge in this demo, where the " +
        "phi-4 model runs on Azure Local. No generative model is connected here.",
    });
  }

  const userContent =
    typeof scenarioBps === "number"
      ? `Scenario: the central bank changes rates by ${(scenarioBps / 100).toFixed(2)}%. ${message}`
      : message;

  const started = Date.now();
  try {
    const res = await fetch(`${endpoint.replace(/\/$/, "")}/v1/chat/completions`, {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        // Foundry Local generative sidecar accepts api-key or Bearer.
        ...(apiKey ? { "api-key": apiKey, Authorization: `Bearer ${apiKey}` } : {}),
      },
      body: JSON.stringify({
        model,
        messages: [
          { role: "system", content: SYSTEM_PROMPT },
          { role: "user", content: userContent },
        ],
        max_tokens: 160,
        temperature: 0.3,
      }),
    });

    if (!res.ok) throw new Error(`Chat endpoint returned ${res.status}`);
    const data = (await res.json()) as {
      choices?: { message?: { content?: string } }[];
    };
    const reply = data.choices?.[0]?.message?.content?.trim() ?? "";

    return NextResponse.json({
      location: DEPLOYMENT_TARGET,
      model,
      latencyMs: Date.now() - started,
      reply: reply || "(no response)",
    });
  } catch (err) {
    console.error("Chat inference failed:", err);
    return NextResponse.json(
      {
        location: "offline",
        model,
        reply:
          "Sorry — the AI analyst is unavailable right now. The generative model " +
          "may still be starting up.",
      },
      { status: 200 },
    );
  }
}
