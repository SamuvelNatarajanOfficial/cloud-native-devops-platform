const { createApp } = require('./app');

const PORT = process.env.API_GATEWAY_PORT || 8080;

const app = createApp();

app.listen(PORT, () => {
  // eslint-disable-next-line no-console
  console.log(`api-gateway listening on port ${PORT}`);
});
