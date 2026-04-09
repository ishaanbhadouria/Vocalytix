import express from "express";
import multer from "multer";
import OpenAI from "openai";
import path from "node:path";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const webRoot = path.resolve(__dirname, "../build/web");

const app = express();
const upload = multer({
  storage: multer.memoryStorage(),
  limits: {
    fileSize: 25 * 1024 * 1024,
  },
});

const apiKey = process.env.OPENAI_API_KEY ?? "";
const transcriptionModel =
  process.env.OPENAI_TRANSCRIPTION_MODEL ?? "gpt-4o-mini-transcribe";
const feedbackModel = process.env.OPENAI_FEEDBACK_MODEL ?? "gpt-5-mini";
const client = apiKey ? new OpenAI({ apiKey }) : null;

app.use(express.json({ limit: "1mb" }));

app.get("/api/health", (_req, res) => {
  res.json({
    ok: true,
    openaiConfigured: Boolean(client),
    transcriptionModel,
    feedbackModel,
  });
});

function modeSpecificFeedbackGoal(mode) {
  switch (mode) {
    case "interview":
      return "clear ownership, decisive action, and measurable result";
    case "presentation":
      return "a crisp recommendation, evidence, and audience takeaway";
    case "speech":
      return "a memorable arc, emotional movement, and a clean message";
    case "informal":
      return "natural warmth, clarity, and relatable detail";
    case "formal":
      return "executive clarity, prioritization, and precise language";
    case "tutorials":
      return "step-by-step clarity, examples, and confidence for the listener";
    default:
      return "clear structure, specificity, and audience relevance";
  }
}

function extractResponseText(responseBody) {
  if (typeof responseBody.output_text === "string" && responseBody.output_text) {
    return responseBody.output_text;
  }

  const parts = [];
  for (const outputItem of responseBody.output ?? []) {
    for (const contentItem of outputItem.content ?? []) {
      if (contentItem.type === "output_text" && typeof contentItem.text === "string") {
        parts.push(contentItem.text);
      }
    }
  }
  return parts.join("\n").trim();
}

app.post("/api/transcribe", upload.single("audio"), async (req, res) => {
  if (!client) {
    return res.status(503).json({
      error: "OPENAI_API_KEY is not configured on the server.",
    });
  }

  const audio = req.file;
  if (!audio) {
    return res.status(400).json({
      error: "Audio file is required.",
    });
  }

  try {
    const prompt =
      typeof req.body.prompt === "string" && req.body.prompt.trim().length > 0
        ? req.body.prompt.trim()
        : undefined;

    const transcription = await client.audio.transcriptions.create({
      file: new File([audio.buffer], audio.originalname || "speech.webm", {
        type: audio.mimetype || "audio/webm",
      }),
      model: transcriptionModel,
      prompt,
    });

    return res.json({
      text: transcription.text?.trim() ?? "",
      model: transcriptionModel,
    });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Transcription failed.";
    return res.status(500).json({ error: message });
  }
});

app.post("/api/content-feedback", async (req, res) => {
  if (!client) {
    return res.status(503).json({
      error: "OPENAI_API_KEY is not configured on the server.",
    });
  }

  const transcript =
    typeof req.body?.transcript === "string" ? req.body.transcript.trim() : "";
  if (!transcript) {
    return res.status(400).json({
      error: "Transcript is required.",
    });
  }

  const mode =
    typeof req.body?.mode === "string" && req.body.mode.trim().length > 0
      ? req.body.mode.trim()
      : "presentation";

  const payload = {
    mode,
    modeGoal: modeSpecificFeedbackGoal(mode),
    transcript,
    delivery: req.body?.delivery ?? {},
    localAnalysis: req.body?.localAnalysis ?? {},
    recentReports: Array.isArray(req.body?.recentReports)
      ? req.body.recentReports.slice(0, 3)
      : [],
  };

  try {
    const openAiResponse = await fetch("https://api.openai.com/v1/responses", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        Authorization: `Bearer ${apiKey}`,
      },
      body: JSON.stringify({
        model: feedbackModel,
        input: [
          {
            role: "system",
            content: [
              {
                type: "input_text",
                text:
                  "You are Avaixa, a speaking coach. Return personalized content coaching only. Focus on message quality, clarity, structure, specificity, and audience payoff. Use the user's mode and recent habits. Avoid generic filler or pace coaching unless it directly changes the content. Be encouraging but honest.",
              },
            ],
          },
          {
            role: "user",
            content: [
              {
                type: "input_text",
                text:
                  "Analyze this speaking transcript and return JSON. Requirements: score content from 0 to 100, give exactly 4 short personalized feedback bullets, make them actionable, and reference the speaker's actual wording or recurring pattern when helpful. Prioritize what will make the next rep stronger, more human, and more mode-specific.\n\n" +
                  JSON.stringify(payload),
              },
            ],
          },
        ],
        text: {
          format: {
            type: "json_schema",
            name: "content_feedback",
            strict: true,
            schema: {
              type: "object",
              additionalProperties: false,
              properties: {
                contentScore: {
                  type: "number",
                  minimum: 0,
                  maximum: 100,
                },
                contentFeedback: {
                  type: "array",
                  minItems: 4,
                  maxItems: 4,
                  items: {
                    type: "string",
                  },
                },
              },
              required: ["contentScore", "contentFeedback"],
            },
          },
        },
      }),
    });

    const responseBody = await openAiResponse.json();
    if (!openAiResponse.ok) {
      return res.status(openAiResponse.status).json({
        error:
          responseBody?.error?.message ??
          "OpenAI content feedback request failed.",
      });
    }

    const responseText = extractResponseText(responseBody);
    const parsed = JSON.parse(responseText);
    const contentScore = Number(parsed.contentScore);
    const contentFeedback = Array.isArray(parsed.contentFeedback)
      ? parsed.contentFeedback
          .map((item) => item?.toString().trim() ?? "")
          .filter(Boolean)
          .slice(0, 4)
      : [];

    if (!Number.isFinite(contentScore) || contentFeedback.length < 3) {
      return res.status(502).json({
        error: "OpenAI returned an invalid content feedback payload.",
      });
    }

    return res.json({
      contentScore: Math.max(0, Math.min(100, contentScore)),
      contentFeedback,
      model: feedbackModel,
    });
  } catch (error) {
    const message =
      error instanceof Error ? error.message : "Content feedback failed.";
    return res.status(500).json({ error: message });
  }
});

app.use(express.static(webRoot));

app.get("*", (_req, res) => {
  res.sendFile(path.join(webRoot, "index.html"));
});

const port = Number(process.env.PORT || 8080);
app.listen(port, () => {
  console.log(`Avaixa server listening on ${port}`);
});
