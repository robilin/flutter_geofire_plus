CREATE TABLE IF NOT EXISTS geofire_locations (
    path VARCHAR(191) NOT NULL,
    location_key VARCHAR(191) NOT NULL,
    lat DOUBLE NOT NULL,
    lng DOUBLE NOT NULL,
    geom POINT NOT NULL SRID 4326,
    data JSON NOT NULL,
    updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
    PRIMARY KEY (path, location_key),
    SPATIAL INDEX geofire_locations_geom_idx (geom),
    INDEX geofire_locations_path_idx (path)
);