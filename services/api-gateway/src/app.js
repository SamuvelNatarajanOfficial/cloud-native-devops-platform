const express = require('express');
const helmet = require('helmet');
const morgan = require('morgan');
// @prometheus-io/client, not the older `prom-client` name: prom-client's
// own maintainer moved the project under the official Prometheus GitHub
// org and marked prom-client itself deprecated pointing here - same
// "actively-maintained, officially-endorsed successor" principle Phase 5
// applied choosing Grafana Alloy over Promtail. Identical API (Registry,
// Counter, Histogram, collectDefaultMetrics all export the same way).
const client = require('@prometheus-io/client');
const { createProxyMiddleware } = require('http-proxy-middleware');

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

// Best-effort route "templating" for the /api/* proxy. Unlike task-service
// (services/task-service/app/main.py), the gateway has no Express route
// definitions of its own for task-service's endpoints - it's a catch-all
// proxy - so there is no req.route to read a template from. Instead, any
// UUID-shaped or purely-numeric path segment is collapsed to ":id" before
// it's ever used as a label value, so e.g. /api/tasks/<uuid-a> and
// /api/tasks/<uuid-b> become the single series /api/tasks/:id instead of
// one series per task ID. See observability/README.md#cardinality.
function normalizePathForMetrics(path) {
  const normalized = path
    .split('/')
    .map((segment) => (UUID_RE.test(segment) || /^\d+$/.test(segment) ? ':id' : segment))
    .join('/');
  return normalized || '/';
}

function createApp() {
  const TASK_SERVICE_URL = process.env.TASK_SERVICE_URL || 'http://localhost:8000';
  const app = express();

  // A registry scoped to this app instance (not prom-client's global
  // default register) - createApp() is called fresh in every test, and a
  // shared global registry would throw "metric already registered" on the
  // second call.
  const register = new client.Registry();
  client.collectDefaultMetrics({ register });

  const httpRequestsTotal = new client.Counter({
    name: 'api_gateway_http_requests_total',
    help: 'Total HTTP requests, labeled by method, route template, and status code',
    labelNames: ['method', 'path', 'status_code'],
    registers: [register],
  });
  const httpRequestDurationSeconds = new client.Histogram({
    name: 'api_gateway_http_request_duration_seconds',
    help: 'HTTP request duration in seconds, labeled by method and route template',
    labelNames: ['method', 'path'],
    registers: [register],
  });

  app.disable('x-powered-by');
  app.use(helmet());
  app.use(morgan('combined'));

  // Golden-signal HTTP metrics for every route (traffic, errors, latency -
  // same philosophy as task-service's record_request_metrics middleware).
  // Registered before /health, /ready, and the proxy below so it observes
  // all of them, including proxied responses (http-proxy-middleware
  // streams through this same `res`, so 'finish' still fires once the
  // upstream response has been fully relayed to the client).
  app.use((req, res, next) => {
    const startedAt = process.hrtime.bigint();
    // Captured NOW, not read lazily inside the 'finish' listener below:
    // http-proxy-middleware rewrites req.url in place as it forwards
    // /api/* to task-service (stripping the /api prefix per
    // pathRewrite), so by the time 'finish' fires, req.path would already
    // reflect the REWRITTEN path (e.g. "/tasks/:id" instead of
    // "/api/tasks/:id") rather than what the client actually requested.
    const path = normalizePathForMetrics(req.path);
    res.on('finish', () => {
      const durationSeconds = Number(process.hrtime.bigint() - startedAt) / 1e9;
      httpRequestsTotal.labels(req.method, path, String(res.statusCode)).inc();
      httpRequestDurationSeconds.labels(req.method, path).observe(durationSeconds);
    });
    next();
  });

  app.get('/metrics', async (_req, res) => {
    res.set('Content-Type', register.contentType);
    res.end(await register.metrics());
  });

  // Liveness: the gateway process itself is up.
  app.get('/health', (_req, res) => {
    res.json({ status: 'ok' });
  });

  // Readiness: the gateway can actually reach its upstream.
  app.get('/ready', async (_req, res) => {
    try {
      const upstream = await fetch(`${TASK_SERVICE_URL}/health`, { signal: AbortSignal.timeout(2000) });
      if (!upstream.ok) throw new Error(`upstream status ${upstream.status}`);
      res.json({ status: 'ready' });
    } catch (err) {
      res.status(503).json({ status: 'not-ready', reason: err.message });
    }
  });

  app.use(
    '/api',
    createProxyMiddleware({
      target: TASK_SERVICE_URL,
      changeOrigin: true,
      pathRewrite: { '^/api': '' },
    })
  );

  return app;
}

module.exports = { createApp };
