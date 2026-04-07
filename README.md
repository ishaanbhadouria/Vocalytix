# Avaixa

Avaixa is a Flutter web app for presentation and interview practice. It uses
camera access, client-side session analysis, and server-backed OpenAI speech to
text when an API key is configured.

## Local Development

```bash
flutter pub get
flutter run -d chrome
```

To create a production web build locally:

```bash
flutter build web --release --no-wasm-dry-run
```

The `--no-wasm-dry-run` flag is intentional. This app uses `dart:html` and
`dart:js`, so Flutter's wasm compatibility check will warn even though the
standard web build works.

## Deploy To Vercel

This repo includes `vercel.json`,
so Vercel can build the Flutter web app automatically.

### Vercel Dashboard

1. Import the Git repository into Vercel.
2. Keep the project root set to the repo root if this project is standalone.
3. Leave the framework preset as `Other`.
4. Deploy. Vercel will:
   - install Flutter
   - run `flutter pub get`
   - build the app into `build/web`
   - serve the generated static files

### Vercel CLI

```bash
vercel
vercel --prod
```

## Deploy To DigitalOcean App Platform

This repo includes a `Dockerfile` that builds the Flutter web app and serves it
through a small Node server. That same server hosts the OpenAI transcription
endpoint, so your `OPENAI_API_KEY` stays on the server.

### What To Select In DigitalOcean

1. Choose `App Platform`.
2. Select this GitHub repo.
3. Keep the branch on `main`.
4. Continue once DigitalOcean detects the `Dockerfile`.
5. Create a single `Web Service` component.

### App Platform Settings

- Resource type: `Web Service`
- HTTP port: `8080`
- Run command: leave blank

### Environment Variables

Build-time variables:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

Runtime variables:

- `OPENAI_API_KEY`
- `OPENAI_TRANSCRIPTION_MODEL` (optional, defaults to `gpt-4o-mini-transcribe`)

If DigitalOcean lets you mark variables as available during build, do that for
`SUPABASE_URL` and `SUPABASE_ANON_KEY` so Flutter can compile them into the web
bundle. Keep `OPENAI_API_KEY` server-side only.

### Local Docker Build

```bash
docker build \
  --build-arg SUPABASE_URL=YOUR_PROJECT_URL \
  --build-arg SUPABASE_ANON_KEY=YOUR_ANON_KEY \
  -t avaixa-web .
```

Then run it with your OpenAI key:

```bash
docker run --rm -p 8080:8080 \
  -e OPENAI_API_KEY=YOUR_OPENAI_API_KEY \
  avaixa-web
```

## Browser Requirements

- Camera and microphone access only work over HTTPS or on localhost.
- OpenAI transcription requires microphone access and a working backend route.
- The first session will prompt for camera and microphone permissions.
