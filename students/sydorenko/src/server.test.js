const assert = require('node:assert/strict');
const { once } = require('node:events');
const { after, before, test } = require('node:test');
const { createApp } = require('./server');

let server;
let origin;

before(async () => {
  server = createApp().listen(0, '127.0.0.1');
  await once(server, 'listening');
  origin = `http://127.0.0.1:${server.address().port}`;
});

after(() => new Promise((resolve, reject) => {
  server.close((error) => error ? reject(error) : resolve());
}));

test('allocates all topics without exceeding the daily limit', async () => {
  const response = await fetch(`${origin}/api/plan?topics=10&perDay=3&minutes=25`);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), {
    topics: 10,
    days: 4,
    totalMinutes: 250,
    schedule: [
      { day: 1, topics: 3, minutes: 75 },
      { day: 2, topics: 3, minutes: 75 },
      { day: 3, topics: 3, minutes: 75 },
      { day: 4, topics: 1, minutes: 25 },
    ],
  });
});

test('rejects missing, duplicate, fractional, and out-of-range values', async () => {
  const invalidQueries = [
    'topics=10&perDay=3',
    'topics=10&perDay=3&perDay=4&minutes=25',
    'topics=1.5&perDay=3&minutes=25',
    'topics=366&perDay=3&minutes=25',
    'topics=10&perDay=0&minutes=25',
  ];

  for (const query of invalidQueries) {
    const response = await fetch(`${origin}/api/plan?${query}`);
    assert.equal(response.status, 400);
    assert.match((await response.json()).error, /must be one integer/);
  }
});

test('serves health and rejects unknown routes or methods', async () => {
  const health = await fetch(`${origin}/health`);
  assert.equal(health.status, 200);
  assert.deepEqual(await health.json(), { status: 'ok' });

  const missing = await fetch(`${origin}/missing`);
  assert.equal(missing.status, 404);

  const disallowed = await fetch(`${origin}/health`, { method: 'POST' });
  assert.equal(disallowed.status, 405);
  assert.equal(disallowed.headers.get('allow'), 'GET');
});
