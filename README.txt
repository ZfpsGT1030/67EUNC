What changed:
- Moved API handlers into /api so Vercel exposes them as /api/results and /api/result
- Added "type": "module" to package.json so import/export works in plain Vercel Functions
- Added vercel.json rewrite so /result/<id> loads result.html
- Updated result.html to support both /result/<id> and result.html?id=<id>
- Added index.html so the site root no longer 404s
- Updated unc_tester.lua to post to the stable main deployment URL

Deploy structure:
/
  api/result.js
  api/results.js
  index.html
  result.html
  vercel.json
  package.json
  unc_tester.lua

Important:
- In Vercel, connect a KV database to this project. @vercel/kv needs the Vercel-provided environment variables.
- After replacing the repo contents, redeploy.
