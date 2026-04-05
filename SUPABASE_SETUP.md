# Supabase Setup

Avaixa is now wired to initialize Supabase at app startup when these
compile-time variables are provided:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

## 1. Create a Supabase Project

In your Supabase dashboard:

1. Create a new project.
2. Open `Project Settings` -> `Data API`.
3. Copy:
   - Project URL
   - anon/public key

## 2. Run the App Locally With Supabase

Use `--dart-define` so keys are not committed into the repo:

```bash
flutter run -d chrome \
  --dart-define=SUPABASE_URL=YOUR_PROJECT_URL \
  --dart-define=SUPABASE_ANON_KEY=YOUR_ANON_KEY
```

## 3. Add The Same Variables In Vercel

In Vercel project settings, add:

- `SUPABASE_URL`
- `SUPABASE_ANON_KEY`

Your existing Flutter web build will then compile with those values.

## 4. Recommended First Table

Start with a `sessions` table:

```sql
create table public.sessions (
  id uuid primary key default gen_random_uuid(),
  created_at timestamptz not null default now(),
  mode text not null,
  transcript text not null,
  overall_score double precision not null,
  content_score double precision not null,
  pace_label text not null,
  confidence_label text not null,
  filler_count integer not null,
  filler_rate double precision not null,
  confidence_score double precision not null,
  metadata jsonb not null default '{}'::jsonb
);
```

## 5. Next Step

Once your project URL and anon key are ready, the next code step is saving each
`SessionReport` into `sessions` when a practice session ends.
