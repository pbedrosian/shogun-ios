# Database integration tests

Run `npm run backend:test:db` from the repository root with local Supabase running.
The pgTAP suite switches between authenticated/anonymous roles and four distinct
user identities, verifies positive/negative access and data integrity, then rolls
back the test data. Run `npm run backend:fixtures` and `npm run backend:test:api`
to verify actual signed user sessions through the REST gateway as well.

See [schema, permissions, and recovery](../../../../docs/DATABASE.md).
