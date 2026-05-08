# Supabase starter

Use this as an Edge Function starter. Persist locations in a table such as public.driver_locations with columns:

- path text
- key text
- lat double precision
- lng double precision
- geom geography(Point, 4326)
- data jsonb
- updated_at timestamptz

Recommended indexes:

- btree (path)
- btree (key)
- gist (geom)

Function routes should support:

- POST /initialize
- POST /set-location
- POST /remove-location
- GET /get-location
- GET /query

Use Geofire adapter:

Geofire.configureBackend(
  SupabaseGeofireBackend(
    edgeFunctionBaseUrl: "https://<project>.functions.supabase.co/geofire",
    anonKey: "<anon-key>",
  ),
);
