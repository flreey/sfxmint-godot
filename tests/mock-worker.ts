// Local-only controlled service. No provider, billing or production calls.
// Real client-status authentication/allowance is tested against SQLite by
// scripts/test-client-status.mjs; this Worker exercises the native editor client.
const ORIGIN = "http://127.0.0.1:8797";
const TEST_KEY = "sfx_live_" + "1".repeat(40);
const OTHER_KEY = "sfx_live_" + "2".repeat(40);
const orders = new Map<string, { id: string; prompt: string; status: string; owner: string; created_at: number; polls: number; kind: string; favorites: Record<number,boolean>; supplied: boolean }>();
let serial = 0;
let control = { post_status: 201, get_status: 200, file_status: 200, partial: false, delay_ms: 0, invalid_wav: false };
function wav(seconds = 1): Uint8Array {
  const samples = Math.round(22050 * seconds), bytes = new Uint8Array(44 + samples * 2), view = new DataView(bytes.buffer);
  const str = (at: number, s: string) => [...s].forEach((c, i) => bytes[at + i] = c.charCodeAt(0));
  str(0, "RIFF"); view.setUint32(4, bytes.length - 8, true); str(8, "WAVE"); str(12, "fmt ");
  view.setUint32(16, 16, true); view.setUint16(20, 1, true); view.setUint16(22, 1, true);
  view.setUint32(24, 22050, true); view.setUint32(28, 44100, true); view.setUint16(32, 2, true); view.setUint16(34, 16, true);
  str(36, "data"); view.setUint32(40, samples * 2, true);
  for (let i = 0; i < samples; i++) view.setInt16(44 + i * 2, Math.sin(i * 2 * Math.PI * 660 / 22050) * 5000 * Math.exp(-i / 3500), true);
  return bytes;
}
const ogg = Uint8Array.from(atob("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"), c => c.charCodeAt(0));
const bytes = wav();
const digest = async () => [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(n => n.toString(16).padStart(2, "0")).join("");
const json = (data: unknown, status = 200) => Response.json(data, { status, headers: { "Cache-Control": "no-store" } });
export default {
  async fetch(req: Request) {
    const u = new URL(req.url), path = u.pathname;
    const key = (req.headers.get("Authorization") ?? "").replace("Bearer ", "");
    const owner = key === TEST_KEY ? "test-account-a" : key === OTHER_KEY ? "test-account-b" : "";
    if (path === "/__control" && req.method === "POST") {
      control = { ...control, ...await req.json() as object };
      return json(control);
    }
    if (path === "/__reset" && req.method === "POST") {
      orders.clear(); control = { post_status: 201, get_status: 200, file_status: 200, partial: false, delay_ms: 0, invalid_wav: false };
      return json({ ok: true });
    }
    const sound = { slug: "test-coin", title: "Fixture coin pickup", description: "Local test tone — not a catalog sound", duration_ms: 1000, loopable: false, license: "CC0-1.0", wav_url: ORIGIN + "/audio.wav", mp3_url: ORIGIN + "/audio.wav", format_metadata: { wav: { sha256: await digest() } } };
    if (path === "/api/v1/search") {
      if (key) return json({ error: "search_must_not_send_key" }, 400);
      return json({ candidates: u.searchParams.get("q") === "none" ? [] : [sound], closest: [], near_matches: [], constraints: {}, library_fit: "full" });
    }
    if (path === "/api/v1/sounds/test-coin") return json(sound);
    if (path === "/audio.wav") {
      const delay = Math.min(2000, Number(u.searchParams.get("delay_ms") ?? 0));
      if (delay > 0) await new Promise(resolve => setTimeout(resolve, delay));
      if (key) return json({ error: "download_must_not_send_key" }, 400);
      if (control.file_status !== 200) return json({ error: "expired_link" }, control.file_status);
      const expires = Number(u.searchParams.get("expires") ?? 0);
      if (expires && expires < Date.now()) return json({ error: "expired_link" }, 403);
      const invalid = bytes.slice(); invalid[20] = 255; invalid[21] = 255;
      return new Response(control.invalid_wav ? invalid : u.searchParams.get("format") === "ogg" ? ogg : wav(Number(u.searchParams.get("seconds") ?? 1)), { headers: { "Content-Type": "audio/wav" } });
    }
    if (path.startsWith("/api/v1/recipes/")) return json({slug:"test-coin", recipe:"A coin pickup", variation:true, duration_s:1});
    if (!owner) return json({ error: "invalid_api_key" }, 401);
    if (path === "/api/v1/uploads" && req.method === "POST") {
      if (u.searchParams.get("rights") !== "1") return json({error:"rights_required"},400);
      const audio = new Uint8Array(await req.arrayBuffer());
      if (audio.length < 44) return json({error:"invalid_audio"},400);
      return json({upload_id:"upload-fixture", duration_s:1, expires_at:Date.now()+86400000},201);
    }
    if (path === "/api/v1/ambience/details") return json({details:[{label:"birds"},{label:"wind"}]});
    if (path === "/api/v1/client-status") return json({ version: 2, account_id: owner, key: { masked: "sfx_live_••••" + key.slice(-4) }, allowance: { limit: 3, used: orders.size, left: Math.max(0, 3 - orders.size), resets_at: null, plan: null, credits: 9 }, generation_enabled: true, credits: { balance: 9 }, capabilities: { kinds: ["sound", "ambience", "music"], durations: [0.2, 0.5, 1, 2, 3, 5, 8, 10], variations: [1, 2, 4], formats: ["wav", "ogg"] } });
    if (path === "/api/v1/orders" && req.method === "POST") {
      if (control.post_status !== 201) return json({ error: control.post_status === 402 ? "payment_required" : control.post_status === 429 ? "too_many_active_orders" : "unavailable" }, control.post_status);
      const input = await req.json() as { prompt: string; kind?: string; from_audio?: {upload?: string} };
      const id = "ord_fixture_" + (++serial);
      orders.set(id, { id, prompt: input.prompt, status: "generating", owner, created_at: Date.now(), polls: 0, kind: input.kind ?? "sound", favorites: {}, supplied: !!input.from_audio?.upload });
      if (control.delay_ms) await new Promise(r => setTimeout(r, control.delay_ms));
      return json({ order_id: id, free: { limit: 3, used: orders.size, left: Math.max(0, 3 - orders.size), resets_at: null, plan: null } }, 201);
    }
    if (path === "/api/v1/orders") return json({ orders: [...orders.values()].filter(o => o.owner === owner).reverse() });
    if (path.startsWith("/api/v1/orders/")) {
      if (control.get_status !== 200) return json({ error: "temporary_failure" }, control.get_status);
      const order = orders.get(path.split("/")[4]);
      if (!order || order.owner !== owner) return json({ error: "not_found" }, 404);
      if (req.method === "PATCH" && path.includes("/items/")) {
        const index = Number(path.split("/").pop());
        const input = await req.json() as {favorite: boolean};
        order.favorites[index] = input.favorite;
        return json(input);
      }
      order.polls++;
      if (order.polls > 1) order.status = "delivered";
      return json({ order, files: [1, 2, 3, 4].map(index => ({ index, favorite: order.favorites[index] ?? false, status: order.status === "generating" ? "working" : control.partial && index === 4 ? "failed" : "ready", duration_s: order.kind === "sound" ? 1 : 30, sha256: order.kind === "sound" ? digestCache : "", ogg: true, loop_cut: order.kind === "sound" ? null : {seconds: 8}, loop_url: order.kind === "sound" ? null : `/audio.wav?seconds=8`, details: order.kind === "ambience" ? {seconds: 12, labels: ["birds", "wind"]} : null, details_play_url: order.kind === "ambience" ? "/audio.wav?seconds=12" : null, details_url: order.kind === "ambience" ? "/audio.wav?seconds=12" : null, filename: `take-${index}.wav`, url: `/audio.wav?seconds=${order.kind === "sound" ? 1 : 30}&expires=${Date.now() + 3000}`, preview_url: `/audio.wav?seconds=${order.kind === "sound" ? 1 : 30}&expires=${Date.now() + 3000}` })), license_id: order.supplied ? "LicenseRef-User-Supplied" : "CC0-1.0", license: order.supplied ? "User-supplied source; no CC0 dedication." : "CC0-1.0 — local test fixture" });
    }
    return json({ error: "not_found" }, 404);
  },
};
let digestCache = "";
digest().then(value => digestCache = value);
