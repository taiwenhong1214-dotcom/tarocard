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
    const { prompt, max_tokens = 2048 } = req.body;

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

    // 🌟 核心改动：向 OpenRouter API 发送请求并配置最新模型队列
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
        body: JSON.stringify({
          // 🔄 自动降级队列：按首选顺序排列。前一个触发限流或下线时，OpenRouter 会直接切到下一个。
          models: [
            "openai/gpt-oss-120b:free",
            "poolside/laguna-m.1:free",
            "z-ai/glm-4.5-air:free",
          ],
          messages: [
            {
              role: "system",
              content: "You are a precise tarot reading assistant. The user's exact question inside the prompt is the highest-priority context. First answer that question directly, then use every card and spread position as supporting evidence. Never replace the question with a generic reading. Do not claim certainty or invent personal facts. Follow the requested response language and format."
            },
            { role: "user", content: prompt }
          ],
          temperature: 0.45,
          max_tokens: Math.min(Number(max_tokens) || 2048, 3000),
          stream: true
        })
      }
    );

    if (!openRouterRes.ok) {
      const data = await openRouterRes.json();
      return res.status(openRouterRes.status).json(data);
    }

    // 设置流式响应头
    res.setHeader("Content-Type", "text/event-stream; charset=utf-8");
    res.setHeader("Cache-Control", "no-cache, no-transform");
    res.setHeader("Connection", "keep-alive");

    // 将 OpenRouter 返回的 ReadableStream 逐块写入 Vercel response
    const reader = openRouterRes.body.getReader();
    const decoder = new TextDecoder("utf-8");

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;
      res.write(decoder.decode(value, { stream: true }));
    }
    
    res.end();
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
