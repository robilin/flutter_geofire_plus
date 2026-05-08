package main

import (
	"database/sql"
	"encoding/json"
	"log"
	"net/http"
	"os"
	"strconv"

	_ "github.com/lib/pq"
)

type setLocationRequest struct {
	Path string                 `json:"path"`
	ID   string                 `json:"id"`
	Lat  float64                `json:"lat"`
	Lng  float64                `json:"lng"`
	Data map[string]interface{} `json:"data"`
}

type initRequest struct {
	Path string `json:"path"`
}

type removeRequest struct {
	Path string `json:"path"`
	ID   string `json:"id"`
}

type queryRow struct {
	Key       string                 `json:"key"`
	Latitude  float64                `json:"latitude"`
	Longitude float64                `json:"longitude"`
	Data      map[string]interface{} `json:"data,omitempty"`
}

func main() {
	dsn := os.Getenv("DATABASE_URL")
	if dsn == "" {
		log.Fatal("DATABASE_URL is required")
	}

	db, err := sql.Open("postgres", dsn)
	if err != nil {
		log.Fatal(err)
	}
	defer db.Close()

	mux := http.NewServeMux()

	mux.HandleFunc("/initialize", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		jsonResponse(w, http.StatusOK, map[string]any{"ok": true})
	})

	mux.HandleFunc("/set-location", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		var req setLocationRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "invalid json", http.StatusBadRequest)
			return
		}
		if req.Path == "" || req.ID == "" {
			http.Error(w, "path and id are required", http.StatusBadRequest)
			return
		}

		dataBytes, _ := json.Marshal(req.Data)
		_, err := db.Exec(
			`INSERT INTO geofire_locations(path, key, lat, lng, geom, data, updated_at)
			 VALUES($1, $2, $3, $4, ST_SetSRID(ST_MakePoint($4, $3), 4326)::geography, $5::jsonb, NOW())
			 ON CONFLICT(path, key)
			 DO UPDATE SET
				lat = EXCLUDED.lat,
				lng = EXCLUDED.lng,
				geom = EXCLUDED.geom,
				data = EXCLUDED.data,
				updated_at = NOW()`,
			req.Path, req.ID, req.Lat, req.Lng, string(dataBytes),
		)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		jsonResponse(w, http.StatusOK, map[string]any{"ok": true})
	})

	mux.HandleFunc("/remove-location", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodPost {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		var req removeRequest
		if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
			http.Error(w, "invalid json", http.StatusBadRequest)
			return
		}
		if req.Path == "" || req.ID == "" {
			http.Error(w, "path and id are required", http.StatusBadRequest)
			return
		}
		if _, err := db.Exec(`DELETE FROM geofire_locations WHERE path=$1 AND key=$2`, req.Path, req.ID); err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		jsonResponse(w, http.StatusOK, map[string]any{"ok": true})
	})

	mux.HandleFunc("/get-location", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}
		path := r.URL.Query().Get("path")
		id := r.URL.Query().Get("id")
		if path == "" || id == "" {
			http.Error(w, "path and id are required", http.StatusBadRequest)
			return
		}

		var lat, lng float64
		var dataBytes []byte
		err := db.QueryRow(
			`SELECT lat, lng, data FROM geofire_locations WHERE path=$1 AND key=$2 LIMIT 1`,
			path, id,
		).Scan(&lat, &lng, &dataBytes)
		if err == sql.ErrNoRows {
			jsonResponse(w, http.StatusOK, map[string]any{"error": "No location found"})
			return
		}
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}

		var data map[string]any
		_ = json.Unmarshal(dataBytes, &data)
		jsonResponse(w, http.StatusOK, map[string]any{"lat": lat, "lng": lng, "data": data})
	})

	mux.HandleFunc("/query", func(w http.ResponseWriter, r *http.Request) {
		if r.Method != http.MethodGet {
			http.Error(w, "method not allowed", http.StatusMethodNotAllowed)
			return
		}

		path := r.URL.Query().Get("path")
		latStr := r.URL.Query().Get("lat")
		lngStr := r.URL.Query().Get("lng")
		radiusStr := r.URL.Query().Get("radius")
		includeData := r.URL.Query().Get("includeData") == "true"

		lat, err := strconv.ParseFloat(latStr, 64)
		if err != nil {
			http.Error(w, "invalid lat", http.StatusBadRequest)
			return
		}
		lng, err := strconv.ParseFloat(lngStr, 64)
		if err != nil {
			http.Error(w, "invalid lng", http.StatusBadRequest)
			return
		}
		radiusKm, err := strconv.ParseFloat(radiusStr, 64)
		if err != nil {
			http.Error(w, "invalid radius", http.StatusBadRequest)
			return
		}

		rows, err := db.Query(
			`SELECT key, lat, lng, data
			 FROM geofire_locations
			 WHERE path = $1
			   AND ST_DWithin(
				 geom,
				 ST_SetSRID(ST_MakePoint($2, $3), 4326)::geography,
				 $4
			   )`,
			path, lng, lat, radiusKm*1000,
		)
		if err != nil {
			http.Error(w, err.Error(), http.StatusInternalServerError)
			return
		}
		defer rows.Close()

		result := make([]queryRow, 0)
		for rows.Next() {
			var row queryRow
			var dataBytes []byte
			if err := rows.Scan(&row.Key, &row.Latitude, &row.Longitude, &dataBytes); err != nil {
				http.Error(w, err.Error(), http.StatusInternalServerError)
				return
			}
			if includeData {
				_ = json.Unmarshal(dataBytes, &row.Data)
			}
			result = append(result, row)
		}

		jsonResponse(w, http.StatusOK, result)
	})

	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}
	log.Printf("geofire-postgres-starter listening on :%s", port)
	log.Fatal(http.ListenAndServe(":"+port, mux))
}

func jsonResponse(w http.ResponseWriter, status int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(payload)
}
