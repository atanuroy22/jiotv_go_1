#!/usr/bin/env python3
"""Extract render.m3u8 URLs from JioTV Go for restreaming."""

import requests
import sys
import urllib.parse

JIOGO_URL = "http://localhost:5001"

def get_render_url(channel_id, quality="auto"):
    """
    GET /live/:id returns a 302 redirect to /render.m3u8?auth=...&channel_key_id=...
    This is the proxied M3U8 URL you can use in any HLS player or restreaming software.
    """
    if quality and quality != "auto":
        url = f"{JIOGO_URL}/live/{quality}/{channel_id}.m3u8"
    else:
        url = f"{JIOGO_URL}/live/{channel_id}.m3u8"

    resp = requests.get(url, allow_redirects=False)
    if resp.status_code == 302:
        location = resp.headers["Location"]
        # Make absolute
        if location.startswith("/"):
            location = f"{JIOGO_URL}{location}"
        return location
    else:
        # Some endpoints may return directly
        return url

def generate_m3u_playlist(output_file="jiotv_restream.m3u"):
    """Fetch full M3U playlist from JioTV Go."""
    resp = requests.get(f"{JIOGO_URL}/channels?type=m3u")
    if resp.status_code == 200:
        with open(output_file, "wb") as f:
            f.write(resp.content)
        print(f"Playlist saved: {output_file}")
    else:
        print(f"Failed: {resp.status_code}")

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage:")
        print(f"  python {sys.argv[0]} <channel_id> [quality]")
        print(f"  python {sys.argv[0]} --playlist")
        print(f"\nExamples:")
        print(f"  python {sys.argv[0]} 182")
        print(f"  python {sys.argv[0]} 182 high")
        print(f"  python {sys.argv[0]} --playlist")
        print(f"\nSet JIOGO_URL env var to change server (default: http://localhost:5001)")
        sys.exit(1)

    global JIOGO_URL
    import os
    JIOGO_URL = os.environ.get("JIOGO_URL", JIOGO_URL)

    if sys.argv[1] == "--playlist":
        generate_m3u_playlist()
    else:
        channel_id = sys.argv[1]
        quality = sys.argv[2] if len(sys.argv) > 2 else "auto"
        url = get_render_url(channel_id, quality)
        if url:
            print(url)
        else:
            print("Failed to get render URL", file=sys.stderr)
            sys.exit(1)
