# seguranca — recorte Go

> **PONTEIRO, não cópia.** A normativa deste tema é da base: **`schematize-engineering`** →
> `references/seguranca.md`. Leia lá primeiro; aqui fica **só o que muda em Go**.
>
> **Onde este arquivo divergir da base, a BASE MANDA** (`SKILL.md` §"Precedência e herança").
> Este arquivo era um clone com **96%** de conteúdo
> idêntico à base — deriva por cópia foi o achado da Classe C da vistoria de 2026-08-21, e ela
> já tinha atingido piso de segurança (o `argon2id-only` da casa virou "ou PBKDF2" numa skill,
> o rol de 6 linguagens virou "só Go e Rust" em três). Manter uma cópia é manter a próxima deriva.
O piso de segurança da base vale integralmente em Go. **O que muda de forma** é o scanner: o
pipeline MUST da base fala em SAST/SCA genéricos, e em Go o obrigatório é o **oficial**:

- **`govulncheck ./...` no CI, travando o merge.** Ele é diferente de um SCA comum porque usa
  **alcançabilidade**: cruza o banco oficial (`vuln.go.dev`) com a **análise estática de chamadas**
  do seu binário e só reporta a vulnerabilidade que o **seu código realmente alcança**. Na prática
  isso é o que faz o gate ser cumprível — um SCA que lista toda CVE de toda dependência transitiva
  vira ruído, e ruído se ignora. O silêncio dele também é informação: "a CVE existe mas você não
  chama aquela função" é uma resposta útil, e é a que um SCA genérico não sabe dar.
- **`go vet ./...`** no mesmo gate (é análise, não estilo), e **`go test -race`** — corrida é bug de
  segurança quando o dado corrompido é decisão de authz.
- Versão da toolchain dentro da janela suportada: fora dela **não há patch de segurança**
  (`references/stack-versoes.md`).

**Fronteira:** as regras de segurança de **frontend** (token em cookie `HttpOnly` e nunca em
`localStorage`, CSP e headers, `dangerouslySetInnerHTML`, open redirect) são da
`schematize-web` → `references/seguranca.md` §43 — não desta skill. Este arquivo trazia uma
cópia delas, que é como a mesma regra passa a existir em dois lugares e diverge.

