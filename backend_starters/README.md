# Geofire backend starters

These starter templates implement the REST contract used by RestGeofireBackend and its typed wrappers:

- POST /initialize
- POST /set-location
- POST /remove-location
- GET /get-location
- GET /query

Available templates:

1. supabase/ (Edge Function style)
2. postgres-go/ (Go + net/http + PostGIS)
3. mysql-go/ (Go + net/http + MySQL spatial)

These are starter references, not production-ready deployments.

Production checklist:

1. Add authentication and tenancy checks.
2. Add rate limits and request validation.
3. Add pagination/windowing for large radius queries.
4. Add indexes and query plans for your expected density.
5. Add monitoring and retry logic.
