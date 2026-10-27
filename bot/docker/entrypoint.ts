// Point d'entrée de l'image : convertit les secrets Docker en variables d'environnement.
// Pour chaque variable XXX_FILE=/run/secrets/..., on lit le fichier et on définit XXX
// (sauf si XXX est déjà défini), puis on démarre le bot sans modifier son code.
import { readFileSync } from "node:fs";

for (const [key, path] of Object.entries(process.env)) {
  if (!key.endsWith("_FILE") || !path) continue;
  const name = key.slice(0, -"_FILE".length);
  if (!process.env[name]) {
    process.env[name] = readFileSync(path, "utf8").trim();
  }
}

await import("./src/index.ts");
