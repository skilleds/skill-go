#!/usr/bin/env node
/**
 * precompact-backup.mjs — PreCompact hook do Claude Code.
 *
 * Dispara logo ANTES de toda compactação (manual /compact ou automática).
 * Última chance de capturar estado: faz um dump determinístico do transcript
 * em <PROJECT_ARCHIVE>, independente de o agente ter gerado os MDs ricos.
 *
 * Recebe na stdin um JSON com (entre outros) session_id, transcript_path e
 * trigger ("manual" | "auto"). Nomes podem variar por versão — trate ambos.
 *
 * Env:
 *   PROJECT_ARCHIVE   pasta de archive (default ./<projeto>_archive/context)
 */
import fs from "node:fs";
import path from "node:path";

const ARCHIVE = process.env.PROJECT_ARCHIVE ?? "./PROJETO_archive/context";

function readStdin() {
  try { return JSON.parse(fs.readFileSync(0, "utf8")); }
  catch { return {}; }
}

const input = readStdin();
const sid = input.session_id ?? input.sessionId ?? "session";
const trigger = input.trigger ?? input.reason ?? "unknown";
const transcript = input.transcript_path ?? input.transcriptPath ?? null;

try {
  fs.mkdirSync(ARCHIVE, { recursive: true });
  const ts = new Date().toISOString().replace(/[:.]/g, "-");

  // Parse leve do transcript JSONL -> pontos-chave (sem PII além do necessário).
  let userAsks = [], filesTouched = new Set(), lastAssistant = "";
  if (transcript && fs.existsSync(transcript)) {
    for (const line of fs.readFileSync(transcript, "utf8").split("\n")) {
      if (!line.trim()) continue;
      let ev; try { ev = JSON.parse(line); } catch { continue; }
      const role = ev.role ?? ev.message?.role;
      const text = ev.content ?? ev.message?.content;
      const str = typeof text === "string" ? text : JSON.stringify(text ?? "");
      if (role === "user" && str) userAsks.push(str.slice(0, 200));
      if (role === "assistant" && str) lastAssistant = str.slice(0, 400);
      const m = str.match(/(?:edit|write|create)[^\n]*?([\w./-]+\.\w+)/gi);
      if (m) m.forEach(x => filesTouched.add(x));
    }
  }

  const md =
    `# Backup pré-compactação (${trigger})\n\n` +
    `- session: ${sid}\n- quando: ${ts}\n- transcript: ${transcript ?? "?"}\n\n` +
    `## Pedidos do usuário (recentes)\n` +
    (userAsks.slice(-10).map(a => `- ${a}`).join("\n") || "- (sem dados)") + `\n\n` +
    `## Arquivos tocados (heurística)\n` +
    ([...filesTouched].map(f => `- ${f}`).join("\n") || "- (sem dados)") + `\n\n` +
    `## Última resposta do agente (trecho)\n${lastAssistant || "(sem dados)"}\n`;

  fs.writeFileSync(path.join(ARCHIVE, `${ts}-precompact-${trigger}.md`), md);
} catch (e) {
  // não bloquear a compactação por falha de backup
  process.stderr.write(`precompact-backup: ${e.message}\n`);
}

// exit 0 sem JSON = deixa a compactação seguir
process.exit(0);
