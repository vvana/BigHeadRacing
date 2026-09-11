'use strict';
/*
 * БОЛЬШЕГОЛОВАЯ АНАЛИТИКА — «Пыль и Пламя», сбор и показ метрик игры.
 *
 * Что делает: раз в POLL_MS читает новые строки из файлов метрик, которые
 * пишет сервер друзей игры (user://metrics/<дата>.jsonl у пользователя
 * bighead), раскладывает их в SQLite и показывает веб-панель со сводкой.
 *
 * Зависимостей нет вовсе: только встроенные модули Node (node:sqlite есть
 * с Node 22). Это сделано нарочно — на VDS 960 МБ и без npm-дерева сервис
 * поднимается одним файлом и не ломается при обновлениях.
 *
 * Запуск: node server.js   (настройки — config.json рядом, создаётся сам)
 * Документация: server/metrics/README.md
 */

const http = require('node:http');
const fs = require('node:fs');
const path = require('node:path');
const crypto = require('node:crypto');
const { DatabaseSync } = require('node:sqlite');

const ROOT = __dirname;
const CONFIG_PATH = path.join(ROOT, 'config.json');
const POLL_MS = 20000;

// ── настройки ──────────────────────────────────────────────────────────────

const DEFAULTS = {
  port: 8090,
  host: '0.0.0.0',
  // Папка, куда сервер друзей пишет <дата>.jsonl.
  metricsDir: '/home/bighead/.local/share/godot/app_userdata/Пыль и Пламя/metrics',
  dbPath: path.join(ROOT, 'data', 'metrics.db'),
  // Часовой пояс для границ суток в отчётах (Москва = 3).
  tzOffsetHours: 3,
  // Пароль панели. Пустой — сгенерируется при первом запуске.
  token: '',
  title: 'Пыль и Пламя — аналитика',
};

function loadConfig() {
  let cfg = { ...DEFAULTS };
  if (fs.existsSync(CONFIG_PATH)) {
    try {
      cfg = { ...cfg, ...JSON.parse(fs.readFileSync(CONFIG_PATH, 'utf8')) };
    } catch (e) {
      console.error('[cfg] config.json не читается:', e.message);
    }
  }
  if (!cfg.token) {
    cfg.token = crypto.randomBytes(12).toString('base64url');
    fs.writeFileSync(CONFIG_PATH, JSON.stringify(cfg, null, 2), 'utf8');
    console.log('[cfg] создан config.json, пароль панели: ' + cfg.token);
  }
  return cfg;
}

const CFG = loadConfig();

// ── словари для человеческих подписей ──────────────────────────────────────
// Держать в согласии с игрой: CarSelect.DISPLAY_NAMES, Weapons.NAMES,
// TrackBuilder.KIND_*. Незнакомый ключ показывается как есть.

const CAR_NAMES = {
  vz01: 'Копейка', vz02: 'Двойка', vz21: 'Нива', vz03: 'Тройка',
  vz04: 'Четвёрка', vz05: 'Пятёрка', vz06: 'Шестёрка', vz07: 'Семёрка',
  vz05r: 'Пятёрка Спорт', vz08: 'Зубило', vz09: 'Девятка',
  vz099: 'Самара 99', gz21: 'Волга 21', gz24: 'Волга 24',
  vz31: 'Нива Лонг', fastback: 'Fastback', godfather: 'Godfather',
  lemans: 'Le Mans GT', superbird: 'Superbird', chevelle: 'Chevelle SS',
  diablo: 'Diablo', dragster: 'Dragster', safari: 'Safari 4x4',
  ac1: 'Стрела', ac2: 'Сарай', ac3: 'Багги', ac4: 'Малыш', ac5: 'Пикап',
  ac6: 'Монстр', ac7: 'Маслкар', ac8: 'Кирпич',
};
const WEAPON_NAMES = ['Мина', 'Ракета', 'Масло', 'Магнит', 'Лазер',
  'Заморозка', 'Авиаудар', 'Ускорение', 'Глушилка', 'Щит'];
const TRACK_NAMES = { grass: 'Трава', sand: 'Пустыня', neon: 'Неон',
  space: 'Космос' };
const BUY_KINDS = { car: 'Машины', item: 'Детали и краска',
  weapon: 'Ступени оружия', pack: 'Наборы' };

// ── база ───────────────────────────────────────────────────────────────────

fs.mkdirSync(path.dirname(CFG.dbPath), { recursive: true });
const db = new DatabaseSync(CFG.dbPath);
db.exec(`
  PRAGMA journal_mode = WAL;
  CREATE TABLE IF NOT EXISTS files (path TEXT PRIMARY KEY, off INTEGER NOT NULL);
  CREATE TABLE IF NOT EXISTS events (
    id INTEGER PRIMARY KEY AUTOINCREMENT,
    ts REAL NOT NULL, day TEXT NOT NULL, uid TEXT, name TEXT, e TEXT NOT NULL,
    platform TEXT, version TEXT, locale TEXT,
    place INTEGER, size INTEGER, humans INTEGER, online INTEGER, party INTEGER,
    car TEXT, kills INTEGER, deaths INTEGER, track TEXT, ms INTEGER,
    rating INTEGER, level INTEGER, money INTEGER,
    result INTEGER, goals INTEGER, coins INTEGER, price INTEGER,
    kind TEXT, ikey TEXT, d TEXT
  );
  CREATE INDEX IF NOT EXISTS ev_day ON events(day);
  CREATE INDEX IF NOT EXISTS ev_e ON events(e);
  CREATE INDEX IF NOT EXISTS ev_uid ON events(uid);
  CREATE INDEX IF NOT EXISTS ev_ts ON events(ts);
  CREATE TABLE IF NOT EXISTS weapons (
    day TEXT NOT NULL, uid TEXT, kind INTEGER NOT NULL, n INTEGER NOT NULL);
  CREATE INDEX IF NOT EXISTS wp_day ON weapons(day);
`);

const insEvent = db.prepare(`INSERT INTO events
  (ts, day, uid, name, e, platform, version, locale, place, size, humans,
   online, party, car, kills, deaths, track, ms, rating, level, money,
   result, goals, coins, price, kind, ikey, d)
  VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)`);
const insWeapon = db.prepare(
  'INSERT INTO weapons (day, uid, kind, n) VALUES (?,?,?,?)');
const getOff = db.prepare('SELECT off FROM files WHERE path = ?');
const setOff = db.prepare(
  'INSERT INTO files (path, off) VALUES (?,?) ' +
  'ON CONFLICT(path) DO UPDATE SET off = excluded.off');

// ── чтение файлов метрик ───────────────────────────────────────────────────

/** Дата события по местному часовому поясу отчётов (YYYY-MM-DD). */
function dayOf(ts) {
  const d = new Date((ts + CFG.tzOffsetHours * 3600) * 1000);
  return d.toISOString().slice(0, 10);
}

function num(v) {
  const n = Number(v);
  return Number.isFinite(n) ? n : null;
}
function bool(v) { return v === true || v === 1 ? 1 : (v === false || v === 0 ? 0 : null); }

let lastIngest = { at: 0, lines: 0, errors: 0 };

function ingest() {
  let dir = CFG.metricsDir;
  if (!fs.existsSync(dir)) {
    lastIngest = { at: Date.now(), lines: 0, errors: 0, note: 'папки метрик нет: ' + dir };
    return;
  }
  let lines = 0, errors = 0;
  const files = fs.readdirSync(dir).filter((f) => f.endsWith('.jsonl')).sort();
  for (const f of files) {
    const full = path.join(dir, f);
    let st;
    try { st = fs.statSync(full); } catch { continue; }
    const row = getOff.get(full);
    let off = row ? Number(row.off) : 0;
    // Файл усох (переписали, почистили) — читаем с начала, чтобы не
    // потерять остаток; дубли при этом возможны только если файл
    // действительно переписали другим содержимым.
    if (st.size < off) off = 0;
    if (st.size === off) continue;
    const fd = fs.openSync(full, 'r');
    const len = st.size - off;
    const buf = Buffer.allocUnsafe(len);
    fs.readSync(fd, buf, 0, len, off);
    fs.closeSync(fd);
    const text = buf.toString('utf8');
    // Последняя строка может быть недописана — её оставляем на следующий раз.
    const cut = text.lastIndexOf('\n');
    if (cut < 0) continue;
    const chunk = text.slice(0, cut);
    const consumed = Buffer.byteLength(text.slice(0, cut + 1), 'utf8');
    db.exec('BEGIN');
    try {
      for (const line of chunk.split('\n')) {
        const s = line.trim();
        if (!s) continue;
        try { store(s); lines++; } catch { errors++; }
      }
      setOff.run(full, off + consumed);
      db.exec('COMMIT');
    } catch (e) {
      db.exec('ROLLBACK');
      console.error('[ingest] ' + f + ': ' + e.message);
      errors++;
    }
  }
  lastIngest = { at: Date.now(), lines, errors };
  if (lines) console.log('[ingest] новых событий: ' + lines +
    (errors ? ', битых строк: ' + errors : ''));
}

/** Одна строка JSONL → строка в events (+ weapons для заездов). */
function store(line) {
  const o = JSON.parse(line);
  const ts = Number(o.ts) || 0;
  if (!ts || !o.e) throw new Error('нет ts/e');
  const d = (o.d && typeof o.d === 'object') ? o.d : {};
  const day = dayOf(ts);
  insEvent.run(ts, day, String(o.uid || ''), String(o.name || ''),
    String(o.e), d.platform ? String(d.platform) : null,
    d.version ? String(d.version) : null, d.locale ? String(d.locale) : null,
    num(d.place), num(d.size), num(d.humans), bool(d.online), bool(d.party),
    d.car ? String(d.car) : null, num(d.kills), num(d.deaths),
    d.track ? String(d.track) : null, num(d.ms), num(d.rating), num(d.level),
    num(d.money) ?? num(d.money_after), num(d.result), num(d.goals),
    num(d.coins), num(d.price), d.kind ? String(d.kind) : null,
    d.key ? String(d.key) : null, JSON.stringify(d));
  if (o.e === 'race' && d.weapons && typeof d.weapons === 'object') {
    for (const [k, v] of Object.entries(d.weapons)) {
      const n = Number(v);
      if (Number.isFinite(n) && n > 0) {
        insWeapon.run(day, String(o.uid || ''), Number(k) || 0, n);
      }
    }
  }
}

// ── запросы к сводке ───────────────────────────────────────────────────────

const q = (sql, ...args) => db.prepare(sql).all(...args);
const q1 = (sql, ...args) => db.prepare(sql).get(...args) || {};

function today() { return dayOf(Date.now() / 1000); }
function dayShift(n) { return dayOf(Date.now() / 1000 - n * 86400); }

function summary(days) {
  const from = dayShift(days - 1);
  const tdy = today();
  const week = dayShift(6);

  const totals = q1(`SELECT
      (SELECT COUNT(DISTINCT uid) FROM events WHERE uid <> '') AS players,
      (SELECT COUNT(*) FROM events) AS events,
      (SELECT COUNT(*) FROM events WHERE e = 'race') AS races,
      (SELECT COUNT(*) FROM events WHERE e = 'soccer') AS soccer,
      (SELECT COUNT(*) FROM events WHERE e = 'ad') AS ads,
      (SELECT COALESCE(SUM(coins), 0) FROM events WHERE e = 'ad') AS ad_coins,
      (SELECT COUNT(*) FROM events WHERE e = 'buy') AS buys,
      (SELECT COALESCE(SUM(price), 0) FROM events WHERE e = 'buy') AS spent,
      (SELECT MIN(ts) FROM events) AS first_ts,
      (SELECT MAX(ts) FROM events) AS last_ts`);

  const live = q1(`SELECT
      (SELECT COUNT(DISTINCT uid) FROM events WHERE day = ? AND uid <> '') AS dau,
      (SELECT COUNT(DISTINCT uid) FROM events WHERE day >= ? AND uid <> '') AS wau,
      (SELECT COUNT(*) FROM events WHERE day = ? AND e = 'race') AS races_today,
      (SELECT COUNT(*) FROM events WHERE day >= ? AND e = 'race') AS races_week,
      (SELECT COUNT(*) FROM events WHERE day = ? AND e IN ('session','hello')) AS sessions_today`,
    tdy, week, tdy, week, tdy);

  // Новые игроки: по первому событию.
  const firstSeen = q(`SELECT uid, MIN(ts) AS t FROM events
      WHERE uid <> '' GROUP BY uid`);
  const newByDay = {};
  for (const r of firstSeen) {
    const d = dayOf(Number(r.t));
    newByDay[d] = (newByDay[d] || 0) + 1;
  }
  const newWeek = Object.entries(newByDay)
    .filter(([d]) => d >= week).reduce((a, [, n]) => a + n, 0);

  const byDay = q(`SELECT day,
      COUNT(DISTINCT CASE WHEN uid <> '' THEN uid END) AS players,
      SUM(CASE WHEN e = 'race' THEN 1 ELSE 0 END) AS races,
      SUM(CASE WHEN e = 'soccer' THEN 1 ELSE 0 END) AS soccer,
      SUM(CASE WHEN e IN ('session','hello') THEN 1 ELSE 0 END) AS sessions,
      SUM(CASE WHEN e = 'ad' THEN 1 ELSE 0 END) AS ads,
      SUM(CASE WHEN e = 'buy' THEN COALESCE(price,0) ELSE 0 END) AS spent
    FROM events WHERE day >= ? GROUP BY day ORDER BY day`, from);
  for (const r of byDay) r.newcomers = newByDay[r.day] || 0;

  const cars = q(`SELECT car,
      COUNT(*) AS races,
      ROUND(AVG(place), 2) AS avg_place,
      SUM(CASE WHEN place = 1 THEN 1 ELSE 0 END) AS wins,
      COUNT(DISTINCT uid) AS players
    FROM events WHERE e = 'race' AND car IS NOT NULL AND car <> ''
    GROUP BY car ORDER BY races DESC`);
  for (const r of cars) r.title = CAR_NAMES[r.car] || r.car;

  const carBuys = q(`SELECT ikey AS car, COUNT(*) AS n,
      COALESCE(SUM(price),0) AS spent
    FROM events WHERE e = 'buy' AND kind = 'car'
    GROUP BY ikey ORDER BY n DESC`);
  for (const r of carBuys) r.title = CAR_NAMES[r.car] || r.car;

  const tracks = q(`SELECT track, COUNT(*) AS races, ROUND(AVG(place),2) AS avg_place
    FROM events WHERE e = 'race' AND track IS NOT NULL
    GROUP BY track ORDER BY races DESC`);
  for (const r of tracks) r.title = TRACK_NAMES[r.track] || r.track;

  const weapons = q(`SELECT kind, SUM(n) AS uses, COUNT(DISTINCT uid) AS players
    FROM weapons GROUP BY kind ORDER BY uses DESC`);
  for (const r of weapons) r.title = WEAPON_NAMES[r.kind] || ('вид ' + r.kind);

  const modes = q1(`SELECT
      (SELECT COUNT(*) FROM events WHERE e = 'race' AND online = 1) AS online,
      (SELECT COUNT(*) FROM events WHERE e = 'race' AND online = 0) AS offline,
      (SELECT COUNT(*) FROM events WHERE e = 'race' AND party = 1) AS party,
      (SELECT COUNT(*) FROM events WHERE e = 'party') AS party_launch,
      (SELECT ROUND(AVG(ms) / 1000.0, 1) FROM events WHERE e = 'race' AND ms > 0) AS avg_race_s,
      (SELECT ROUND(AVG(place), 2) FROM events WHERE e = 'race') AS avg_place,
      (SELECT ROUND(AVG(kills), 2) FROM events WHERE e = 'race') AS avg_kills,
      (SELECT COALESCE(SUM(goals),0) FROM events WHERE e = 'soccer') AS goals`);

  const sizes = q(`SELECT size, COUNT(*) AS races FROM events
    WHERE e = 'race' AND size IS NOT NULL GROUP BY size ORDER BY size`);

  const platforms = q(`SELECT platform, COUNT(DISTINCT uid) AS players,
      COUNT(*) AS sessions
    FROM events WHERE e = 'session' AND platform IS NOT NULL
    GROUP BY platform ORDER BY sessions DESC`);
  const versions = q(`SELECT version, COUNT(DISTINCT uid) AS players,
      COUNT(*) AS sessions, MAX(ts) AS last_ts
    FROM events WHERE e = 'session' AND version IS NOT NULL
    GROUP BY version ORDER BY last_ts DESC`);

  const ads = q1(`SELECT
      COUNT(*) AS views,
      SUM(CASE WHEN coins > 0 THEN 1 ELSE 0 END) AS pairs,
      COALESCE(SUM(coins),0) AS coins,
      COUNT(DISTINCT uid) AS players
    FROM events WHERE e = 'ad'`);
  const adsByDay = q(`SELECT day, COUNT(*) AS views,
      SUM(CASE WHEN coins > 0 THEN 1 ELSE 0 END) AS pairs
    FROM events WHERE e = 'ad' AND day >= ? GROUP BY day ORDER BY day`, from);

  const buys = q(`SELECT kind, COUNT(*) AS n, COALESCE(SUM(price),0) AS spent,
      COUNT(DISTINCT uid) AS players
    FROM events WHERE e = 'buy' AND kind IS NOT NULL
    GROUP BY kind ORDER BY spent DESC`);
  for (const r of buys) r.title = BUY_KINDS[r.kind] || r.kind;
  const topBuys = q(`SELECT kind, ikey, COUNT(*) AS n, COALESCE(SUM(price),0) AS spent
    FROM events WHERE e = 'buy' GROUP BY kind, ikey
    ORDER BY n DESC, spent DESC LIMIT 20`);

  const levels = q(`SELECT level, COUNT(*) AS ups FROM events
    WHERE e = 'level' AND level IS NOT NULL GROUP BY level ORDER BY level`);

  // Игроки: последнее известное состояние и активность.
  const players = q(`SELECT uid,
      (SELECT name FROM events e2 WHERE e2.uid = e1.uid AND e2.name <> ''
        ORDER BY ts DESC LIMIT 1) AS name,
      MIN(ts) AS first_ts, MAX(ts) AS last_ts,
      COUNT(DISTINCT day) AS days,
      SUM(CASE WHEN e = 'race' THEN 1 ELSE 0 END) AS races,
      SUM(CASE WHEN e = 'race' AND place = 1 THEN 1 ELSE 0 END) AS wins,
      SUM(CASE WHEN e = 'soccer' THEN 1 ELSE 0 END) AS soccer,
      SUM(CASE WHEN e = 'ad' THEN 1 ELSE 0 END) AS ads,
      SUM(CASE WHEN e = 'buy' THEN COALESCE(price,0) ELSE 0 END) AS spent,
      MAX(COALESCE(rating,0)) AS rating, MAX(COALESCE(level,0)) AS level,
      (SELECT platform FROM events e3 WHERE e3.uid = e1.uid
        AND platform IS NOT NULL ORDER BY ts DESC LIMIT 1) AS platform
    FROM events e1 WHERE uid <> '' GROUP BY uid
    ORDER BY last_ts DESC`);

  // Удержание: вернулся ли игрок на 1-й и 7-й день после первого входа.
  const seen = new Map();
  for (const r of q(`SELECT uid, day FROM events WHERE uid <> '' GROUP BY uid, day`)) {
    if (!seen.has(r.uid)) seen.set(r.uid, new Set());
    seen.get(r.uid).add(r.day);
  }
  let cohort = 0, d1 = 0, d7 = 0, cohort7 = 0;
  const tNow = Date.now() / 1000;
  for (const r of firstSeen) {
    const days = seen.get(r.uid);
    if (!days) continue;
    const t0 = Number(r.t);
    const age = (tNow - t0) / 86400;
    if (age >= 2) {
      cohort++;
      if (days.has(dayOf(t0 + 86400))) d1++;
    }
    if (age >= 8) {
      cohort7++;
      if (days.has(dayOf(t0 + 7 * 86400))) d7++;
    }
  }
  const retention = {
    cohort, d1, d1_pct: cohort ? Math.round((100 * d1) / cohort) : null,
    cohort7, d7, d7_pct: cohort7 ? Math.round((100 * d7) / cohort7) : null,
  };

  // Воронка: зашёл → проехал заезд → проехал пять заездов.
  const funnel = q1(`SELECT
      (SELECT COUNT(DISTINCT uid) FROM events WHERE uid <> '') AS came,
      (SELECT COUNT(*) FROM (SELECT uid FROM events WHERE e = 'race'
        GROUP BY uid)) AS raced,
      (SELECT COUNT(*) FROM (SELECT uid FROM events WHERE e = 'race'
        GROUP BY uid HAVING COUNT(*) >= 5)) AS raced5,
      (SELECT COUNT(*) FROM (SELECT uid FROM events WHERE e = 'buy'
        GROUP BY uid)) AS bought,
      (SELECT COUNT(*) FROM (SELECT uid FROM events WHERE e = 'ad'
        GROUP BY uid)) AS watched`);

  return {
    now: new Date().toISOString(), tz: CFG.tzOffsetHours, days,
    totals: { ...totals, new_week: newWeek }, live, byDay, cars, carBuys,
    tracks, weapons, modes, sizes, platforms, versions, ads, adsByDay,
    buys, topBuys, levels, players, retention, funnel,
    ingest: lastIngest,
  };
}

function recentEvents(limit) {
  return q(`SELECT ts, name, uid, e, d FROM events
    ORDER BY id DESC LIMIT ?`, Math.min(Math.max(limit | 0, 1), 500));
}

// ── страница ───────────────────────────────────────────────────────────────

const PAGE = String.raw`<!doctype html>
<html lang="ru"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>__TITLE__</title>
<style>
  :root {
    --bg:#15171b; --panel:#1e2126; --panel2:#242830; --line:#333946;
    --ink:#e8eaee; --dim:#9aa3b2; --yellow:#ffc61e; --teal:#35c9b5;
    --orange:#ff8c32; --red:#ef5b5b;
  }
  * { box-sizing:border-box; }
  body { margin:0; background:var(--bg); color:var(--ink);
    font:14px/1.45 "Segoe UI", system-ui, sans-serif; }
  header { padding:16px 20px; background:linear-gradient(180deg,#242831,#1b1e24);
    border-bottom:2px solid var(--line); display:flex; align-items:baseline;
    gap:14px; flex-wrap:wrap; }
  h1 { margin:0; font-size:20px; letter-spacing:.5px; color:var(--yellow); }
  .sub { color:var(--dim); font-size:12px; }
  main { padding:16px 20px 60px; max-width:1320px; margin:0 auto; }
  h2 { font-size:15px; margin:26px 0 10px; color:var(--teal);
    text-transform:uppercase; letter-spacing:1px; }
  .kpis { display:grid; gap:10px;
    grid-template-columns:repeat(auto-fit,minmax(150px,1fr)); }
  .kpi { background:var(--panel); border:1px solid var(--line);
    border-radius:10px; padding:12px 14px; }
  .kpi .cap { color:var(--dim); font-size:11px; text-transform:uppercase;
    letter-spacing:.6px; }
  .kpi .val { font-size:26px; font-weight:600; margin-top:2px; }
  .kpi .note { color:var(--dim); font-size:11px; }
  .cards { display:grid; gap:14px;
    grid-template-columns:repeat(auto-fit,minmax(330px,1fr)); }
  .card { background:var(--panel); border:1px solid var(--line);
    border-radius:10px; padding:14px; overflow:hidden; }
  .card h3 { margin:0 0 10px; font-size:13px; color:var(--dim);
    text-transform:uppercase; letter-spacing:.8px; font-weight:600; }
  table { width:100%; border-collapse:collapse; font-size:13px; }
  th, td { text-align:left; padding:5px 8px; border-bottom:1px solid #2b303a;
    white-space:nowrap; }
  th { color:var(--dim); font-weight:600; font-size:11px;
    text-transform:uppercase; letter-spacing:.5px; }
  td.n, th.n { text-align:right; font-variant-numeric:tabular-nums; }
  tr:last-child td { border-bottom:none; }
  .scroll { overflow-x:auto; }
  .bar { height:6px; border-radius:3px; background:var(--orange);
    min-width:2px; }
  .muted { color:var(--dim); }
  .tag { display:inline-block; padding:1px 7px; border-radius:10px;
    font-size:11px; background:var(--panel2); color:var(--dim);
    border:1px solid var(--line); }
  .chart { width:100%; height:190px; }
  .legend { display:flex; gap:14px; font-size:11px; color:var(--dim);
    margin-top:4px; flex-wrap:wrap; }
  .legend i { display:inline-block; width:10px; height:10px; border-radius:2px;
    margin-right:4px; vertical-align:-1px; }
  .feed { font-size:12px; max-height:420px; overflow:auto; }
  .feed div { padding:3px 0; border-bottom:1px solid #262b34; }
  .err { background:#3a1f1f; border:1px solid #6a3030; padding:10px;
    border-radius:8px; color:#ffc9c9; }
  button { background:var(--panel2); color:var(--ink); border:1px solid var(--line);
    border-radius:8px; padding:6px 12px; cursor:pointer; font-size:13px; }
  button:hover { border-color:var(--teal); }
</style></head>
<body>
<header>
  <h1>__TITLE__</h1>
  <span class="sub" id="meta">загрузка…</span>
  <span style="flex:1"></span>
  <button onclick="load()">обновить</button>
</header>
<main id="root"><p class="muted">загрузка…</p></main>
<script>
const R = (n) => (n == null ? '—' : Number(n).toLocaleString('ru-RU'));
const PCT = (a, b) => (b ? Math.round((100 * a) / b) + ' %' : '—');
const ESC = (s) => String(s == null ? '' : s).replace(/[&<>"]/g,
  (c) => ({ '&':'&amp;', '<':'&lt;', '>':'&gt;', '"':'&quot;' }[c]));
const DT = (ts) => new Date(ts * 1000).toLocaleString('ru-RU',
  { day:'2-digit', month:'2-digit', hour:'2-digit', minute:'2-digit' });

function kpi(cap, val, note) {
  return '<div class="kpi"><div class="cap">' + cap + '</div><div class="val">' +
    val + '</div>' + (note ? '<div class="note">' + note + '</div>' : '') + '</div>';
}

/** Столбики по дням: серии [{key,color,label}] из массива rows с полем day. */
function chart(rows, series) {
  if (!rows.length) return '<p class="muted">нет данных</p>';
  const W = Math.max(rows.length * 26, 320), H = 170, pad = 24;
  let max = 1;
  for (const r of rows) for (const s of series) max = Math.max(max, Number(r[s.key]) || 0);
  const bw = (W - pad * 2) / rows.length;
  let svg = '<svg class="chart" viewBox="0 0 ' + W + ' ' + (H + 26) +
    '" preserveAspectRatio="none">';
  for (let g = 0; g <= 2; g++) {
    const y = pad + ((H - pad) * g) / 2;
    svg += '<line x1="0" y1="' + y + '" x2="' + W + '" y2="' + y +
      '" stroke="#2b303a" stroke-width="1"/>';
    svg += '<text x="2" y="' + (y - 3) + '" fill="#6f7a8c" font-size="9">' +
      Math.round(max - (max * g) / 2) + '</text>';
  }
  rows.forEach((r, i) => {
    const x0 = pad + i * bw;
    series.forEach((s, k) => {
      const v = Number(r[s.key]) || 0;
      const h = ((H - pad) * v) / max;
      const w = (bw - 4) / series.length;
      svg += '<rect x="' + (x0 + 2 + k * w) + '" y="' + (H - h) + '" width="' +
        Math.max(w - 1, 1) + '" height="' + Math.max(h, v ? 1 : 0) +
        '" fill="' + s.color + '" rx="1"><title>' + r.day + ': ' + v +
        ' ' + s.label + '</title></rect>';
    });
    if (rows.length <= 32 || i % 2 === 0) {
      svg += '<text x="' + (x0 + bw / 2) + '" y="' + (H + 12) +
        '" fill="#6f7a8c" font-size="9" text-anchor="middle">' +
        r.day.slice(8) + '</text>';
    }
  });
  svg += '</svg><div class="legend">' + series.map((s) =>
    '<span><i style="background:' + s.color + '"></i>' + s.label + '</span>').join('') +
    '</div>';
  return svg;
}

/** Таблица с полоской-долей по главному числу (valTitle — подпись колонки). */
function tableBar(rows, nameKey, valKey, valTitle, cols) {
  if (!rows.length) return '<p class="muted">нет данных</p>';
  const max = Math.max(...rows.map((r) => Number(r[valKey]) || 0), 1);
  let h = '<div class="scroll"><table><tr><th>название</th><th class="n">' +
    valTitle + '</th><th></th>' +
    cols.map((c) => '<th class="n">' + c.title + '</th>').join('') + '</tr>';
  for (const r of rows) {
    h += '<tr><td>' + ESC(r[nameKey]) + '</td><td class="n">' +
      R(r[valKey]) + '</td><td style="width:90px"><div class="bar" style="width:' +
      Math.round((100 * (Number(r[valKey]) || 0)) / max) + '%"></div></td>' +
      cols.map((c) => '<td class="n">' + (c.fmt ? c.fmt(r) : R(r[c.key])) +
        '</td>').join('') + '</tr>';
  }
  return h + '</table></div>';
}

function card(title, body) {
  return '<div class="card"><h3>' + title + '</h3>' + body + '</div>';
}

let DATA = null;

async function load() {
  const r = await fetch('api/summary?days=30', { credentials: 'same-origin' });
  if (!r.ok) {
    document.getElementById('root').innerHTML =
      '<div class="err">Сервер ответил ' + r.status + '. Проверьте ссылку с паролем.</div>';
    return;
  }
  DATA = await r.json();
  const f = await fetch('api/events?limit=120', { credentials: 'same-origin' });
  DATA.feed = f.ok ? await f.json() : [];
  render();
}

function render() {
  const d = DATA, t = d.totals, l = d.live, m = d.modes;
  document.getElementById('meta').textContent =
    'игроков ' + R(t.players) + ' · событий ' + R(t.events) +
    ' · последнее ' + (t.last_ts ? DT(t.last_ts) : '—') +
    ' · сутки считаются по UTC+' + d.tz;
  let h = '<div class="kpis">' +
    kpi('Игроков всего', R(t.players), 'уникальных профилей') +
    kpi('Новых за 7 дней', R(t.new_week), 'первый вход') +
    kpi('Играли сегодня', R(l.dau), 'за 7 дней: ' + R(l.wau)) +
    kpi('Заездов всего', R(t.races), 'сегодня ' + R(l.races_today) +
      ', за 7 дней ' + R(l.races_week)) +
    kpi('Матчей футбола', R(t.soccer), 'голов ' + R(m.goals)) +
    kpi('Роликов рекламы', R(d.ads.views), 'пар досмотрено ' + R(d.ads.pairs) +
      ', монет ' + R(d.ads.coins)) +
    kpi('Покупок', R(t.buys), 'на ' + R(t.spent) + ' монет') +
    kpi('Удержание D1', d.retention.d1_pct == null ? '—' : d.retention.d1_pct + ' %',
      'из ' + R(d.retention.cohort) + ' игроков; D7 ' +
      (d.retention.d7_pct == null ? '—' : d.retention.d7_pct + ' %')) +
    '</div>';

  h += '<h2>По дням (30 суток)</h2><div class="cards">' +
    card('Игроки и новички', chart(d.byDay, [
      { key:'players', color:'#35c9b5', label:'играли' },
      { key:'newcomers', color:'#ffc61e', label:'новые' }])) +
    card('Заезды, матчи, входы', chart(d.byDay, [
      { key:'races', color:'#ff8c32', label:'заезды' },
      { key:'soccer', color:'#8a7bff', label:'футбол' },
      { key:'sessions', color:'#5b8cff', label:'входы' }])) +
    card('Ролики рекламы', chart(d.byDay, [
      { key:'ads', color:'#ef5b5b', label:'ролики досмотрены' }])) +
    card('Потрачено монет в магазине', chart(d.byDay, [
      { key:'spent', color:'#8bd450', label:'монет' }])) +
    '</div>';

  h += '<h2>Машины</h2><div class="cards">' +
    card('Заезды по машинам (что любят)', tableBar(d.cars, 'title', 'races',
      'заездов', [
      { title:'игроков', key:'players' },
      { title:'ср. место', key:'avg_place' },
      { title:'побед', key:'wins' },
      { title:'доля', fmt:(r) => PCT(r.races, t.races) }])) +
    card('Покупки машин', tableBar(d.carBuys, 'title', 'n', 'куплено', [
      { title:'монет', key:'spent' }])) +
    '</div>';

  h += '<h2>Заезды</h2><div class="cards">' +
    card('Как играют', '<table>' +
      row('Заездов всего', R(t.races)) +
      row('По сети', R(m.online) + ' (' + PCT(m.online, t.races) + ')') +
      row('Одному с ботами', R(m.offline) + ' (' + PCT(m.offline, t.races) + ')') +
      row('В команде друзей', R(m.party) + ' · запусков команды ' + R(m.party_launch)) +
      row('Средняя длительность', m.avg_race_s == null ? '—' : m.avg_race_s + ' с') +
      row('Среднее место', R(m.avg_place)) +
      row('Уничтожено за заезд', R(m.avg_kills)) + '</table>') +
    card('Трассы', tableBar(d.tracks, 'title', 'races', 'заездов', [
      { title:'ср. место', key:'avg_place' },
      { title:'доля', fmt:(r) => PCT(r.races, t.races) }])) +
    card('Размер заезда', tableBar(d.sizes.map((r) =>
      ({ title:r.size + ' участника', races:r.races })), 'title', 'races',
      'заездов', [{ title:'доля', fmt:(r) => PCT(r.races, t.races) }])) +
    card('Оружие: сколько раз применяли', tableBar(d.weapons, 'title', 'uses',
      'применений', [{ title:'игроков', key:'players' }])) +
    '</div>';

  h += '<h2>Деньги и реклама</h2><div class="cards">' +
    card('Реклама', '<table>' +
      row('Роликов досмотрено', R(d.ads.views)) +
      row('Пар (награда +500)', R(d.ads.pairs)) +
      row('Монет выдано', R(d.ads.coins)) +
      row('Смотрят игроков', R(d.ads.players) + ' из ' + R(t.players)) +
      row('Роликов на игрока', d.ads.players ?
        (d.ads.views / d.ads.players).toFixed(1) : '—') + '</table>') +
    card('Покупки по типам', tableBar(d.buys, 'title', 'spent', 'монет', [
      { title:'покупок', key:'n' }, { title:'игроков', key:'players' }])) +
    card('Что покупают чаще', '<div class="scroll"><table>' +
      '<tr><th>тип</th><th>что</th><th class="n">раз</th><th class="n">монет</th></tr>' +
      d.topBuys.map((r) => '<tr><td><span class="tag">' + ESC(r.kind) +
        '</span></td><td>' + ESC(r.ikey) + '</td><td class="n">' + R(r.n) +
        '</td><td class="n">' + R(r.spent) + '</td></tr>').join('') +
      '</table></div>') +
    card('Взятые уровни', tableBar(d.levels.map((r) =>
      ({ title:'уровень ' + r.level, ups:r.ups })), 'title', 'ups',
      'раз взят', [])) +
    '</div>';

  h += '<h2>Платформы и воронка</h2><div class="cards">' +
    card('Платформы', tableBar(d.platforms.map((r) =>
      ({ title:r.platform, sessions:r.sessions, players:r.players })),
      'title', 'sessions', 'входов', [{ title:'игроков', key:'players' }])) +
    card('Версии сборки', '<div class="scroll"><table>' +
      '<tr><th>версия</th><th class="n">входов</th><th class="n">игроков</th>' +
      '<th>последний вход</th></tr>' + d.versions.map((r) =>
        '<tr><td>' + ESC(r.version) + '</td><td class="n">' + R(r.sessions) +
        '</td><td class="n">' + R(r.players) + '</td><td>' + DT(r.last_ts) +
        '</td></tr>').join('') + '</table></div>') +
    card('Воронка', '<table>' +
      row('Зашли', R(d.funnel.came)) +
      row('Проехали заезд', R(d.funnel.raced) + ' (' +
        PCT(d.funnel.raced, d.funnel.came) + ')') +
      row('Проехали 5 и больше', R(d.funnel.raced5) + ' (' +
        PCT(d.funnel.raced5, d.funnel.came) + ')') +
      row('Что-то купили', R(d.funnel.bought) + ' (' +
        PCT(d.funnel.bought, d.funnel.came) + ')') +
      row('Смотрели рекламу', R(d.funnel.watched) + ' (' +
        PCT(d.funnel.watched, d.funnel.came) + ')') + '</table>') +
    '</div>';

  h += '<h2>Игроки (' + R(d.players.length) + ')</h2><div class="card scroll">' +
    '<table><tr><th>имя</th><th class="n">рейтинг</th><th class="n">ур.</th>' +
    '<th class="n">заездов</th><th class="n">побед</th><th class="n">футбол</th>' +
    '<th class="n">реклама</th><th class="n">траты</th><th class="n">дней</th>' +
    '<th>первый вход</th><th>последний</th><th>платформа</th></tr>' +
    d.players.map((p) => '<tr><td>' + ESC(p.name || p.uid.slice(0, 8)) +
      '</td><td class="n">' + R(p.rating) + '</td><td class="n">' + R(p.level) +
      '</td><td class="n">' + R(p.races) + '</td><td class="n">' + R(p.wins) +
      '</td><td class="n">' + R(p.soccer) + '</td><td class="n">' + R(p.ads) +
      '</td><td class="n">' + R(p.spent) + '</td><td class="n">' + R(p.days) +
      '</td><td>' + DT(p.first_ts) + '</td><td>' + DT(p.last_ts) +
      '</td><td>' + ESC(p.platform || '—') + '</td></tr>').join('') +
    '</table></div>';

  h += '<h2>Последние события</h2><div class="card feed">' +
    d.feed.map((ev) => '<div><span class="muted">' + DT(ev.ts) + '</span> ' +
      '<span class="tag">' + ESC(ev.e) + '</span> ' +
      ESC(ev.name || ev.uid.slice(0, 8)) + ' <span class="muted">' +
      ESC(ev.d).slice(0, 200) + '</span></div>').join('') + '</div>';

  h += '<p class="muted" style="margin-top:22px">Чтение файлов метрик: ' +
    (d.ingest.note ? ESC(d.ingest.note) : 'последний проход ' +
      DT(d.ingest.at / 1000) + ', новых строк ' + R(d.ingest.lines) +
      (d.ingest.errors ? ', битых ' + R(d.ingest.errors) : '')) + '</p>';

  document.getElementById('root').innerHTML = h;
}

function row(k, v) {
  return '<tr><td class="muted">' + k + '</td><td class="n">' + v + '</td></tr>';
}

load();
setInterval(load, 60000);
</script></body></html>`;

// ── HTTP ───────────────────────────────────────────────────────────────────

function authorized(req) {
  const url = new URL(req.url, 'http://x');
  if (url.searchParams.get('k') === CFG.token) return 'fresh';
  const cookie = req.headers.cookie || '';
  for (const part of cookie.split(';')) {
    const [k, v] = part.trim().split('=');
    if (k === 'bhrk' && v === encodeURIComponent(CFG.token)) return true;
  }
  const hdr = req.headers.authorization || '';
  if (hdr.startsWith('Basic ')) {
    const raw = Buffer.from(hdr.slice(6), 'base64').toString('utf8');
    if (raw.split(':').pop() === CFG.token) return true;
  }
  return false;
}

function send(res, code, body, type) {
  res.writeHead(code, {
    'Content-Type': type || 'application/json; charset=utf-8',
    'Cache-Control': 'no-store',
  });
  res.end(body);
}

const server = http.createServer((req, res) => {
  const url = new URL(req.url, 'http://x');
  if (url.pathname === '/healthz') {
    return send(res, 200, JSON.stringify({ ok: true, events: q1(
      'SELECT COUNT(*) AS n FROM events').n }));
  }
  const ok = authorized(req);
  if (!ok) {
    res.writeHead(401, {
      'WWW-Authenticate': 'Basic realm="bhr-metrics"',
      'Content-Type': 'text/html; charset=utf-8',
    });
    return res.end('<h3>Нужен пароль панели</h3><p>Откройте ссылку с ' +
      '<code>?k=ПАРОЛЬ</code> (см. config.json на сервере).</p>');
  }
  const headers = {};
  if (ok === 'fresh') {
    headers['Set-Cookie'] = 'bhrk=' + encodeURIComponent(CFG.token) +
      '; Max-Age=31536000; Path=/; HttpOnly; SameSite=Lax';
  }
  try {
    if (url.pathname === '/' || url.pathname === '/index.html') {
      res.writeHead(200, { ...headers,
        'Content-Type': 'text/html; charset=utf-8', 'Cache-Control': 'no-store' });
      return res.end(PAGE.replaceAll('__TITLE__', CFG.title));
    }
    if (url.pathname === '/api/summary') {
      const days = Math.min(Math.max(Number(url.searchParams.get('days')) || 30, 1), 365);
      res.writeHead(200, { ...headers,
        'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
      return res.end(JSON.stringify(summary(days)));
    }
    if (url.pathname === '/api/events') {
      const limit = Number(url.searchParams.get('limit')) || 120;
      res.writeHead(200, { ...headers,
        'Content-Type': 'application/json; charset=utf-8', 'Cache-Control': 'no-store' });
      return res.end(JSON.stringify(recentEvents(limit)));
    }
    // Выгрузка всех событий для своего анализа (Excel, Python).
    if (url.pathname === '/api/export.csv') {
      const rows = q(`SELECT ts, day, name, e, platform, version, place, size,
        online, party, car, kills, deaths, track, ms, rating, level, result,
        goals, coins, price, kind, ikey FROM events ORDER BY id`);
      const cols = rows.length ? Object.keys(rows[0]) : ['ts'];
      const csv = [cols.join(';')].concat(rows.map((r) => cols.map((c) =>
        r[c] == null ? '' : String(r[c]).replace(/[;\n\r]/g, ' ')).join(';')));
      res.writeHead(200, { ...headers, 'Content-Type': 'text/csv; charset=utf-8',
        'Content-Disposition': 'attachment; filename="bhr-metrics.csv"' });
      return res.end('﻿' + csv.join('\n'));
    }
    send(res, 404, JSON.stringify({ error: 'нет такой страницы' }));
  } catch (e) {
    console.error('[http] ' + url.pathname + ': ' + e.stack);
    send(res, 500, JSON.stringify({ error: e.message }));
  }
});

ingest();
setInterval(ingest, POLL_MS);
server.listen(CFG.port, CFG.host, () => {
  console.log('[web] аналитика слушает http://' + CFG.host + ':' + CFG.port +
    '/?k=' + CFG.token);
  console.log('[web] файлы метрик: ' + CFG.metricsDir);
});

process.on('SIGTERM', () => { server.close(); db.close(); process.exit(0); });
