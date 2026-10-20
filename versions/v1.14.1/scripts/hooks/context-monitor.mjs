#!/usr/bin/env node
/**
 * context-monitor.mjs — StatusLine hook do Claude Code.
 *
 * Recebe na stdin um JSON com métricas de contexto (a StatusLine é o único hook
 * que recebe isso em tempo real). Quando o uso cruza CTX_THRESHOLD:
 *   - acende um flag visível na barra de status;
 *   - grava um backup bruto de segurança em <PROJECT_ARCHIVE>;
 *   - registra o "epoch" pra não regravar a cada render dentro da mesma faixa.
 *
 * O MD rico (context.md + checklist.md) é gerado pelo PRÓPRIO Claude, instruído
 * via CLAUDE.md ao ver o flag — aqui é só detecção + rede de segurança.
 *
 * Env:
 *   CTX_THRESHOLD     tokens p/ disparar (default 250000 — ~25% de janela 1M)
 *   PROJECT_ARCHIVE   pasta de archive (default ./<projeto>_archive/context)
 *
 * IMPORTANTE: confirme o shape do JSON na sua versão do Claude Code.
 *   Rode uma vez com a linha `console.error(JSON.stringify(input))` e compare
 *   com a saída de /context. Ajuste os campos se necessário.
 */
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

const THRESHOLD = Number(process.env.CTX_THRESHOLD ?? 250000);
const ARCHIVE = process.env.PROJECT_ARCHIVE ?? "./PROJETO_archive/context";

function readStdin() {
  try { return JSON.parse(fs.readFileSync(0, "utf8")); }
  catch { return {}; }
}

// Extrai tokens usados de formatos conhecidos (defensivo entre versões).
function usedTokens(input) {
  const cw = input.context_window ?? input.contextWindow ?? {};
  if (typeof cw.used_tokens === "number") return cw.used_tokens;
  if (typeof cw.used === "number") return cw.used;
  const total = cw.total ?? cw.total_tokens ?? cw.size ?? 0;
  const remPct = cw.remaining_percentage ?? cw.remainingPercentage;
  if (total && typeof remPct === "number") {
    return Math.round(total * (1 - remPct / 100));
  }
  return 0;
}

const input = readStdin();
// console.error(JSON.stringify(input)); // <- descomente UMA vez p/ inspecionar o shape
const used = usedTokens(input);
const sid = input.session_id ?? input.sessionId ?? "session";

const stateFile = path.join(os.homedir(), ".claude", "ctx-state.json");
let state = {};
try { state = JSON.parse(fs.readFileSync(stateFile, "utf8")); } catch {}

let flag = "";
if (used >= THRESHOLD) {
  const epoch = `${sid}:${Math.floor(used / THRESHOLD)}`;
  if (state.lastEpoch !== epoch) {
    try {
      fs.mkdirSync(ARCHIVE, { recursive: true });
      const ts = new Date().toISOString().replace(/[:.]/g, "-");
      fs.writeFileSync(
        path.join(ARCHIVE, `${ts}-raw-backup.md`),
        `# Snapshot automático de contexto\n\n` +
        `- tokens usados: ${used}\n- limite: ${THRESHOLD}\n` +
        `- session: ${sid}\n- transcript: ${input.transcript_path ?? input.transcriptPath ?? "?"}\n\n` +
        `> Rede de segurança determinística. O handoff rico (context.md + checklist.md)\n` +
        `> deve ser gerado pelo Claude conforme o CLAUDE.md, e então rodar /compact.\n`
      );
      state.lastEpoch = epoch;
      fs.mkdirSync(path.dirname(stateFile), { recursive: true });
      fs.writeFileSync(stateFile, JSON.stringify(state));
    } catch (e) {
      // nunca derruba a status line por falha de IO
      flag = " (ctx-monitor IO err)";
    }
    flag = " ⚠ LIMITE: gerar context.md + checklist.md em <projeto>_archive e rodar /compact";
  } else {
    flag = " ⚠ acima do limite (handoff já marcado)";
  }
}

process.stdout.write(`ctx ${used} tok / limite ${THRESHOLD}${flag}`);
