const statusEl = document.getElementById('status');
const eventsBody = document.getElementById('eventsBody');
const tableFilter = document.getElementById('tableFilter');
const opFilter = document.getElementById('opFilter');
const reloadBtn = document.getElementById('reload');

const maxRows = 300;
let events = [];

function setStatus(text, kind = '') {
  statusEl.textContent = text;
  statusEl.className = `status ${kind}`.trim();
}

function formatDate(ts) {
  if (!ts) return '-';
  return new Date(ts).toLocaleString('pt-BR');
}

function normalizeFromNotify(data) {
  return {
    event_ts: data.ts || new Date().toISOString(),
    schema_name: data.schema || 'public',
    table_name: data.table || '-',
    operation: data.op || '-',
    user_name: data.user || '-'
  };
}

function matchesFilters(row) {
  const tableValue = tableFilter.value.trim().toLowerCase();
  const opValue = opFilter.value;

  const tableOk = !tableValue || String(row.table_name || '').toLowerCase().includes(tableValue);
  const opOk = !opValue || String(row.operation || '').toUpperCase() === opValue;

  return tableOk && opOk;
}

function render() {
  const html = events
    .filter(matchesFilters)
    .map((row) => `
      <tr>
        <td>${formatDate(row.event_ts)}</td>
        <td>${row.schema_name || '-'}</td>
        <td>${row.table_name || '-'}</td>
        <td><span class="op ${row.operation}">${row.operation || '-'}</span></td>
        <td>${row.user_name || '-'}</td>
      </tr>
    `)
    .join('');

  eventsBody.innerHTML = html || '<tr><td colspan="5">Sem dados ainda.</td></tr>';
}

async function loadRecent() {
  const response = await fetch('/api/recent?limit=200');
  if (!response.ok) throw new Error('Falha ao buscar histórico');
  const rows = await response.json();
  events = rows;
  render();
}

function pushEvent(eventRow) {
  events.unshift(eventRow);
  if (events.length > maxRows) {
    events.length = maxRows;
  }
  render();
}

function connectWs() {
  const protocol = location.protocol === 'https:' ? 'wss:' : 'ws:';
  const ws = new WebSocket(`${protocol}//${location.host}`);

  ws.onopen = () => setStatus('Conectado em tempo real', 'ok');

  ws.onclose = () => {
    setStatus('Desconectado. Tentando reconectar...', 'err');
    setTimeout(connectWs, 2000);
  };

  ws.onerror = () => {
    setStatus('Erro de conexão', 'err');
  };

  ws.onmessage = (event) => {
    const msg = JSON.parse(event.data);

    if (msg.type === 'snapshot' && Array.isArray(msg.data)) {
      events = msg.data;
      render();
      return;
    }

    if (msg.type === 'change' && msg.data) {
      pushEvent(normalizeFromNotify(msg.data));
    }
  };
}

reloadBtn.addEventListener('click', async () => {
  try {
    await loadRecent();
    setStatus('Histórico atualizado', 'ok');
  } catch {
    setStatus('Falha ao atualizar histórico', 'err');
  }
});

tableFilter.addEventListener('input', render);
opFilter.addEventListener('change', render);

(async function init() {
  try {
    await loadRecent();
    setStatus('Histórico carregado', 'ok');
  } catch {
    setStatus('Não foi possível ler histórico (verifique SQL setup)', 'err');
  }
  connectWs();
})();
