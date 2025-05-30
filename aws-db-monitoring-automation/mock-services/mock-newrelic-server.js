#!/usr/bin/env node

const express = require('express');
const bodyParser = require('body-parser');
const fs = require('fs');
const path = require('path');

const app = express();
app.use(bodyParser.json({ limit: '10mb' }));
app.use(bodyParser.text());

// Store received data
const dataStore = {
  infrastructure: [],
  metrics: [],
  events: [],
  logs: []
};

// Logging middleware
app.use((req, res, next) => {
  console.log(`[${new Date().toISOString()}] ${req.method} ${req.path}`);
  if (req.headers['x-license-key']) {
    console.log(`  License Key: ${req.headers['x-license-key'].substr(0, 8)}...`);
  }
  next();
});

// Infrastructure API endpoint
app.post('/infrastructure/v2/infra/data', (req, res) => {
  console.log('=== Infrastructure Data Received ===');
  const data = req.body;
  
  if (typeof data === 'string') {
    try {
      const parsed = JSON.parse(data);
      dataStore.infrastructure.push({
        timestamp: new Date().toISOString(),
        data: parsed
      });
      console.log(`Stored ${parsed.length || 1} infrastructure data points`);
    } catch (e) {
      console.error('Failed to parse infrastructure data:', e.message);
    }
  }
  
  res.status(202).json({ success: true });
});

// Metrics API endpoint
app.post('/metric/v1/infra', (req, res) => {
  console.log('=== Metrics Data Received ===');
  const metrics = req.body;
  
  if (Array.isArray(metrics)) {
    metrics.forEach(metric => {
      dataStore.metrics.push({
        timestamp: new Date().toISOString(),
        metric
      });
      
      // Log specific database metrics
      if (metric.name && metric.name.includes('database')) {
        console.log(`Database metric: ${metric.name} = ${metric.value}`);
      }
    });
    console.log(`Stored ${metrics.length} metrics`);
  }
  
  res.status(202).json({ success: true });
});

// Integration data endpoint
app.post('/v1/data', (req, res) => {
  console.log('=== Integration Data Received ===');
  const data = req.body;
  
  if (data && data.integration) {
    console.log(`Integration: ${data.integration.name}`);
    console.log(`Version: ${data.integration.version}`);
    
    if (data.data && data.data.length > 0) {
      data.data.forEach(item => {
        if (item.entity) {
          console.log(`  Entity: ${item.entity.name} (${item.entity.type})`);
        }
        
        // Log database-specific metrics
        if (item.metrics) {
          item.metrics.forEach(metric => {
            // MySQL metrics
            if (metric.event_type === 'MysqlSample') {
              console.log('  MySQL Metrics:');
              console.log(`    - Connections: ${metric['db.connections'] || 'N/A'}`);
              console.log(`    - Queries/sec: ${metric['db.queriesPerSecond'] || 'N/A'}`);
              console.log(`    - Slow Queries: ${metric['db.slowQueriesPerSecond'] || 'N/A'}`);
            }
            
            // PostgreSQL metrics
            if (metric.event_type === 'PostgresqlSample') {
              console.log('  PostgreSQL Metrics:');
              console.log(`    - Connections: ${metric['db.connections'] || 'N/A'}`);
              console.log(`    - Transactions: ${metric['db.commitsPerSecond'] || 'N/A'}`);
              console.log(`    - Cache Hit Ratio: ${metric['db.cacheHitRatio'] || 'N/A'}`);
            }
            
            // Custom query metrics
            if (metric.event_type === 'MysqlCustomQuerySample' || 
                metric.event_type === 'PostgresqlCustomQuerySample') {
              console.log(`  Custom Query Metrics (${metric.event_type}):`);
              Object.keys(metric).forEach(key => {
                if (!['event_type', 'entityKey', 'timestamp'].includes(key)) {
                  console.log(`    - ${key}: ${metric[key]}`);
                }
              });
            }
          });
        }
      });
    }
    
    dataStore.events.push({
      timestamp: new Date().toISOString(),
      data
    });
  }
  
  res.status(200).json({ success: true });
});

// Status endpoint
app.get('/status', (req, res) => {
  res.json({
    status: 'ok',
    dataReceived: {
      infrastructure: dataStore.infrastructure.length,
      metrics: dataStore.metrics.length,
      events: dataStore.events.length,
      logs: dataStore.logs.length
    }
  });
});

// Data viewer endpoint
app.get('/data', (req, res) => {
  const summary = {
    infrastructure: dataStore.infrastructure.slice(-5),
    metrics: dataStore.metrics.slice(-10),
    events: dataStore.events.slice(-5),
    totalCounts: {
      infrastructure: dataStore.infrastructure.length,
      metrics: dataStore.metrics.length,
      events: dataStore.events.length
    }
  };
  res.json(summary);
});

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'healthy', timestamp: new Date().toISOString() });
});

const PORT = process.env.PORT || 8080;
app.listen(PORT, () => {
  console.log(`Mock New Relic API server running on port ${PORT}`);
  console.log(`Status: http://localhost:${PORT}/status`);
  console.log(`Data viewer: http://localhost:${PORT}/data`);
});