const MODEL_QUEUE = [
  "nvidia/nemotron-3-ultra-550b-a55b:free",
  "openai/gpt-oss-120b:free",
  "poolside/laguna-m.1:free",
  "z-ai/glm-4.5-air:free",
];

module.exports = async function handler(req, res) {
  // 设置跨域 CORS
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, x-app-version");

  if (req.method === "OPTIONS") {
    return res.status(200).end();
  }

  // 🔒 拒绝旧版 App（版本号拦截）
  if (req.headers['x-app-version'] !== '2.1.0') {
    return res.status(403).json({ error: "请更新 App 才能继续使用" });
  }

  if (req.method !== "POST") {
    return res.status(405).json({ error: "Only POST allowed" });
  }

  try {
    const { prompt, max_tokens = 2048, moonPhase, userMood } = req.body;

    if (!prompt) {
      return res.status(400).json({ error: "Missing prompt" });
    }

    // 获取在 Vercel 填写的 OpenRouter Key
    const apiKey = process.env.OPENROUTER_API_KEY;

    if (!apiKey) {
      return res.status(500).json({
        error: "Missing OPENROUTER_API_KEY in Vercel Environment Variables"
      });
    }

    const payload = {
      messages: [
        {
          role: "system",
          content: (() => {
            let base = "You are a precise tarot reading assistant. The user's exact question inside the prompt is the highest-priority context. First answer that question directly, then use every card and spread position as supporting evidence. Never replace the question with a generic reading. Do not claim certainty or invent personal facts. Follow the requested response language and format.";
            if (moonPhase || userMood) {
              base += "\n\n### Current Astrological & Personal Context:\n";
              if (moonPhase) base += `- Moon Phase: ${moonPhase}\n`;
              if (userMood) base += `- User's current mood: ${userMood}\n`;
              base += "Please subtly weave the energy of the Moon Phase and the user's mood into your interpretation to provide a multi-dimensional reading.";
            }
            return base;
          })()
        },
        { role: "user", content: prompt }
      ],
      temperature: 0.45,
      max_tokens: Math.min(Number(max_tokens) || 2048, 3000),
      stream: true,
      reasoning: { enabled: false }
    };

    // 🔄 服务端自动降级：逐个模型尝试。免费端点经常间歇性下线（404），
    // OpenRouter 的 models 数组不会为这类错误自动切换，所以这里手动轮询。
    let lastStatus = 502;
    let lastError = { error: "All models unavailable" };

    for (const model of MODEL_QUEUE) {
      const openRouterRes = await fetch(
        "https://openrouter.ai/api/v1/chat/completions",
        {
          method: "POST",
          headers: {
            "Content-Type": "application/json",
            "Authorization": `Bearer ${apiKey}`,
            "HTTP-Referer": "https://vercel.com",
            "X-Title": "Tarot App"
          },
          body: JSON.stringify({ ...payload, model })
        }
      );

      if (!openRouterRes.ok) {
        lastStatus = openRouterRes.status;
        try {
          lastError = await openRouterRes.json();
        } catch (parseErr) {
          lastError = { error: `Model ${model} failed` };
        }
        console.error(`[${model}] failed (${lastStatus}):`, JSON.stringify(lastError));
        continue;
      }

      // ✅ 命中可用模型：设置流式响应头并透传
      res.setHeader("Content-Type", "text/event-stream; charset=utf-8");
      res.setHeader("Cache-Control", "no-cache, no-transform");
      res.setHeader("Connection", "keep-alive");

      const reader = openRouterRes.body.getReader();
      const decoder = new TextDecoder("utf-8");

      while (true) {
        const { done, value } = await reader.read();
        if (done) break;
        res.write(decoder.decode(value, { stream: true }));
      }

      res.end();
      return;
    }

    // ❌ 所有模型都失败
    return res.status(lastStatus).json(lastError);
  } catch (error) {
    console.error("Vercel 执行错误:", error);
    if (!res.headersSent) {
      return res.status(500).json({
        error: "Server error",
        detail: error.message
      });
    } else {
      res.end();
    }
  }
};
