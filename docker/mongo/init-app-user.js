// Exécuté une seule fois par l'image mongo, au premier démarrage (dossier de données vide).
// Crée l'utilisateur applicatif de Stoat avec des droits limités à la base "revolt" :
// les services n'utilisent jamais le compte root.
db.getSiblingDB("revolt").createUser({
  user: process.env.MONGO_APP_USER,
  pwd: process.env.MONGO_APP_PASSWORD,
  roles: [
    { role: "readWrite", db: "revolt" },
    { role: "dbAdmin", db: "revolt" },
  ],
});
