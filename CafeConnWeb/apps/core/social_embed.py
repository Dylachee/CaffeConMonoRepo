"""Social-post embed providers for the venue feed.

One module owns everything about turning a staff-pasted URL into markup the
guest page can render:

  * `detect_platform(url)`  — strict domain whitelist + platform detection;
  * `build_embed(platform, url)` — official embed markup, generated ONLY here
    (never from user input) so the DB can be trusted not to hold foreign HTML;
  * `EMBED_SCRIPTS`         — the official widget script per platform, loaded
    lazily by the guest page on the first open of the Feed tab.

Provider notes:
  * X/Twitter has a public oEmbed endpoint (publish.twitter.com) that needs no
    token — we call it with a short timeout and fall back to the standard
    blockquote if it is slow/down.
  * Instagram/Facebook oEmbed requires a Graph API token. With
    FACEBOOK_GRAPH_TOKEN in the env we use it; without it we generate the
    documented blockquote/div markup that the official embed.js/sdk.js scripts
    upgrade in the browser.
  * Threads only has the blockquote + embed.js form.

Every embed also gets a guest-side fallback card (rendered by menu.html) for
when the widget script is blocked or the network is down — this module only
guarantees the markup, not the third-party script.
"""

import json
import os
import re
import urllib.error
import urllib.parse
import urllib.request

from django.utils.html import format_html


class SocialEmbedError(ValueError):
    """Invalid social-post URL. `str(error)` is safe to show to a human."""


class Platform:
    """Wire values — must match SocialPost.Platform choices."""

    INSTAGRAM = "instagram"
    THREADS = "threads"
    TWITTER_X = "twitter_x"
    FACEBOOK = "facebook"


# Strict whitelist: hostname must equal one of these or be a subdomain of it.
# Anything else is rejected with a human-readable message — never stored.
PLATFORM_DOMAINS = {
    Platform.INSTAGRAM: ("instagram.com",),
    # threads.net is the historical domain, threads.com the current one.
    Platform.THREADS: ("threads.net", "threads.com"),
    Platform.TWITTER_X: ("x.com", "twitter.com"),
    Platform.FACEBOOK: ("facebook.com", "fb.watch"),
}

# Official widget scripts, loaded lazily by the guest page (never on the
# initial /menu/ render). The Facebook SDK also needs a #fb-root node, which
# menu.html creates before injecting the script.
EMBED_SCRIPTS = {
    Platform.INSTAGRAM: "https://www.instagram.com/embed.js",
    Platform.THREADS: "https://www.threads.net/embed.js",
    Platform.TWITTER_X: "https://platform.twitter.com/widgets.js",
    Platform.FACEBOOK: "https://connect.facebook.net/en_US/sdk.js#xfbml=1&version=v19.0",
}

_OEMBED_TIMEOUT_SECONDS = 6
_SCRIPT_TAG_RE = re.compile(r"<script\b[^>]*>.*?</script\s*>", re.IGNORECASE | re.DOTALL)


def _hostname(url: str) -> str:
    try:
        parts = urllib.parse.urlsplit(url)
    except ValueError:
        raise SocialEmbedError("That does not look like a valid link.")
    if parts.scheme not in ("http", "https"):
        raise SocialEmbedError("Only http(s) links are supported.")
    host = (parts.hostname or "").lower().rstrip(".")
    if not host:
        raise SocialEmbedError("That does not look like a valid link.")
    return host


def _matches(host: str, domain: str) -> bool:
    return host == domain or host.endswith("." + domain)


def detect_platform(url: str) -> tuple[str, str]:
    """Validate a staff-pasted URL and return (platform, normalized_url).

    Raises SocialEmbedError with a human-readable message for anything that
    is not a post link on a whitelisted social domain.
    """
    url = (url or "").strip()
    if not url:
        raise SocialEmbedError("Paste a link to a post first.")
    host = _hostname(url)

    platform = None
    for candidate, domains in PLATFORM_DOMAINS.items():
        if any(_matches(host, domain) for domain in domains):
            platform = candidate
            break
    if platform is None:
        allowed = ", ".join(sorted({d for ds in PLATFORM_DOMAINS.values() for d in ds}))
        raise SocialEmbedError(
            f"Links from {host} are not supported. Use a post link from: {allowed}."
        )

    parts = urllib.parse.urlsplit(url)
    # A bare profile/home link has nothing to embed; require a real path.
    # (facebook permalinks carry their id in the query string, so a query
    # also counts as "points at a post".)
    if parts.path.strip("/") == "" and not parts.query:
        raise SocialEmbedError("That link points at a profile or home page, not a post.")

    # Drop the fragment; keep the query (facebook permalink.php needs it).
    normalized = urllib.parse.urlunsplit(
        (parts.scheme, parts.netloc, parts.path, parts.query, "")
    )
    return platform, normalized


# --- providers ---------------------------------------------------------------


def _strip_scripts(html: str) -> str:
    """Remove <script> tags from provider oEmbed HTML — the guest page loads
    the official scripts itself, lazily and exactly once per platform."""
    return _SCRIPT_TAG_RE.sub("", html).strip()


def _fetch_oembed(endpoint: str, params: dict) -> str | None:
    """GET an oEmbed endpoint; return its `html` or None on any failure.
    Never raises: a slow provider must degrade to the blockquote markup,
    not break post creation."""
    url = f"{endpoint}?{urllib.parse.urlencode(params)}"
    request = urllib.request.Request(url, headers={"User-Agent": "CafeConnect/1.0"})
    try:
        with urllib.request.urlopen(request, timeout=_OEMBED_TIMEOUT_SECONDS) as response:
            payload = json.loads(response.read().decode("utf-8"))
    except (urllib.error.URLError, TimeoutError, ValueError, OSError):
        return None
    html = payload.get("html")
    return _strip_scripts(html) if isinstance(html, str) and html.strip() else None


def _twitter_embed(url: str) -> str:
    html = _fetch_oembed(
        "https://publish.twitter.com/oembed",
        {"url": url, "omit_script": "true", "dnt": "true", "hide_thread": "true"},
    )
    if html:
        return html
    return format_html(
        '<blockquote class="twitter-tweet" data-dnt="true"><a href="{}"></a></blockquote>',
        url,
    )


def _graph_oembed(url: str, kind: str) -> str | None:
    """Official Instagram/Facebook oEmbed via the Graph API. Only used when a
    token is configured (FACEBOOK_GRAPH_TOKEN); returns None otherwise."""
    token = os.getenv("FACEBOOK_GRAPH_TOKEN", "").strip()
    if not token:
        return None
    endpoint = f"https://graph.facebook.com/v19.0/{kind}"
    return _fetch_oembed(endpoint, {"url": url, "access_token": token, "omitscript": "true"})


def _instagram_embed(url: str) -> str:
    html = _graph_oembed(url, "instagram_oembed")
    if html:
        return html
    # Standard markup the official embed.js upgrades in the browser.
    permalink = url if url.endswith("/") else url + "/"
    return format_html(
        '<blockquote class="instagram-media" data-instgrm-permalink="{}" '
        'data-instgrm-version="14"><a href="{}"></a></blockquote>',
        permalink,
        permalink,
    )


def _facebook_embed(url: str) -> str:
    html = _graph_oembed(url, "oembed_post")
    if html:
        return html
    kind = "fb-video" if ("/videos/" in url or "fb.watch" in url or "/watch" in url) else "fb-post"
    return format_html('<div class="{}" data-href="{}"></div>', kind, url)


def _threads_embed(url: str) -> str:
    return format_html(
        '<blockquote class="text-post-media" data-text-post-permalink="{}" '
        'data-text-post-version="0"><a href="{}"></a></blockquote>',
        url,
        url,
    )


_PROVIDERS = {
    Platform.INSTAGRAM: _instagram_embed,
    Platform.THREADS: _threads_embed,
    Platform.TWITTER_X: _twitter_embed,
    Platform.FACEBOOK: _facebook_embed,
}


def build_embed(platform: str, url: str) -> str:
    """Official embed markup for a validated (platform, url) pair. The result
    is entirely generated by this module — user input only ever contributes
    the (validated, escaped) URL."""
    provider = _PROVIDERS.get(platform)
    if provider is None:  # pragma: no cover — detect_platform guards this
        raise SocialEmbedError("Unsupported platform.")
    return provider(url)


def domain_for_display(url: str) -> str:
    """Hostname without 'www.' — what the guest fallback card shows."""
    host = _hostname(url)
    return host[4:] if host.startswith("www.") else host
