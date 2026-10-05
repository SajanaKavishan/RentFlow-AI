# Maintenance coordination configuration

The existing Landlord/Admin actions run advisory analysis on demand. The tenant submission
and normal maintenance state transitions have no dependency on image/AI availability.

Configure private deployment environment values:

| Backend setting | Purpose |
| --- | --- |
| `AgentService__BaseUrl` | Reachable private Python service base URL |
| `AgentService__TimeoutSeconds` | Total maintenance analysis deadline, default 30 seconds |
| `AgentService__ServiceApiKey` | Secret matching Python `AGENT_SERVICE_API_KEY` |
| Existing `CloudflareR2` settings | Private object storage credentials/bucket; never forwarded to AI |

Python uses its existing `AI_PROVIDER`, `AI_MODEL`, and API-key configuration for text.
Optional `VISION_PROVIDER`, `VISION_MODEL`, `VISION_API_KEY` select its existing vision
adapter. Configure these privately; unsupported/unconfigured vision means text-only
maintenance analysis with photo limitations when photos were supplied. Restart both
services together for the additive internal request/execution-metadata contract.

The photo service repeats caller role/ownership checks before any storage access. It uses
`DownloadBytesAsync`, never signed/public URLs. JPEG/PNG/WEBP selection is restricted to
the current request and ordered by creation time then ID, up to five images.

Fixed safety bounds in `MaintenancePhotoEvidenceService`:

| Bound | Value |
| --- | --- |
| Source bytes per image | 10 MiB |
| Source dimension / pixel area | 8192 pixels per side / 20,000,000 pixels |
| Decoded frames | First frame only |
| Simultaneous backend decodes | 2 per process, one decoder worker per image |
| Image allocator pool / allocation limit | 32 MiB / 192 MiB |
| Primary analysis representation | JPEG quality 80, at most 1280 pixels per side |
| Bounded encoding retry | At most 960 pixels per side, JPEG quality 65 |
| Analysis bytes per image / aggregate | 512 KiB / 2 MiB |
| Approximate aggregate Base64 budget | 2.67 MiB plus bounded text JSON |
| Private retrieval + preparation phase | min(8 seconds, total deadline / 4) |

The decoded format must match declared MIME and actual pixels must decode. Orientation
is applied before copying pixels into a new image, which excludes EXIF/GPS/device/time,
XMP, IPTC, ICC and format metadata. Upload originals remain private and unchanged.
Python independently validates the normalized representation, so deployment proxy body
limits should allow at least 3 MiB for this internal route without logging request bodies.

Missing or unreadable photos are omitted with closed safe limitation codes. Remaining valid
photos continue; storage/optional vision failures can fall back to text. An exhausted total
deadline fails only the advisory workflow and propagates caller cancellation. Decoder CPU
operations use bounded work and cooperative checks, rather than unbounded parallel tasks.

Safe photo counts reuse the existing agent step `ValidationSummary`, with no migration.
The final recommendation JSON schema is unchanged. Never log or persist internal media
requests, object keys, original filenames, signed URLs, credentials or JWTs. Diagnostics
for photo retrieval/decoding log exception type only; maintenance vision diagnostics omit
provider exception messages. Service-key authorization still protects every Python
`/internal/*` endpoint before request parsing.

The backend adds only the cross-platform image-processing dependency
`SixLabors.ImageSharp` 3.1.12, separate from the existing AI provider adapters. Its package
license is [documented by the publisher](https://www.nuget.org/packages/SixLabors.ImageSharp/3.1.12).
Python reuses the project's existing Pillow and provider-neutral media infrastructure.

Photos remain advisory. Metadata stripping does not remove information visibly present
in pixels; the trusted vision instructions prohibit identity/location/contact extraction
and embedded instructions. No safety certification, repair guarantee, cost determination
or business action follows from photo interpretation.
