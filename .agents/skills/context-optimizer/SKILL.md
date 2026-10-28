---
name: context-optimizer
description: Reduce redundant file reads, tool output, and prompt context. Use during large investigations, lengthy coding tasks, and context-heavy sessions.
---

# Context Optimizer

Goal: Reduce tokens without sacrificing correctness.

## Rules

- Prefer filenames and symbols before file contents.
- Read narrow code ranges before complete modules.
- Avoid repeatedly reading unchanged content.
- Summarize large logs; preserve actionable errors.
- Do not print full datasets unnecessarily.
- Do not expand dependencies without a concrete reason.
- Keep responses concise but technically complete.

## Before complex tasks

Identify:

1. Required information
2. Relevant files
3. Minimal set of tool calls
4. Validation needed

## During complex tasks

- Reuse verified findings.
- Track unresolved questions.
- Keep intermediate output small.
- Preserve critical evidence and error details.

## Before context compaction

Save durable decisions and remaining work to
project memory without copying unnecessary details.

## Completion

Report the outcome concisely.
Never claim token savings without measurement.
