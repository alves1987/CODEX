import fs from 'fs';
import path from 'path';
import dotenv from 'dotenv';
import { fileURLToPath } from 'url';
import { Client } from 'pg';

dotenv.config();

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const config = {
  host: process.env.PGHOST || 'localhost',
  port: Number(process.env.PGPORT || 5432),
  database: process.env.PGDATABASE || 'esus',
  user: process.env.PGUSER || 'esus',
  password: process.env.PGPASSWORD || 'esus'
};

const sqlPath = path.join(__dirname, 'sql', '01_setup_auditoria.sql');
const sql = fs.readFileSync(sqlPath, 'utf8');

const client = new Client(config);

try {
  await client.connect();
  await client.query(sql);
  console.log('[OK] Auditoria configurada via Node (sem psql).');
} catch (error) {
  console.error('[ERRO] Falha ao configurar auditoria via Node.');
  console.error(error.message);
  process.exitCode = 1;
} finally {
  await client.end().catch(() => {});
}
