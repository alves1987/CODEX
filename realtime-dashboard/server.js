import dotenv from 'dotenv';
import express from 'express';
import http from 'http';
import path from 'path';
import { fileURLToPath } from 'url';
import { Client } from 'pg';
import { WebSocketServer } from 'ws';

dotenv.config();

const app = express();
const server = http.createServer(app);
const wss = new WebSocketServer({ server });

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const config = {
  port: Number(process.env.PORT || 3000),
  channel: process.env.PGCHANNEL || 'table_changes',
  pg: {
    host: process.env.PGHOST || 'localhost',
    port: Number(process.env.PGPORT || 5432),
    database: process.env.PGDATABASE || 'esus',
    user: process.env.PGUSER || 'esus',
    password: process.env.PGPASSWORD || 'esus'
  }
};

let dbClient;

function broadcast(type, data) {
  const payload = JSON.stringify({ type, data });

  for (const client of wss.clients) {
    if (client.readyState === 1) {
      client.send(payload);
    }
  }
}

async function fetchRecent(limit = 100) {
  const query = `
    SELECT event_ts, schema_name, table_name, operation, user_name
      FROM monitor.audit_log
     ORDER BY event_ts DESC
     LIMIT $1;
  `;

  const { rows } = await dbClient.query(query, [limit]);
  return rows;
}

async function connectListener() {
  dbClient = new Client(config.pg);
  await dbClient.connect();
  await dbClient.query(`LISTEN ${config.channel}`);

  dbClient.on('notification', (msg) => {
    try {
      const payload = JSON.parse(msg.payload || '{}');
      broadcast('change', payload);
    } catch {
      broadcast('change', { raw: msg.payload });
    }
  });

  dbClient.on('error', (err) => {
    console.error('Erro na conexão PostgreSQL:', err.message);
  });
}

app.use(express.static(path.join(__dirname, 'public')));

app.get('/health', (_, res) => {
  res.json({ ok: true });
});

app.get('/api/recent', async (req, res) => {
  try {
    const limit = Number(req.query.limit || 100);
    const rows = await fetchRecent(Math.min(limit, 500));
    res.json(rows);
  } catch (err) {
    res.status(500).json({
      error: 'Não foi possível buscar eventos recentes.',
      detail: err.message
    });
  }
});

wss.on('connection', async (socket) => {
  socket.send(JSON.stringify({
    type: 'info',
    data: { message: 'Conectado ao monitor em tempo real.' }
  }));

  try {
    const rows = await fetchRecent(50);
    socket.send(JSON.stringify({ type: 'snapshot', data: rows }));
  } catch (err) {
    socket.send(JSON.stringify({
      type: 'error',
      data: { message: `Erro ao carregar histórico inicial: ${err.message}` }
    }));
  }
});

await connectListener();

server.listen(config.port, () => {
  console.log(`Dashboard rodando em http://localhost:${config.port}`);
  console.log(`Escutando canal PostgreSQL: ${config.channel}`);
});
