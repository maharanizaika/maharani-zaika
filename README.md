# Maharani Zaika Restaurant & Cafe: ordering platform

Single-restaurant platform (not a marketplace). White and blue theme, Zomato-style customer app.

## Status
| Part | State |
|---|---|
| Customer front (`index.html`) | Working demo, sample menu, in-browser orders only |
| Database schema + RLS (`supabase/schema.sql`) | Written, not yet run |
| Server-side order pricing (`place_order()`) | Written |
| Connect front to Supabase | Next |
| Admin and staff dashboard | Next |
| Table QR codes, PWA, payments | Next |

All menu items and prices are DEMO data until the restaurant supplies the real menu.

## Local run
Open `index.html` in a browser, or run `python3 -m http.server 8000`.

## Push to GitHub
```bash
git init && git add . && git commit -m "Initial commit"
git branch -M main
git remote add origin https://github.com/YOUR-USER/maharani-zaika.git
git push -u origin main
```
Then on GitHub: **Settings > Pages > Source: GitHub Actions**. The workflow in `.github/workflows/pages.yml` publishes the site on every push to `main`.

## Supabase setup
1. Create a free project at supabase.com.
2. SQL Editor: run `supabase/schema.sql`, then `supabase/seed.sql`.
3. Make yourself admin: sign up once, then run
   `update profiles set role='admin' where id='YOUR-USER-UUID';`
4. Copy `.env.example` to `.env`. Only the public anon key may ever go in frontend code.

## Security checklist
- [ ] Service-role and payment secrets only in server environment, never in the repo
- [ ] RLS enabled on every table (done in schema), test with a customer account
- [ ] Payments marked paid only by a verified gateway webhook
- [ ] Real policy pages and opening hours added
- [ ] Free-tier limits checked (Supabase pauses idle free projects; GitHub Pages is static only, so webhooks need Cloudflare Workers or Supabase Edge Functions)
