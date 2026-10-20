# Backend Development Guidelines

> Best practices for backend development in this project.

---

## Overview

This directory contains guidelines for backend development. Fill in each file with your project's specific conventions.

---

## Guidelines Index

| Guide | Description | Status |
|-------|-------------|--------|
| [Directory Structure](./directory-structure.md) | Module organization and file layout | To fill |
| [Database Guidelines](./database-guidelines.md) | ORM patterns, queries, migrations | To fill |
| [Error Handling](./error-handling.md) | Error types, handling strategies | To fill |
| [Quality Guidelines](./quality-guidelines.md) | Code standards, forbidden patterns | To fill |
| [Logging Guidelines](./logging-guidelines.md) | Structured logging, log levels | To fill |
| [Codex Usage](./codex-usage.md) | Local app-server protocol, normalization, and display contract | Phase 2A |
| [88VIP Usage](./vip-usage.md) | 88API billing, Keychain credential, and balance normalization contract | Phase 3 |
| [DeepSeek Usage](./deepseek-usage.md) | Official native-currency balances, isolated Keychain credential, and refresh invalidation | Current |
| [Release Delivery](./release-delivery.md) | Universal preview signing, recoverable local installation, and GitHub artifact/source publication | Current |
| [Auto Update](./auto-update.md) | GitHub latest-release feed, digest + code-signature verification, staged install with rollback | Current |
| [Built-in Tasks](./builtin-tasks.md) | Local JSON transactions, tags, daily repeat, retry and schema compatibility | Current |

---

## How to Fill These Guidelines

For each guideline file:

1. Document your project's **actual conventions** (not ideals)
2. Include **code examples** from your codebase
3. List **forbidden patterns** and why
4. Add **common mistakes** your team has made

The goal is to help AI assistants and new team members understand how YOUR project works.

---

**Language**: All documentation should be written in **English**.
