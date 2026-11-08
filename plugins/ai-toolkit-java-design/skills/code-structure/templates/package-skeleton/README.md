# Package skeleton
Copy these directories into `src/main/java/{{basePackagePath}}/` to seed
a new service with the core of the canonical package layout described in
this skill (§1). Copy **only the directories you are about to populate** —
the skill forbids empty packages. Each directory contains a `.gitkeep` so
the folder survives version control until its first class lands; delete the
`.gitkeep` then. Feature packages (`spi/`, `adapter/`, `validation/`,
`entity/`, `messaging/`, …) are created by the skill that needs them.
