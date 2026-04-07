FROM ghcr.io/cirruslabs/flutter:stable AS build

WORKDIR /app

COPY pubspec.yaml pubspec.lock ./
RUN flutter pub get

COPY . .

ARG SUPABASE_URL=""
ARG SUPABASE_ANON_KEY=""

RUN flutter config --enable-web && \
    flutter build web --release --no-wasm-dry-run \
      --dart-define=SUPABASE_URL=${SUPABASE_URL} \
      --dart-define=SUPABASE_ANON_KEY=${SUPABASE_ANON_KEY}

FROM node:20-alpine

WORKDIR /app

COPY server/package.json ./server/package.json
RUN cd server && npm install --omit=dev

COPY server ./server
COPY --from=build /app/build/web ./build/web

ENV PORT=8080

EXPOSE 8080

CMD ["node", "server/index.mjs"]
