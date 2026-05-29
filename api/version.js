module.exports = async function handler(req, res) {
    // 设置 CORS 跨域
    res.setHeader("Access-Control-Allow-Origin", "*");
    res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  
    if (req.method === "OPTIONS") {
      return res.status(200).end();
    }
  
    // 随时可以在此处修改最新的版本号和你的 APK 安装包下载链接
    return res.status(200).json({
      latestVersion: "2.0.1", 
      downloadUrl: "https://tai-taro.vercel.app/download/tarot-v2.0.1.apk" // 👈 替换成你真实的 APK 下载地址
    });
  };