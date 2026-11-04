Skills catalogue: ~/.ai-toolkit/plugins/<plugin>/skills/<skill-name>/SKILL.md  (plugin = ai-toolkit-<phase> or ai-toolkit-<lang>-<phase>; map: ~/.ai-toolkit/docs/REGISTRY.md)
Use #file to load a skill when relevant, e.g. #file ~/.ai-toolkit/plugins/ai-toolkit-java-build/skills/exception-handling/SKILL.md
Standards apply only if the skill is read first. Before writing code, #file the matching skill:
any class → code-structure + testable-code-principles; tests → unit-tests; errors → exception-handling;
validation → input-validation; endpoint → api-design + permissions; external call → external-client;
config/async/cache → spring-boot-conventions; commit → git-commit-conventions. (Python: python-*, React Native: react-native-*.)
Full map: ~/.ai-toolkit/docs/INDEX_BY_USE_CASE.md. Keep patterns minimal (docs/PATTERN_SELECTION_GUIDE.md).
Never commit until asked; before saying done, apply completion-gate (plugins/ai-toolkit-quality).
