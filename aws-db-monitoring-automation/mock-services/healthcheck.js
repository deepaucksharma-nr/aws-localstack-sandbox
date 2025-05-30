const http = require('http');

const options = {
  hostname: 'localhost',
  port: 8081,
  path: '/health',
  timeout: 2000,
};

const req = http.get(options, (res) => {
  if (res.statusCode === 200) {
    process.exit(0);
  } else {
    process.exit(1);
  }
});

req.on('error', () => {
  process.exit(1);
});

req.on('timeout', () => {
  req.abort();
  process.exit(1);
});

req.end();