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
const client = apiKey ? new OpenAI({ apiKey }) : null;

app.use(express.json({ limit: "1mb" }));

app.get("/api/health", (_req, res) => {
  res.json({
    ok: true,
    openaiConfigured: Boolean(client),
    transcriptionModel,
  });
});

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

app.use(express.static(webRoot));

app.get("*", (_req, res) => {
  res.sendFile(path.join(webRoot, "index.html"));
});

const port = Number(process.env.PORT || 8080);
app.listen(port, () => {
  console.log(`Avaixa server listening on ${port}`);
});
