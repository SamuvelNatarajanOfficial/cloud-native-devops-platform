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

test('GET /health returns ok', async () => {
  const app = createApp();
  await withServer(app, async (baseUrl) => {
    const res = await fetch(`${baseUrl}/health`);
    assert.equal(res.status, 200);
    const body = await res.json();
    assert.deepEqual(body, { status: 'ok' });
  });
});

test('GET /ready returns 503 when upstream is unreachable', async () => {
  process.env.TASK_SERVICE_URL = 'http://127.0.0.1:1';
  const app = createApp();
  await withServer(app, async (baseUrl) => {
    const res = await fetch(`${baseUrl}/ready`);
    assert.equal(res.status, 503);
  });
});
