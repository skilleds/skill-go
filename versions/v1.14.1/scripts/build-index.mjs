#!/usr/bin/env node
/**
 * build-index.mjs — gera o índice de microfunções (§39) a partir dos doc-comments
 * obrigatórios das funções (§6). É o gerador que o gate `check-index.sh` compara
 * contra o índice commitado.
 *
 * Convenção lida: um doc-comment imediatamente acima da função, com as linhas
 *     O quê: <descrição>
 *     Onde:  <onde é usada / prevista>
 *     Efeitos: <opcional>
 * seguido da declaração. Emite uma tabela markdown por arquivo.
 *
 * Uso (o índice mora no archive, nunca no root — §28):
 *   node build-index.mjs <dir-de-origem> > <projeto>_archive/index/INDEX_FUNCTIONS.md
 *
 * PISOS desta ferramenta (corrigem os achados A8–A12 da vistoria de 2026-08-21):
 *   - ENUMERA o que a casa usa de verdade: shell, python, ruby, go, rust, elixir, c#, zig, TS/JS.
 *   - PEGA as formas que a versão antiga perdia: one-liner de shell, `def`, método de classe,
 *     generator (`function* x`), método com receiver em Go, `fn` em `impl`.
 *   - CONFERE COMPLETUDE: conta N (declarações vistas) e M (entradas emitidas) e REPROVA se
 *     `M < N` **ou se N == 0**. Alvo onde o detector não enumerou nada NÃO pode sair verde.
 *   - CHAVEIA o nó por `arquivo:linha`: homônimo em arquivos diferentes não colapsa.
 *   - É DETERMINÍSTICO: sem `new Date()` na saída — senão o `diff` do gate nunca fecha (era
 *     por isso que o gate vivia comentado).
 *
 * Exit: 0 índice completo e com doc — 1 doc-comment ausente, M < N, ou nenhuma unidade.
 */
import fs from "node:fs";
import path from "node:path";

const ROOT = process.argv[2] ?? "src";

// A8 — as extensões que a casa realmente usa (o rol sancionado + shell/python + frontend).
const EXTS = new Set([
  ".ts", ".tsx", ".js", ".jsx", ".mjs", ".cjs", ".go", ".rs",
  ".sh", ".bash", ".py", ".rb", ".ex", ".exs", ".cs", ".zig",
]);

// A9 — uma tabela de declaração por família de linguagem. Cada regex devolve o nome no grupo 1.
const SHELL = [
  /^\s*(?:function\s+)?([A-Za-z_][A-Za-z0-9_:.-]*)\s*\(\s*\)\s*\{/,   // nome() { … }  e o one-liner
  /^\s*function\s+([A-Za-z_][A-Za-z0-9_:.-]*)\s*\{/,
];
const PY = [/^\s*(?:async\s+)?def\s+([A-Za-z_]\w*)\s*\(/, /^\s*class\s+([A-Za-z_]\w*)\s*[(:]/];
const RB = [/^\s*def\s+(?:self\.)?([A-Za-z_]\w*[?!=]?)/, /^\s*(?:class|module)\s+([A-Z]\w*)/];
const GO = [/^\s*func\s+(?:\([^)]*\)\s*)?([A-Za-z_]\w*)\s*[[(]/];      // inclui método com receiver
const RS = [/^\s*(?:pub(?:\([^)]*\))?\s+)?(?:async\s+)?(?:const\s+|unsafe\s+|extern\s+"[^"]*"\s+)*fn\s+([A-Za-z_]\w*)/];
const EX = [/^\s*def(?:p|macro|macrop)?\s+([a-z_]\w*[?!]?)/, /^\s*defmodule\s+([A-Z][\w.]*)/];
const CS = [
  /^\s*(?:\[[^\]]*\]\s*)*(?:public|private|protected|internal|static|async|sealed|virtual|override|partial|\s)+[A-Za-z_][\w<>,.\[\]?]*\s+([A-Za-z_]\w*)\s*\([^)]*\)\s*(?:\{|=>|$)/,
  /^\s*(?:public|internal|private|sealed|abstract|static|partial|\s)*(?:class|record|struct|interface)\s+([A-Za-z_]\w*)/,
];
const ZIG = [/^\s*(?:pub\s+)?(?:export\s+|inline\s+|noinline\s+)?fn\s+([A-Za-z_]\w*)/];
const JS = [
  /^\s*(?:export\s+)?(?:default\s+)?(?:async\s+)?function\s*\*?\s*([A-Za-z_$][\w$]*)\s*\(/,   // inclui generator
  /^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?(?:function\s*\*?\s*)?\(/,
  /^\s*(?:export\s+)?(?:const|let|var)\s+([A-Za-z_$][\w$]*)\s*=\s*(?:async\s*)?[A-Za-z_$][\w$]*\s*=>/,
  /^\s*(?:export\s+)?(?:abstract\s+)?class\s+([A-Za-z_$][\w$]*)/,
  /^\s*(?:static\s+)?(?:async\s+)?(?:get\s+|set\s+)?\*?\s*([A-Za-z_$][\w$]*)\s*\([^)]*\)\s*\{/,  // método de classe/objeto
];
const PATTERNS = {
  ".sh": SHELL, ".bash": SHELL, ".py": PY, ".rb": RB, ".go": GO, ".rs": RS,
  ".ex": EX, ".exs": EX, ".cs": CS, ".zig": ZIG,
};
// Palavras que casam com a forma "método" e são controle de fluxo, não declaração.
const NAO_DECL = new Set(["if", "for", "while", "switch", "catch", "do", "else", "return",
  "function", "case", "with", "match", "loop", "defer", "go", "select", "using", "lock", "try"]);

/** declName — devolve o nome declarado na linha, ou null. Fonte única de N e de M. */
function declName(ext, line) {
  if (/^\s*(?:\/\/|#|\*|--)/.test(line)) return null;                 // linha comentada
  for (const re of (PATTERNS[ext] ?? JS)) {
    const m = re.exec(line);
    if (m && m[1] && !NAO_DECL.has(m[1])) return m[1];
  }
  return null;
}

/** walk — enumera arquivos de código sob `dir`, pulando .git, node_modules e vendor. */
function* walk(dir) {
  for (const e of fs.readdirSync(dir, { withFileTypes: true }).sort((a, b) => a.name < b.name ? -1 : 1)) {
    if (e.name === "node_modules" || e.name === "vendor" || e.name === "target" || e.name.startsWith(".")) continue;
    const p = path.join(dir, e.name);
    if (e.isDirectory()) yield* walk(p);
    else if (EXTS.has(path.extname(e.name))) yield p;
  }
}

/**
 * field — extrai um campo do doc-comment. O rótulo é procurado FORA de código inline: um
 * doc-comment que *fala sobre* os rótulos (`O quê:` entre crases) não deve virar o valor.
 */
function field(block, label) {
  const limpo = block.replace(/`[^`\n]*`/g, "");
  const m = limpo.match(new RegExp(`${label}\\s*:\\s*(.+)`, "i"));
  return m ? m[1].trim().replace(/\*\/\s*$/, "").replace(/\|/g, "\\|").trim() : "";
}

/** docBlock — o comentário CONTÍGUO imediatamente acima da declaração (bloco ou linhas). */
function docBlock(lines, i, ext) {
  let j = i - 1;
  while (j >= 0 && lines[j].trim() === "") j--;
  if (j < 0) return "";
  if (/\*\//.test(lines[j])) {                                        // /* … */
    let k = j;
    while (k >= 0 && !/\/\*/.test(lines[k])) k--;
    return k >= 0 ? lines.slice(k, j + 1).join("\n") : "";
  }
  const linha = ext === ".sh" || ext === ".bash" || ext === ".py" || ext === ".rb" || ext === ".ex" || ext === ".exs"
    ? /^\s*#/ : /^\s*\/\//;
  if (linha.test(lines[j])) {
    let k = j;
    while (k >= 0 && linha.test(lines[k])) k--;
    return lines.slice(k + 1, j + 1).join("\n");
  }
  return "";
}

const byFile = new Map();
let missing = 0, N = 0;
const chaves = new Set();                                             // A11 — chave = arquivo:linha

let raiz;
try { raiz = fs.statSync(ROOT).isDirectory() ? ROOT : path.dirname(ROOT); }
catch { console.error(`origem não existe: ${ROOT}`); process.exit(1); }

for (const file of walk(raiz)) {
  const ext = path.extname(file);
  const lines = fs.readFileSync(file, "utf8").split("\n");
  for (let i = 0; i < lines.length; i++) {
    const name = declName(ext, lines[i]);
    if (!name) continue;
    N++;
    const block = docBlock(lines, i, ext);
    const what = field(block, "O qu[êe]") || field(block, "what");
    const where = field(block, "Onde") || field(block, "usedby");
    const fx = field(block, "Efeitos") || field(block, "effects");
    if (!what || !where) missing++;
    const rel = path.relative(raiz, file) || path.basename(file);
    if (!byFile.has(rel)) byFile.set(rel, []);
    byFile.get(rel).push({ name, what: what || "SEM DOC (§6)", where: where || "SEM DOC (§6)", fx, line: i + 1 });
    chaves.add(`${rel}:${i + 1}`);
  }
}

const M = chaves.size;
const out = [];
out.push("# Índice de Microfunções (gerado)", "");
out.push(`> Gerado por \`build-index.mjs\` a partir de \`${path.normalize(raiz)}\`. Não editar à mão.`);
out.push(`> Determinístico por construção: a saída depende só da origem — o gate \`check-index.sh\` compara com o commitado.`, "");
out.push(`> **Completude (§39):** N declarações vistas = **${N}** · M entradas emitidas = **${M}** · sem doc-comment = **${missing}**.`, "");
if (missing) out.push(`> ATENÇÃO: ${missing} unidade(s) sem doc-comment de contexto completo (§6). Corrija na origem.`, "");
for (const [file, fns] of [...byFile].sort()) {
  out.push(`## ${file}`, "");
  out.push("| Função | O quê | Onde é usada | Efeitos | Linha |", "|---|---|---|---|---|");
  for (const f of fns) out.push(`| \`${f.name}\` | ${f.what} | ${f.where} | ${f.fx} | ${f.line} |`);
  out.push("");
}
process.stdout.write(out.join("\n") + "\n");

// A10 — a conciliação que faltava: alvo vazio ou entrada perdida REPROVA. Um índice de aparência
// normal sobre zero função enumerada é o mesmo verde vacuamente verdadeiro do A1.
if (N === 0) {
  console.error(`ZERO unidades enumeradas em ${raiz} — o detector não enxergou o alvo (§39). Confira EXTS/declName.`);
  process.exit(1);
}
if (M < N) {
  console.error(`incompletude: N=${N} declarações vistas, M=${M} entradas emitidas.`);
  process.exit(1);
}
process.exit(missing > 0 ? 1 : 0);
