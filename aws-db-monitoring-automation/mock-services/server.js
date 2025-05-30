const express = require('express');
const bodyParser = require('body-parser');
const morgan = require('morgan');
const cors = require('cors');

// Create Express apps for different endpoints
const apiApp = express();
const infraApp = express();

// Middleware
[apiApp, infraApp].forEach(app => {
    app.use(cors());
    app.use(bodyParser.json());
    app.use(bodyParser.urlencoded({ extended: true }));
    app.use(morgan('combined'));
});

// Store agent data
const agents = new Map();
const metrics = [];

// API Server (Port 8080) - Management API
apiApp.get('/health', (req, res) => {
    res.json({ status: 'ok', service: 'mock-newrelic-api' });
});

// Validate license key
apiApp.use((req, res, next) => {
    const apiKey = req.headers['api-key'] || req.headers['x-api-key'];
    if (!apiKey || !apiKey.startsWith('test_')) {
        return res.status(401).json({ error: 'Invalid API key' });
    }
    next();
});

// Account information
apiApp.get('/v2/accounts/:accountId', (req, res) => {
    res.json({
        account: {
            id: req.params.accountId,
            name: 'Test Account',
            region: 'US'
        }
    });
});

// Infrastructure Server (Port 8081) - Agent Communication
infraApp.get('/health', (req, res) => {
    res.json({ status: 'ok', service: 'mock-newrelic-infra' });
});

// Agent registration
infraApp.post('/identity/v1/connect', (req, res) => {
    const agentId = `agent-${Date.now()}`;
    const agentData = {
        id: agentId,
        license_key: req.body.license_key,
        hostname: req.body.hostname || 'unknown',
        registered_at: new Date().toISOString()
    };
    
    agents.set(agentId, agentData);
    
    res.json({
        agent_id: agentId,
        status: 'connected',
        endpoints: {
            metrics: '/agent/v1/metrics',
            inventory: '/agent/v1/inventory',
            events: '/agent/v1/events'
        }
    });
});

// Metrics ingestion
infraApp.post('/agent/v1/metrics', (req, res) => {
    const agentId = req.headers['x-agent-id'];
    if (!agents.has(agentId)) {
        return res.status(401).json({ error: 'Unknown agent' });
    }
    
    const metric = {
        agent_id: agentId,
        timestamp: new Date().toISOString(),
        data: req.body
    };
    
    metrics.push(metric);
    console.log(`Received metrics from agent ${agentId}:`, JSON.stringify(req.body, null, 2));
    
    res.json({ status: 'accepted', count: req.body.length || 1 });
});

// Inventory data
infraApp.post('/agent/v1/inventory', (req, res) => {
    const agentId = req.headers['x-agent-id'];
    if (!agents.has(agentId)) {
        return res.status(401).json({ error: 'Unknown agent' });
    }
    
    console.log(`Received inventory from agent ${agentId}:`, JSON.stringify(req.body, null, 2));
    res.json({ status: 'accepted' });
});

// Events ingestion
infraApp.post('/agent/v1/events', (req, res) => {
    const agentId = req.headers['x-agent-id'];
    if (!agents.has(agentId)) {
        return res.status(401).json({ error: 'Unknown agent' });
    }
    
    console.log(`Received events from agent ${agentId}:`, JSON.stringify(req.body, null, 2));
    res.json({ status: 'accepted' });
});

// Integration configuration endpoints
infraApp.get('/agent/v1/integrations', (req, res) => {
    res.json({
        integrations: [
            {
                name: 'nri-mysql',
                version: '1.8.0',
                enabled: true
            },
            {
                name: 'nri-postgresql',
                version: '2.9.0',
                enabled: true
            }
        ]
    });
});

// Mock database metrics endpoint
apiApp.get('/v2/metrics/database', (req, res) => {
    res.json({
        databases: [
            {
                name: 'mysql-test',
                type: 'mysql',
                status: 'healthy',
                metrics: {
                    connections: 10,
                    queries_per_second: 50,
                    slow_queries: 2
                }
            },
            {
                name: 'postgres-test',
                type: 'postgresql',
                status: 'healthy',
                metrics: {
                    connections: 5,
                    transactions_per_second: 30,
                    cache_hit_ratio: 0.95
                }
            }
        ]
    });
});

// Admin endpoints for testing
apiApp.get('/admin/agents', (req, res) => {
    res.json({
        agents: Array.from(agents.values()),
        count: agents.size
    });
});

apiApp.get('/admin/metrics', (req, res) => {
    res.json({
        metrics: metrics.slice(-100), // Last 100 metrics
        total_count: metrics.length
    });
});

// Start servers
const API_PORT = process.env.API_PORT || 8080;
const INFRA_PORT = process.env.INFRA_PORT || 8081;

apiApp.listen(API_PORT, () => {
    console.log(`Mock New Relic API server listening on port ${API_PORT}`);
});

infraApp.listen(INFRA_PORT, () => {
    console.log(`Mock New Relic Infrastructure server listening on port ${INFRA_PORT}`);
});

// Graceful shutdown
process.on('SIGTERM', () => {
    console.log('Shutting down mock servers...');
    process.exit(0);
});