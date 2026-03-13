# Vocalytix

Vocalytix is a Flutter web app for presentation and interview practice. It uses
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

This repo includes [`vercel.json`](/Users/ishaanbhadouria/Desktop/CES/Vocalytix/vercel.json),
so Vercel can build the Flutter web app automatically.

### Vercel Dashboard

1. Import the Git repository into Vercel.
2. Keep the project root set to
   [`/Users/ishaanbhadouria/Desktop/CES/Vocalytix`](/Users/ishaanbhadouria/Desktop/CES/Vocalytix)
   or the repo root if this project is standalone.
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

## Browser Requirements

- Camera and microphone access only work over HTTPS or on localhost.
- Speech recognition support depends on the browser. Chrome-based browsers are
  the safest target.
- The first session will prompt for camera and microphone permissions.
