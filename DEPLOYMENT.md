# Production deployment

Bridge uses a persistent, single-process Jac graph. The supported Vercel
architecture is therefore:

- a static client on Vercel;
- same-origin Vercel rewrites for `/user`, `/walker`, `/function`, and `/cl`;
- one persistent Jac backend on a container host;
- MongoDB for durable graph state.

The model key, JWT secret, and database URI belong on the backend. They must
never be added to Vercel's client bundle.

## 1. Backend

Configure the persistent backend host with:

```text
OPENAI_API_KEY=...
JWT_SECRET=...
MONGODB_URI=...
BRIDGE_ORG_ACCESS_CODE=...
BYLLM_DEFAULT_MODEL=gpt-4o-mini
```

Generate a JWT secret with:

```bash
openssl rand -hex 32
```

Use this start command:

```bash
./scripts/start_prod.sh
```

Do not use `jac start --scale` for Bridge. Splitting its modules into services
also splits the shared graph store.

After the backend is live, initialize the shared graph once:

```bash
curl -fsS -X POST \
  https://YOUR-BACKEND/function/bootstrap \
  -H 'Content-Type: application/json' \
  -d '{}'
```

When Railway provisions MongoDB with a 500 MB free/trial volume, deploy the
small wrapper image in `infra/mongodb` to the MongoDB service. It preserves the
official MongoDB 8 image and persistent volume while lowering MongoDB's
index-build free-space guard so Jac can create its authentication indexes:

```bash
railway up infra/mongodb --path-as-root --service MongoDB
```

To create the demo accounts and data:

```bash
BRIDGE_URL=https://YOUR-BACKEND ./scripts/seed_demo.sh
```

## 2. Vercel

Prepare an inspectable deployment bundle without deploying:

```bash
BRIDGE_BACKEND_URL=https://YOUR-BACKEND ./scripts/prepare_vercel.sh
```

The generated `.vercel-output/` directory is ignored by Git. It contains:

- the compiled static client under `public/`;
- a generated `vercel.json` that proxies Jac API routes to the backend;
- an SPA fallback to `index.html`;
- basic response security headers.

Deploy it to the authenticated Vercel account:

```bash
BRIDGE_BACKEND_URL=https://YOUR-BACKEND ./scripts/deploy_vercel.sh
```

The backend URL must use HTTPS. The deployment scripts do not read or upload
the model API key, JWT secret, MongoDB URI, or local `.env` files.

## 3. Verification

Exercise login through the Vercel domain to verify the rewrite:

```bash
curl -fsS -X POST \
  https://YOUR-APP.vercel.app/user/login \
  -H 'Content-Type: application/json' \
  -d '{"identity":{"type":"email","value":"maria@bridge.demo"},"credential":{"type":"password","password":"bridge::seeker::email-only::maria@bridge.demo"}}'
```

Then verify intake, pledging, matching, and state persistence across a backend
restart.
