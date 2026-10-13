# ADR 0002 : Fastify pour l'API HTTP

## Décision

Le serveur REST utilise Fastify avec TypeScript strict.

## Contexte

La phase serveur doit proposer une API REST validée, un rate limiting et une
base de tests d'intégration, tout en restant légère pour un déploiement
auto-hébergé.

## Justification

Fastify fournit un pipeline de plugins explicite, une validation de requêtes
compatible avec les schémas et de bonnes performances avec une empreinte
réduite ; il s'intègre donc bien avec Zod, PostgreSQL et Vitest sans imposer
une architecture applicative lourde.
