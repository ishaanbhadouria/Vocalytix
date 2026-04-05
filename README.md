# Avaixa

Avaixa is a Flutter web app for presentation and interview practice. It uses
browser speech recognition, camera access, and client-side session analysis.

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

This repo also includes a `Dockerfile` for DigitalOcean App Platform.

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

The app can be deployed without Supabase, but if you want live Supabase data,
set these during the build:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

If DigitalOcean asks whether the variables are available at build time, enable
that option so Flutter can compile them into the web bundle.

### Local Docker Build

```bash
docker build \
  --build-arg SUPABASE_URL=YOUR_PROJECT_URL \
  --build-arg SUPABASE_ANON_KEY=YOUR_ANON_KEY \
  -t avaixa-web .
```

## Browser Requirements

- Camera and microphone access only work over HTTPS or on localhost.
- Speech recognition support depends on the browser. Chrome-based browsers are
  the safest target.
- The first session will prompt for camera and microphone permissions.
