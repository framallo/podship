// Shared test fixtures.

const sampleConfig = '''
project: demo
server_package: demo_server
build:
  flutter_web:
    - name: app
      path: demo_flutter
      output: demo_server/web/app
      base_href: /app/
  pre_deploy: ["echo pre"]
  files:
    - "!demo_server/web/app/**"
compose:
  files: [docker-compose.yml]
  build_contexts:
    worker: /srv/worker
  remote_pre_build: ["git -C /srv/worker pull --ff-only"]
environments:
  production:
    host: prod-box
    dir: /srv/demo
    ports: {web: 8087, api: 8086}
    health:
      url: http://127.0.0.1:{port:web}/health
      public_url: https://demo.example.com/health
    plain_env: [PORT_WEB]
    database: {name: demo}
    backup:
      dir: /srv/backups/demo
      unit: demo-backup
      schedule: "*-*-* 03:30:00 America/Mexico_City"
      recipients: ["ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIExample owner"]
      volumes:
        - {name: worker, volume: demo_worker, sqlite: [q.db]}
      drill:
        tables: ["user*", ticket]
        volatile: ["session*"]
    proxy: {kind: cloudflare_tunnel, config: /root/.cloudflared/config.yml, service: cloudflared, tunnel_id: abc}
    domains:
      - host: demo.example.com
        routes:
          - {path: "^/(api|v1)/", port: api}
          - {port: web}
  staging:
    host: prod-box
    dir: /srv/demo-staging
    ports: {web: auto, api: auto}
    health: {url: "http://127.0.0.1:{port:web}/health"}
    backup: {}
    domains:
      - host: staging.example.com
        routes: [{port: web}]
''';
