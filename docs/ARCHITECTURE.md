# Cashbook Architecture V0.1

## Goal

Build a two-person, privacy-first shared cashbook with reliable Android payment capture and a small self-hosted cloud.

## System

```
Android A                       Android B
  |                               |
  | local transaction             | local transaction
  v                               v
BeeCount-derived client      BeeCount-derived client
  |                               |
  +------------ HTTPS/WSS --------+
                  |
                  v
          Cashbook Cloud
     (BeeCount Cloud upstream)
        FastAPI + Web UI
             SQLite
```

The cloud stores structured bookkeeping data only. Raw payment notifications, SMS bodies, screenshots and full OCR text are not synchronized.

## Android capture pipeline

```
Android Notification
        |
        v
Package Gatekeeper
        |
        +-- not allowlisted --> DROP
        |
        v
Payment Signal Filter
        |
        +-- not payment-like --> DROP
        |
        v
Local Parser
        |
        v
CandidateTransaction
        |
        v
Dedup + confidence
        |
        +-- high confidence --> confirm automatically
        |
        +-- uncertain -------> ask user
        |
        v
Transaction
        |
        v
Existing BeeCount sync engine
```

### Critical boundary

Raw notification text must remain inside the Android capture layer and must never be persisted or uploaded by default.

The cross-layer object is limited to:

- source
- amount
- direction
- merchant candidate
- timestamp
- optional local fingerprint
- confidence

## Server profile for 2C / 2G / 40G

V0.1 intentionally uses the upstream single-container BeeCount Cloud image and SQLite.

Expected components:

- BeeCount Cloud container
- reverse proxy or private overlay network
- one local data volume
- periodic encrypted/off-host backup later

No PostgreSQL, Redis, message queue, vector DB or external AI service is required for V0.1.

### Resource budget

- Cashbook Cloud: cap around 1.1 GB RAM / 1.5 CPU
- OS + Docker + reverse proxy: remaining memory
- SQLite + attachments: data volume under `deploy/data`
- Docker logs: rotation enabled

## Upstream policy

Cashbook uses BeeCount/BeeCount-Cloud as upstream foundations but keeps Cashbook-specific privacy and capture logic isolated.

Do not fork core synchronization behavior unless there is a concrete Cashbook requirement. Prefer a narrow patch surface so upstream updates remain mergeable.
