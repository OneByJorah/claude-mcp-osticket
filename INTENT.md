# INTENT.md — J1-PIPELINE Phase -1 (ORACLE)

**Repository:** `OneByJorah/claude-mcp-osticket`
**Analysis Date:** 2026-07-05
**Analyst:** J1-PIPELINE ORACLE (read-only)
**Status:** Intent Reconstructed

---

## What This System Does

**osTicket MCP Server** is a TypeScript/Node.js server that implements the [Model Context Protocol (MCP)](https://modelcontextprotocol.io/) to provide AI assistants — primarily Claude Code — with direct, tool-driven access to an [osTicket](https://osticket.com/) helpdesk instance via its REST API.

It exposes **12 MCP tools** across three functional domains:

| Domain | Tools | Description |
|--------|-------|-------------|
| **Core Ticket Management** | `osticket_get_ticket`, `osticket_list_tickets`, `osticket_search_tickets`, `osticket_get_stats`, `osticket_create_ticket`, `osticket_update_ticket`, `osticket_delete_ticket` | Full CRUD + search + statistics for helpdesk tickets |
| **Subticket Management** | `osticket_get_parent_ticket`, `osticket_get_child_tickets`, `osticket_create_subticket_link`, `osticket_unlink_subticket` | Parent-child ticket relationships (requires Subticket Manager Plugin) |
| **Attachment Operations** | `osticket_download_attachment` | Download ticket attachments to local temp files |

### Operational Role

The server runs as a **stdio-based MCP subprocess** launched by the AI assistant (Claude Code, or any MCP host). It communicates via JSON-RPC over stdin/stdout. At runtime it:

1. Reads configuration from `~/.claude/mcp-servers/osticket/.env` (API URL + API key)
2. Connects to a live osTicket instance via its REST API endpoints
3. Validates all tool inputs with Zod schemas at runtime
4. Returns structured JSON responses with actionable error messages
5. Logs to `~/.claude/mcp-servers/osticket/logs/server.log` with rotation

The system is **not a standalone service** — it has no HTTP server, no database, and no UI. It is a bridge between an AI assistant and an existing osTicket helpdesk.

---

## Why This Was Built

### Real Problem

AI coding assistants like Claude Code can read and write code, but they cannot interact with operational business systems. Helpdesk ticket management is a core operational workflow — developers and support teams need to create, read, update, and search tickets as part of their daily work. Without this bridge, a developer using Claude Code would have to:

- Switch context to a browser or terminal to check ticket status
- Manually copy-paste ticket information into the AI conversation
- Manually create tickets from AI-generated summaries

This context-switching destroys the flow state that AI assistants are meant to enable.

### Why Existing Tools Were Insufficient

- **osTicket's native web UI** is not accessible to AI assistants — it requires a browser and manual interaction.
- **osTicket's REST API** is raw HTTP — an AI assistant would need to construct raw HTTP requests, handle authentication, parse responses, and manage errors, all without any structured tool interface.
- **Generic MCP HTTP clients** (e.g., `mcp-server-fetch`) can make HTTP requests but lack domain-specific knowledge of osTicket's API structure, endpoint paths, authentication scheme (`X-API-Key` header), and response formats.
- **No existing MCP server for osTicket** existed at the time of creation — this was the first implementation bridging the MCP protocol to osTicket.

### What Triggered Development

The initial commit (`57c7817`, 2025-10-18) was "feat: Initial implementation of osTicket MCP Server" by Markus Michalski. The project was triggered by the emergence of the MCP protocol itself and the need for AI assistants to interact with helpdesk systems. The development was driven by:

- The release and adoption of the Model Context Protocol by Anthropic for Claude Code
- The practical need for developers using AI coding tools to manage support tickets without leaving their editor
- The availability of osTicket's REST API and the [API Endpoints Plugin](https://github.com/markus-michalski/osticket-plugins/tree/main/api-endpoints) which extended osTicket's native API surface

### Ecosystem Fit

```
JorahOne Ecosystem
├── claude-mcp-osticket (this repo) — MCP server for osTicket helpdesk
├── osticket-plugins (upstream) — Required companion plugins (API Endpoints, Subticket Manager)
└── Hermes Agent / Claude Code — MCP host that consumes this server
```

This repo is a **fork** of `markus-michalski/claude-mcp-osTicket` (upstream). The JorahOne fork (`OneByJorah/claude-mcp-osticket`) adds one commit on top of upstream: portfolio standardization (community files, issue templates, CodeQL, dependabot, security policy). The fork tracks upstream and has 89 total commits, with only 1 fork-specific commit.

The repo fits into the JorahOne ecosystem as a **tool adapter** — it enables AI agents (Hermes Agent, Claude Code) to interact with osTicket helpdesk instances, which is a common operational need in managed service and support workflows.

---

## Operational Classification

**Classification: PRODUCTION**

Evidence:
- **Semantic versioning**: 12 tagged releases from v1.0.0 through v2.2.2, following semver
- **CI/CD**: GitHub Actions CI workflow testing across Node.js 18/20/22 with type-check, lint, and build
- **CodeQL**: Weekly security analysis workflow enabled
- **Security posture**: Two dedicated security audit fix commits (v2.2.1: "implement all 20 security audit findings", v2.2.2: "comprehensive security audit fixes and code improvements")
- **Health check**: Runtime health check on startup (`apiClient.healthCheck()`)
- **Graceful shutdown**: SIGINT/SIGTERM handlers for clean MCP server shutdown
- **Log rotation**: Automatic log rotation at 10MB with cleanup of old rotated logs
- **Input validation**: Zod schemas with runtime validation on all tool inputs
- **Error handling**: Structured error class (`OsTicketApiError`) with status code matching, actionable error messages, and sanitized internal details
- **Retry logic**: Exponential backoff (2 retries) for transient HTTP errors (502/503/504)
- **Response size limits**: 25KB character limit on tool responses, 10MB max HTTP response size
- **Community readiness**: CODE_OF_CONDUCT.md, CONTRIBUTING.md, SECURITY.md, issue/PR templates, Dependabot
- **License**: MIT

---

## Key Architectural Decisions

1. **API-only architecture (v2.0.0 refactor)**: The system was refactored from a hybrid architecture (SSH tunnel + MySQL direct access) to a pure REST API client. This eliminated the need for SSH tunnels, database credentials, and direct MySQL access — simplifying deployment and improving security. The `examples/metadata-usage.ts` file is a stale artifact from the pre-refactor era, referencing classes (`MetadataService`, `MySQLTicketRepository`, `SSHTunnelPool`) that no longer exist.

2. **Stdio transport over HTTP**: MCP servers can use either stdio or HTTP transport. This server uses stdio, meaning it's launched as a child process by the MCP host (Claude Code). This is the standard pattern for local MCP servers and avoids the complexity of port management, TLS, and authentication between host and server.

3. **Wildcard API endpoint for ticket creation**: Uses `/api/wildcard/tickets.json` instead of a specific endpoint to support API keys configured with `0.0.0.0` IP address restrictions in osTicket.

4. **Status name-to-ID resolution with caching**: The API client resolves human-readable status names (e.g., "Closed") to numeric IDs by fetching and caching the status list from the API with a 5-minute TTL. Other entity types (department, staff, topic, SLA) only support numeric IDs — name lookup is not yet implemented.

5. **Defense-in-depth security**: Multiple layers of input validation — ticket number regex validation before URL construction, CRLF injection prevention in API keys, HTTPS enforcement (with `ALLOW_HTTP` escape hatch for development), response size limits, and sanitized error messages that avoid leaking internal hostnames/IPs.

6. **Content-Length header for Apache compatibility**: Explicitly sets `Content-Length` on POST/PATCH requests because Apache's `mod_proxy_fcgi` can truncate chunked-encoded bodies, causing `php://input` to be empty on the server.

7. **Logging to stderr + file**: Uses stderr for real-time logging (visible in MCP debug mode) and a rotating file at `~/.claude/mcp-servers/osticket/logs/server.log` for persistent logs. This avoids corrupting the JSON-RPC transport on stdout.

---

## Repository Structure

```
claude-mcp-osticket/
├── src/
│   ├── index.ts                          # Entry point: MCP server setup + 12 tool registrations
│   ├── constants.ts                      # Shared constants (limits, timeouts, server info)
│   ├── config/
│   │   └── Configuration.ts              # Env-based config with validation
│   ├── schemas/
│   │   └── index.ts                      # Zod validation schemas for all tool inputs
│   ├── infrastructure/
│   │   ├── http/
│   │   │   ├── OsTicketApiClient.ts      # HTTP client for osTicket REST API
│   │   │   └── types/
│   │   │       ├── ApiResponseTypes.ts   # TypeScript interfaces for API responses
│   │   │       └── SubticketTypes.ts     # TypeScript interfaces for subticket API
│   │   ├── errors/
│   │   │   └── OsTicketApiError.ts       # Custom error class with HTTP status code
│   │   └── logging/
│   │       └── Logger.ts                 # File-based logger with rotation
│   └── utils/
│       └── attachments.ts               # File attachment processing (read, encode, save)
├── examples/
│   └── metadata-usage.ts                # STALE — references removed v1.x architecture
├── .github/
│   ├── workflows/
│   │   ├── ci.yml                        # CI: type-check, lint, build across Node 18/20/22
│   │   └── codeql.yml                    # Weekly CodeQL security analysis
│   ├── dependabot.yml                    # Dependabot config (pip, npm, docker, github-actions)
│   ├── ISSUE_TEMPLATE/
│   │   ├── bug_report.md
│   │   └── feature_request.md
│   └── PULL_REQUEST_TEMPLATE.md
├── .env.example                          # Required env vars template
├── package.json                          # v2.2.2, Node 18+, MCP SDK, Zod
├── tsconfig.json                         # Strict TypeScript, ES2022, NodeNext
├── eslint.config.js                      # ESLint flat config (v10)
├── evaluation.xml                        # Manual QA evaluation template
├── VERSION.txt                           # 2.2.2
├── CHANGELOG.md                          # Full changelog (German)
├── README.md                             # Quick start + tool reference
├── CODE_OF_CONDUCT.md                    # Contributor Covenant v2.1
├── CONTRIBUTING.md                       # Development setup + conventions
├── SECURITY.md                           # Vulnerability reporting policy
└── LICENSE                               # MIT
```

---

## Notes

- **Dependabot ecosystem mismatch**: `dependabot.yml` configures `pip` and `docker` ecosystems, but this is a pure TypeScript/Node.js project with no Python files and no Dockerfile. These are template vestiges from the JorahOne portfolio standardization commit. Only `npm` and `github-actions` ecosystems are relevant.

- **Stale example file**: `examples/metadata-usage.ts` imports classes (`MetadataService`, `MySQLTicketRepository`, `DatabaseConnectionManager`, `SSHTunnelPool`) that were removed in the v2.0.0 API-only refactor. This file is non-functional and should be removed or updated.

- **No docs/ directory**: Documentation is hosted externally at `https://faq.markus-michalski.net/en/mcp/osticket`. The README explicitly defers to this external site.

- **No Dockerfile or compose files**: The server runs as a stdio-based MCP subprocess, not as a container. No containerization is provided.

- **No test directory or test files**: The only test artifact is `evaluation.xml`, a manual QA template with placeholder answers. There are no automated unit or integration tests.

- **Fork with upstream tracking**: The repo has two remotes — `origin` (OneByJorah fork) and `upstream` (markus-michalski original). Only 1 fork-specific commit exists (portfolio standardization). The initial commit of the fork is the upstream's first commit, not a fork-specific start.

- **Security audit history**: Two dedicated security fix commits exist — one implementing 20 audit findings (v2.2.1) and a second comprehensive audit (v2.2.2). This is a strong positive maturity signal.

- **Bug report template references Python/Docker**: The bug report template asks for "Python Version" and "Docker Version" — this is a template vestige from the portfolio standardization and doesn't match the TypeScript/Node.js nature of this project.
