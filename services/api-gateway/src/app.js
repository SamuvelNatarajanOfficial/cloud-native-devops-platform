const express = require('express');
const helmet = require('helmet');
const morgan = require('morgan');
const { createProxyMiddleware } = require('http-proxy-middleware');

function createApp() {
  const TASK_SERVICE_URL = process.env.TASK_SERVICE_URL || 'http://localhost:8000';
  const app = express();

  app.disable('x-powered-by');
  app.use(helmet());
  app.use(morgan('combined'));

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
