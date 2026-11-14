const { createServer } = require('node:http');
const { createPlan } = require('./plan');

function sendJson(response, status, body) {
  response.writeHead(status, { 'Content-Type': 'application/json; charset=utf-8' });
  response.end(JSON.stringify(body));
}

function createApp() {
  return createServer((request, response) => {
    if (request.method !== 'GET') {
      response.setHeader('Allow', 'GET');
      return sendJson(response, 405, { error: 'Only GET is supported' });
    }

    const url = URL.parse(request.url, 'http://localhost');
    if (!url) {
      return sendJson(response, 400, { error: 'Invalid request URL' });
    }

    switch (url.pathname) {
      case '/':
        return sendJson(response, 200, {
          name: 'Study Planner API',
          example: '/api/plan?topics=10&perDay=3&minutes=25',
        });
      case '/health':
        return sendJson(response, 200, { status: 'ok' });
      case '/api/plan':
        try {
          return sendJson(response, 200, createPlan(url.searchParams));
        } catch (error) {
          return sendJson(response, 400, { error: error.message });
        }
      default:
        return sendJson(response, 404, { error: 'Route not found' });
    }
  });
}

if (require.main === module) {
  const port = Number(process.env.PORT ?? 3000);

  if (!Number.isInteger(port) || port < 1 || port > 65535) {
    throw new RangeError('PORT must be an integer from 1 to 65535');
  }

  createApp().listen(port, '0.0.0.0', () => {
    console.log(`Study Planner API listening on port ${port}`);
  });
}

module.exports = { createApp };
