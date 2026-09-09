const test = require('node:test');
const assert = require('node:assert/strict');
const { createApp } = require('../src/app');

function withServer(app, fn) {
  return new Promise((resolve, reject) => {
    const server = app.listen(0, async () => {
      try {
        const { port } = server.address();
        await fn(`http://127.0.0.1:${port}`);
        resolve();
      } catch (err) {
        reject(err);
      } finally {
        server.close();
      }
    });
  });
}

test('GET /metrics exposes golden-signal HTTP metrics', async () => {
  const app = createApp();
  await withServer(app, async (baseUrl) => {
    await fetch(`${baseUrl}/health`);

    const res = await fetch(`${baseUrl}/metrics`);
    assert.equal(res.status, 200);
    const body = await res.text();
    assert.match(body, /api_gateway_http_requests_total/);
    assert.match(body, /api_gateway_http_request_duration_seconds/);
  });
});

test('metrics normalize UUID path segments instead of recording per-ID series', async () => {
  // 127.0.0.1:1 fails to connect immediately, so the proxy returns a fast
  // 502 - only the metrics labeling on the /api/* path is under test here,
  // not a successful proxy response.
  process.env.TASK_SERVICE_URL = 'http://127.0.0.1:1';
  const app = createApp();
  await withServer(app, async (baseUrl) => {
    await fetch(`${baseUrl}/api/tasks/11111111-1111-1111-1111-111111111111`);

    const body = await (await fetch(`${baseUrl}/metrics`)).text();
    assert.match(body, /path="\/api\/tasks\/:id"/);
    assert.doesNotMatch(body, /11111111-1111-1111-1111-111111111111/);
  });
});

test('metrics normalize purely-numeric path segments', async () => {
  process.env.TASK_SERVICE_URL = 'http://127.0.0.1:1';
  const app = createApp();
  await withServer(app, async (baseUrl) => {
    await fetch(`${baseUrl}/api/tasks/42`);

    const body = await (await fetch(`${baseUrl}/metrics`)).text();
    assert.match(body, /path="\/api\/tasks\/:id"/);
  });
});
