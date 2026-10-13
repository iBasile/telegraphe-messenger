# Contrat Protobuf partagé

`telegraphe.proto` est l'unique source du protocole binaire WebSocket.

## Génération

Depuis `server/` :

```sh
npm run proto:generate
```

La commande génère les types TypeScript utilisés par la gateway dans
`server/src/generated/telegraphe.ts`. Elle vérifie aussi que `protoc` et
`protoc-gen-ts_proto` sont disponibles.

Les types Swift sont générés avec `swift-protobuf` :

```sh
./scripts/generate-swift.sh
```

La CI exécute `npm run proto:check` afin d'empêcher une divergence entre le
contrat et les types TypeScript versionnés.
