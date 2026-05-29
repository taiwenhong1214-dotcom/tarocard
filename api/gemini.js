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

    // 获取我们刚刚在 Vercel 填写的 DeepSeek Key
    const apiKey = process.env.DEEPSEEK_API_KEY;

    if (!apiKey) {
      return res.status(500).json({
        error: "Missing DEEPSEEK_API_KEY in Vercel Environment Variables"
      });
    }

    // 🌟 核心改动：向 DeepSeek API 发送请求 (兼容 OpenAI 格式)
    const deepseekRes = await fetch(
      "https://api.deepseek.com/chat/completions",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "Authorization": `Bearer ${apiKey}` // DeepSeek 使用 Bearer 鉴权
        },
        body: JSON.stringify({
          model: "deepseek-v4-flash", // DeepSeek 的通用大模型
          messages: [
            { role: "user", content: prompt }
          ],
          temperature: 0.7 // 设为 0.7 让塔罗牌解读更有灵性和创造力
        })
      }
    );

    const data = await deepseekRes.json();

    if (!deepseekRes.ok) {
      return res.status(deepseekRes.status).json(data);
    }

    // 🌟 核心改动：解析 DeepSeek 的返回格式
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