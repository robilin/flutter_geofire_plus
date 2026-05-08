# Postgres Go starter

Requirements:

1. Go 1.22+
2. PostgreSQL + PostGIS
3. DATABASE_URL environment variable

Setup:

1. Run sql/schema.sql in your database
2. go mod tidy
3. go run .

Adapter setup in Flutter:

Geofire.configureBackend(
  PostgresGeofireBackend(
    apiBaseUrl: "https://your-api.example.com",
  ),
);

This server implements:

- POST /initialize
- POST /set-location
- POST /remove-location
- GET /get-location
- GET /query
