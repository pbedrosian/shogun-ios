# Database integration tests

Run `npm run backend:test:db` from the repository root with local Supabase running.
The pgTAP suite switches between authenticated/anonymous roles and four distinct
user identities, verifies positive/negative access and data integrity, then rolls
back the test data. Run `npm run backend:fixtures` and `npm run backend:test:api`
and `npm run backend:test:collection` to verify actual signed user sessions through
the REST gateway and collection RPCs as well.

See [schema, permissions, and recovery](../../../../docs/DATABASE.md).

`collection.test.sql` covers caller-RLS RPCs, anonymous execution denial, atomic
creation, stable-UUID retry behavior, diary bounds and persisted defaults. See
[collection synchronization](../../../../docs/COLLECTIONS.md) for conflict/offline behavior.
