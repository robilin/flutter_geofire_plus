CREATE EXTENSION IF NOT EXISTS postgis;

CREATE TABLE IF NOT EXISTS geofire_locations (
  path TEXT NOT NULL,
  key TEXT NOT NULL,
  lat DOUBLE PRECISION NOT NULL,
  lng DOUBLE PRECISION NOT NULL,
  geom GEOGRAPHY(POINT, 4326) NOT NULL,
  data JSONB NOT NULL DEFAULT '{}'::jsonb,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  PRIMARY KEY (path, key)
);

CREATE INDEX IF NOT EXISTS geofire_locations_path_idx ON geofire_locations (path);

CREATE INDEX IF NOT EXISTS geofire_locations_geom_idx ON geofire_locations USING GIST (geom);