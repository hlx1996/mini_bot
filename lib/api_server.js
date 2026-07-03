#!/usr/bin/env node
// lib/api_server.js — OpenAI-compatible HTTP server for mini_bot.
// Routes: fuyao-* → direct to Fuyao gateway; others → qodercli bridge.
// Env: BOT_API_PORT (default 9877), FUYAO_API_KEY, FUYAO_BASE_URL, QODER_BIN

const http = require("node:http");
const { spawn } = require("node:child_process");
const { createInterface } = require("node:readline");

const PORT = parseInt(process.env.BOT_API_PORT || "9877", 10);
const FUYAO_API_KEY = process.env.FUYAO_API_KEY || "0e67604fbf554ba7b5727d875af13c13";
const FUYAO_BASE_URL = process.env.FUYAO_BASE_URL || "https://fuyao-ai-gateway.xiaopeng.link/v1";
const QODER_BIN = process.env.QODER_BIN || "qodercli";

const FUYAO_MODELS = new Set(["fuyao-deepseek", "fuyao-glm", "fuyao-kimi"]);

const ALL_MODES = [
  { id: "lite", name: "MB-Lite" },
  { id: "efficient", name: "MB-Efficient" },
  { id: "auto", name: "MB-Auto" },
  { id: "dfmodel", name: "MB-DeepSeek-V4-Flash" },
  { id: "dmodel", name: "MB-DeepSeek-V4-Pro" },
  { id: "gmodel", name: "MB-GLM-5" },
  { id: "gm51model", name: "MB-GLM-5.1" },
  { id: "kmodel", name: "MB-Kimi-K2.6" },
  { id: "mmodel", name: "MB-MiniMax-M2.7" },
  { id: "q35model", name: "MB-Qwen3.5-Plus" },
  { id: "qmodel", name: "MB-Qwen3.6-Plus" },
  { id: "qmodel_latest", name: "MB-Qwen3.7-Max" },
  { id: "performance", name: "MB-Performance" },
  { id: "ultimate", name: "MB-Ultimate" },
  { id: "fuyao-deepseek", name: "MB-Fuyao-DeepSeek" },
  { id: "fuyao-glm", name: "MB-Fuyao-GLM" },
  { id: "fuyao-kimi", name: "MB-Fuyao-Kimi" },
];

function log(msg) {
  process.stderr.write(`[api] ${new Date().toISOString()} ${msg}\n`);
}

function isFuyaoModel(model) {
  return FUYAO_MODELS.has(model) || model.startsWith("fuyao-");
}

// ── Fuyao direct (streaming proxy) ──────────────────────────────

async function handleFuyaoStream(model, messages, extraParams, res) {
  const body = JSON.stringify({
    model,
    messages,
    stream: true,
    ...extraParams,
  });

  const upstream = await fetch(`${FUYAO_BASE_URL}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${FUYAO_API_KEY}`,
    },
    body,
  });

  if (!upstream.ok) {
    const errText = await upstream.text();
    log(`fuyao ERROR ${upstream.status}: ${errText.slice(0, 200)}`);
    res.writeHead(upstream.status, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ error: { message: errText, type: "upstream_error" } }));
    return;
  }

  res.writeHead(200, {
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache",
    Connection: "keep-alive",
  });

  const reader = upstream.body.getReader();
  const decoder = new TextDecoder();

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    const text = decoder.decode(value, { stream: true });

    for (const line of text.split("\n")) {
      if (!line.startsWith("data: ")) continue;
      const payload = line.slice(6);

      if (payload === "[DONE]") {
        res.write("data: [DONE]\n\n");
        continue;
      }

      try {
        const chunk = JSON.parse(payload);
        // Merge reasoning into content if content is null
        for (const choice of chunk.choices || []) {
          if (choice.delta?.content == null && choice.delta?.reasoning) {
            choice.delta.content = "";
          }
        }
        res.write(`data: ${JSON.stringify(chunk)}\n\n`);
      } catch {
        // skip malformed lines
      }
    }
  }

  res.end();
}

async function handleFuyaoNonStream(model, messages, extraParams, res) {
  const body = JSON.stringify({ model, messages, ...extraParams });

  const upstream = await fetch(`${FUYAO_BASE_URL}/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${FUYAO_API_KEY}`,
    },
    body,
  });

  const text = await upstream.text();
  res.writeHead(upstream.status, { "Content-Type": "application/json" });

  try {
    const data = JSON.parse(text);
    // If content is null but reasoning exists, use reasoning as content
    for (const choice of data.choices || []) {
      if (choice.message?.content == null && choice.message?.reasoning) {
        choice.message.content = choice.message.reasoning;
      }
    }
    res.end(JSON.stringify(data));
  } catch {
    res.end(text);
  }
}

// ── qodercli bridge (streaming) ──────────────────────────────────

function handleQodercliStream(model, messages, res) {
  const lastUser = [...messages].reverse().find((m) => m.role === "user");
  const prompt = lastUser?.content || "";

  const args = [
    "-p", prompt,
    "-m", model,
    "--output-format", "stream-json",
    "--permission-mode", "bypass_permissions",
  ];

  log(`qodercli spawn model=${model} prompt=${prompt.slice(0, 60)}...`);

  const proc = spawn(QODER_BIN, args, { stdio: ["ignore", "pipe", "pipe"] });

  res.writeHead(200, {
    "Content-Type": "text/event-stream",
    "Cache-Control": "no-cache",
    Connection: "keep-alive",
  });

  const chatId = `chatcmpl-${Date.now()}`;
  const created = Math.floor(Date.now() / 1000);
  let sentRole = false;

  const rl = createInterface({ input: proc.stdout });
  rl.on("line", (line) => {
    if (!line.trim()) return;
    try {
      const evt = JSON.parse(line);
      if (evt.type === "text" && evt.part?.text) {
        const delta = {};
        if (!sentRole) {
          delta.role = "assistant";
          sentRole = true;
        }
        delta.content = evt.part.text;
        const chunk = {
          id: chatId,
          object: "chat.completion.chunk",
          created,
          model,
          choices: [{ index: 0, delta, finish_reason: null }],
        };
        res.write(`data: ${JSON.stringify(chunk)}\n\n`);
      }
    } catch {
      // skip non-JSON lines
    }
  });

  proc.on("close", (code) => {
    const done = {
      id: chatId,
      object: "chat.completion.chunk",
      created,
      model,
      choices: [{ index: 0, delta: {}, finish_reason: "stop" }],
    };
    res.write(`data: ${JSON.stringify(done)}\n\n`);
    res.write("data: [DONE]\n\n");
    res.end();
    log(`qodercli done model=${model} rc=${code}`);
  });

  proc.on("error", (err) => {
    log(`qodercli ERROR: ${err.message}`);
    res.end();
  });

  proc.stderr.on("data", (d) => {
    // swallow stderr
  });
}

function handleQodercliNonStream(model, messages, res) {
  const lastUser = [...messages].reverse().find((m) => m.role === "user");
  const prompt = lastUser?.content || "";

  const args = [
    "-p", prompt,
    "-m", model,
    "--permission-mode", "bypass_permissions",
  ];

  const proc = spawn(QODER_BIN, args, { stdio: ["ignore", "pipe", "ignore"] });
  let output = "";

  proc.stdout.on("data", (d) => { output += d; });
  proc.on("close", () => {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({
      id: `chatcmpl-${Date.now()}`,
      object: "chat.completion",
      created: Math.floor(Date.now() / 1000),
      model,
      choices: [{ index: 0, message: { role: "assistant", content: output.trim() }, finish_reason: "stop" }],
      usage: { prompt_tokens: 0, completion_tokens: 0, total_tokens: 0 },
    }));
  });
}

// ── HTTP server ──────────────────────────────────────────────────

const server = http.createServer(async (req, res) => {
  if (req.method === "GET" && (req.url === "/v1/models" || req.url === "/v1/models/")) {
    const models = ALL_MODES.map((m) => ({
      id: m.id,
      object: "model",
      owned_by: "mini-bot",
    }));
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ object: "list", data: models }));
    return;
  }

  if (req.method === "GET" && req.url === "/health") {
    res.writeHead(200, { "Content-Type": "application/json" });
    res.end(JSON.stringify({ status: "ok", models: ALL_MODES.length }));
    return;
  }

  if (req.method === "POST" && (req.url === "/v1/chat/completions" || req.url === "/v1/chat/completions/")) {
    let body = "";
    for await (const chunk of req) body += chunk;

    try {
      const parsed = JSON.parse(body);
      const rawModel = parsed.model || "lite";
      const model = rawModel.startsWith("mb-") ? rawModel.slice(3) : rawModel;
      const messages = parsed.messages || [];
      const stream = !!parsed.stream;

      const extraParams = {};
      if (parsed.temperature != null) extraParams.temperature = parsed.temperature;
      if (parsed.max_tokens != null) extraParams.max_tokens = parsed.max_tokens;
      if (parsed.top_p != null) extraParams.top_p = parsed.top_p;

      log(`${model} stream=${stream} msgs=${messages.length}`);

      if (isFuyaoModel(model)) {
        if (stream) {
          await handleFuyaoStream(model, messages, extraParams, res);
        } else {
          await handleFuyaoNonStream(model, messages, extraParams, res);
        }
      } else {
        if (stream) {
          handleQodercliStream(model, messages, res);
        } else {
          handleQodercliNonStream(model, messages, res);
        }
      }
    } catch (err) {
      log(`ERROR: ${err.message}`);
      res.writeHead(500, { "Content-Type": "application/json" });
      res.end(JSON.stringify({ error: { message: err.message, type: "server_error" } }));
    }
    return;
  }

  res.writeHead(404);
  res.end("Not Found");
});

server.listen(PORT, () => {
  log(`listening on http://localhost:${PORT}`);
  log(`fuyao models: direct to ${FUYAO_BASE_URL}`);
  log(`other models: via ${QODER_BIN}`);
  log(`${ALL_MODES.length} models available`);
});
