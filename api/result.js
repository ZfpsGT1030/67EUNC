import { kv } from "@vercel/kv";

export default async function handler(req, res) {
  res.setHeader("Access-Control-Allow-Origin", "*");
  res.setHeader("Access-Control-Allow-Methods", "GET, OPTIONS");
  res.setHeader("Access-Control-Allow-Headers", "Content-Type");

  if (req.method === "OPTIONS") return res.status(200).end();
  if (req.method !== "GET") {
    return res.status(405).json({ error: "Method Not Allowed" });
  }

  const { id } = req.query;
  if (!id || typeof id !== "string" || !/^[a-f0-9]{16}$/i.test(id)) {
    return res.status(400).json({ error: "Invalid or missing id" });
  }

  try {
    const data = await kv.get(`result:${id.toLowerCase()}`);
    if (data === null) {
      return res.status(404).json({ error: "Result not found or expired (7-day TTL)" });
    }
    return res.status(200).json(data);
  } catch (err) {
    console.error("[result] error:", err);
    return res.status(500).json({
      error: "Internal server error",
      hint: "Make sure Vercel KV is connected and environment variables are available in this deployment."
    });
  }
}
