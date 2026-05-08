// Supabase Edge Function starter (TypeScript)
// This file demonstrates contract shape only.

import { serve } from "https://deno.land/std@0.224.0/http/server.ts";

serve(async (req: Request) => {
    const url = new URL(req.url);
    const pathname = url.pathname;

    if (req.method === "POST" && pathname.endsWith("/initialize")) {
        return json({ ok: true });
    }

    if (req.method === "POST" && pathname.endsWith("/set-location")) {
        // Persist path, key(id), lat, lng, data to your table.
        return json({ ok: true });
    }

    if (req.method === "POST" && pathname.endsWith("/remove-location")) {
        // Delete key row for path.
        return json({ ok: true });
    }

    if (req.method === "GET" && pathname.endsWith("/get-location")) {
        // Return one location object.
        return json({ lat: -1.286389, lng: 36.817223, data: {} });
    }

    if (req.method === "GET" && pathname.endsWith("/query")) {
        // Return array rows: { key, latitude, longitude, data }
        // Implement geospatial radius query using PostGIS ST_DWithin.
        return json([
            {
                key: "driver_demo_001",
                latitude: -1.286389,
                longitude: 36.817223,
                data: {
                    vehicleType: "bike",
                    region: "nairobi",
                    isVerified: true,
                    rating: 4.8,
                    activeTrips: 0,
                    priority: 2,
                },
            },
        ]);
    }

    return new Response("Not found", { status: 404 });
});

function json(value: unknown, status = 200): Response {
    return new Response(JSON.stringify(value), {
        status,
        headers: { "content-type": "application/json" },
    });
}
