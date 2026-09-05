import express from 'express';

const app = express();
app.use(express.json({ limit: '12mb' }));

const port = process.env.PORT || 8080;
const geminiKey = process.env.GEMINI_API_KEY;
const model = process.env.GEMINI_MODEL || 'gemini-2.5-flash';

app.get('/health', (_req, res) => {
  res.json({ ok: true, model });
});

app.post('/v1/gemini/generate', async (req, res) => {
  if (!geminiKey) {
    return res.status(500).json({ error: { message: 'GEMINI_API_KEY belum dikonfigurasi di server.' } });
  }

  if (!req.body || !Array.isArray(req.body.contents)) {
    return res.status(400).json({ error: { message: 'Request contents tidak valid.' } });
  }

  try {
    const url = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent?key=${encodeURIComponent(geminiKey)}`;
    const response = await fetch(url, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        contents: req.body.contents,
        generationConfig: req.body.generationConfig,
      }),
    });

    const body = await response.text();
    res.status(response.status).type('application/json').send(body);
  } catch (error) {
    res.status(502).json({ error: { message: `Gemini upstream gagal: ${error.message}` } });
  }
});

app.listen(port, () => {
  console.log(`Finchat AI proxy listening on :${port}`);
});
