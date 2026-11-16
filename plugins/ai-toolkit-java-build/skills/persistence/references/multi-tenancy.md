# Persistence Skill — Multi-tenancy

Part of the [`persistence`](../SKILL.md) skill. Headings are stable; other skills cite them.

## 3a. Multi-tenancy

When a service must manage data for multiple tenants (e.g., different organizations or customers), choose one of the following patterns:

1. **Discriminator Column (Shared Schema)**:
   - Add a `tenant_id` column to every table.
   - Mark it with Hibernate 6 `@TenantId` and register a `CurrentTenantIdentifierResolver`
     that reads the tenant from the request (via `permission/`). Hibernate then adds the
     tenant to every entity query **including `findById` / `getReferenceById`** and sets it on insert.
   - Do **not** rely on Hibernate `@Filter` alone: filters do not apply to `find` by id,
     `getReferenceById`, native queries or bulk updates, so tenants' data leaks.
   - Native and bulk queries still bypass `@TenantId`: add `tenant_id` to them by hand, or
     enforce isolation in the database with Postgres row-level security (RLS).
   - Add a test that tenant A's `findById` on tenant B's id returns empty.
   - **Pro**: Simple, low infra cost. **Con**: Risk of data leakage if filters are bypassed.

2. **Separate Schema (per tenant)**:
   - Every tenant has their own Postgres schema.
   - Use a `MultiTenantConnectionProvider` to switch schemas based on a tenant identifier in the request.
   - **Pro**: Stronger isolation. **Con**: Harder to run migrations across all schemas (Flyway needs a loop).

3. **Separate Database**:
   - Every tenant has their own DB instance.
   - **Pro**: Maximum isolation, no noisy neighbor. **Con**: Highest cost and complexity.

**Recommendation**: Start with **Discriminator Column** unless strict regulatory requirements demand otherwise.
