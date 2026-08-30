const { Router } = require('express');
const { query } = require('../config/db');
const { asyncHandler } = require('../middleware/errorHandler');

const router = Router();

// Liveness: process is up, no dependencies checked.
router.get('/health', (req, res) => {
  res.json({ status: 'ok' });
});

// Readiness: process is up AND can reach the database.
router.get('/health/ready', asyncHandler(async (req, res) => {
  await query('SELECT 1');
  res.json({ status: 'ok', database: 'connected' });
}));

module.exports = router;
