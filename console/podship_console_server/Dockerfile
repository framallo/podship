# The podship console server. Build from the podship repo root (the server
# depends on the podship library by path):
#   docker build -f console/podship_console_server/Dockerfile .
# podship builds the Flutter web app into console/podship_console_server/web/app
# before this runs.

FROM dart:3.12.2 AS build
WORKDIR /src
COPY pubspec.yaml pubspec.lock ./
COPY lib lib
COPY console/pubspec.lock console/pubspec.lock
COPY console/podship_console_server/pubspec.yaml console/podship_console_server/pubspec.yaml
RUN printf '%s\n' \
  'name: _' \
  'environment:' \
  '  sdk: ^3.12.2' \
  'workspace:' \
  '  - podship_console_server' \
  > console/pubspec.yaml
WORKDIR /src/console
RUN --mount=type=cache,target=/root/.pub-cache,sharing=locked dart pub get
COPY console/podship_console_server/bin podship_console_server/bin
COPY console/podship_console_server/lib podship_console_server/lib
WORKDIR /src/console/podship_console_server
RUN --mount=type=cache,target=/root/.pub-cache,sharing=locked \
    dart build cli --target bin/main.dart --output build && \
    mv build/bundle/bin/main build/bundle/bin/server

FROM alpine:3.22
RUN apk add --no-cache ca-certificates tzdata
WORKDIR /app
ENV runmode=production
ENV serverid=default
ENV logging=normal
ENV role=monolith
COPY --from=build /runtime/ /
COPY --from=build /src/console/podship_console_server/build/bundle/ ./
COPY console/podship_console_server/lib/src/generated/protocol.yaml lib/src/generated/protocol.yaml
COPY console/podship_console_server/config/ config/
COPY console/podship_console_server/migrations/ migrations/
COPY console/podship_console_server/web/ web/
EXPOSE 8080 8081 8082
ENTRYPOINT ./bin/server --mode=$runmode --server-id=$serverid --logging=$logging --role=$role --apply-migrations
