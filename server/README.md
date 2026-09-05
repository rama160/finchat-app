# Finchat AI Proxy (opsional untuk production)

V4 tetap bisa dijalankan langsung dengan API key di perangkat untuk development/testing.
Untuk aplikasi publik, gunakan proxy ini agar API key Gemini tidak pernah masuk ke APK.

## Jalankan

```bash
npm install
GEMINI_API_KEY="AIza..." npm start
```

Endpoint:

```text
POST /v1/gemini/generate
GET  /health
```

Simpan `GEMINI_API_KEY` hanya sebagai environment secret pada server/hosting.
Jangan commit key ke GitHub.
