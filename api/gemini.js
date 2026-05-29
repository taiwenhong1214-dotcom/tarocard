module.exports = async function handler(req, res) {
  // 设置跨域 CORS
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "POST, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type, x-app-version");

  if (req.method === "OPTIONS") {
    return res.status(200).end();
  }

  // 🔒 拒绝旧版 App（版本号拦截）
  if (req.headers['x-app-version'] !== '2.0.0') {
    return res.status(403).json({ error: "请更新 App 才能继续使用" });
  }

  if (req.method !== "POST") {
    return res.status(405).json({ error: "Only POST allowed" });
  }

  try {
    const { prompt } = req.body;

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
            "stepfun/step-3.5-flash", //阶跃星辰最新极速模型
            "deepseek/deepseek-v4-flash",    // 1. 首选：谷歌最新主力模型
            "qwen/qwen3.6-flash"          // 2. 备选：通义千问最新旗舰模型
          ],
          messages: [
            { role: "user", content: prompt }
          ],
          temperature: 0.7 
        })
      }
    );

    const data = await openRouterRes.json();

    if (!openRouterRes.ok) {
      return res.status(openRouterRes.status).json(data);
    }

    // 解析 OpenRouter 的返回格式
    const text = data?.choices?.[0]?.message?.content || "占卜师暂时无法解读，请稍后再试。";

    return res.status(200).json({ text });
  } catch (error) {
    console.error("Vercel 执行错误:", error);
    return res.status(500).json({
      error: "Server error",
      detail: error.message
    });
  }
};
