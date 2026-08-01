# ECHO Supabase Proxy — Setup Guide

This Cloudflare Worker proxies all Supabase traffic under your own domain, so
networks that block `*.supabase.co` via DNS (like university Wi-Fi) can't break
the app.

## Why?

`supabase.co` is getting filtered by some university DNS. Users on campus Wi-Fi
can't reach the backend. A Cloudflare Worker lets us front the backend under
a `*.workers.dev` (free) or custom domain (optional, ~$10/year), bypassing the
DNS block entirely.

## Step-by-step

### 1. Create a Cloudflare account
- Go to https://dash.cloudflare.com/sign-up
- Free plan is enough. Sign up with email.

### 2. Create the Worker
- Once logged in, on the left sidebar click **Workers & Pages**
- Click **Create application** → **Create Worker**
- Name it something like `echo-proxy` (this becomes part of your URL)
- Click **Deploy**

### 3. Paste the Worker code
- Click **Edit code** on the Worker you just created
- Delete the default code
- Paste the contents of `worker.js` (in this folder)
- Click **Save and Deploy**

### 4. Get your Worker URL
After deploy, Cloudflare will show your URL. It looks like:
```
https://echo-proxy.YOURNAME.workers.dev
```
Copy this URL — you'll need it.

### 5. Verify it works
In your browser, visit:
```
https://echo-proxy.YOURNAME.workers.dev/__health
```
You should see `ok`. If you do, the Worker is live.

## Cost summary

- Cloudflare Workers free tier: **$0/month** (100,000 requests/day, plenty for
  thousands of users)
- Custom domain (optional): ~$10/year
- No Supabase Pro plan required
