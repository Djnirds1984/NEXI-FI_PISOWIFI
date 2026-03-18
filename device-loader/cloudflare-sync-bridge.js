// Cloudflare Worker: PisoWiFi DHCP Sync Bridge
// Tumatanggap ng raw dhcp.leases text galing sa Ruijie router at nagse-save sa Supabase

export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);

    // Only allow POST requests for syncing
    if (request.method !== 'POST') {
      return new Response('Method not allowed', { status: 405 });
    }

    // Kunin ang machine_id sa URL (e.g. ?machine_id=ruijie_001)
    const machineId = url.searchParams.get('machine_id');
    if (!machineId) {
      return new Response('Missing machine_id', { status: 400 });
    }

    try {
      // Basahin ang raw text galing sa /tmp/dhcp.leases ng router
      const rawLeases = await request.text();
      const lines = rawLeases.split('\n');
      
      const supabasePayload = [];
      const timestamp = new Date().toISOString();

      // I-parse ang raw text sa Cloudflare (Hindi sa Router para tipid RAM)
      for (const line of lines) {
        if (!line.trim()) continue;
        
        // Format: [expires] [mac] [ip] [hostname] [client_id]
        const parts = line.split(/\s+/);
        if (parts.length >= 4) {
          const mac = parts[1];
          const ip = parts[2];
          let name = parts[3];

          // Skip invalid macs
          if (!mac || mac === '*') continue;
          if (!name || name === '*') name = 'Unknown Device';

          supabasePayload.push({
            machine_id: machineId,
            mac_address: mac,
            device_name: name,
            ip_address: ip,
            is_connected: true,
            last_seen: timestamp
          });
        }
      }

      // Kung walang devices, wag na ituloy
      if (supabasePayload.length === 0) {
        return new Response('No devices to sync', { status: 200 });
      }

      // I-send ng isahan (Bulk Insert/Upsert) sa Supabase
      const SUPABASE_URL = "https://fuiabtdflbodglfexvln.supabase.co/rest/v1/wifi_devices";
      const SUPABASE_KEY = "eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6ImZ1aWFidGRmbGJvZGdsZmV4dmxuIiwicm9sZSI6ImFub24iLCJpYXQiOjE3NjkxNTAyMDAsImV4cCI6MjA4NDcyNjIwMH0.kbvAhEBKHLaByS9d9GRHbvuPikHvGjkdTaGHuubYazo";

      const supabaseResponse = await fetch(SUPABASE_URL, {
        method: 'POST',
        headers: {
          'apikey': SUPABASE_KEY,
          'Authorization': `Bearer ${SUPABASE_KEY}`,
          'Content-Type': 'application/json',
          'Prefer': 'resolution=merge-duplicates' // UPSERT mode
        },
        body: JSON.stringify(supabasePayload)
      });

      if (!supabaseResponse.ok) {
        const error = await supabaseResponse.text();
        console.error('Supabase Error:', error);
        return new Response('Failed to sync to database', { status: 500 });
      }

      return new Response(`Successfully synced ${supabasePayload.length} devices`, { status: 200 });

    } catch (err) {
      console.error('Worker Error:', err);
      return new Response('Internal Server Error', { status: 500 });
    }
  }
};
