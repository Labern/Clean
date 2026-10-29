# paradoxica.uk — ★★★★★ × PARADOX company site

`site/` is the web root, mirrored 1:1 into `htdocs` on Fasthosts (Grow Web Hosting, Linux).
Plain HTML/SVG, no build. Fonts: Graphik + Canela only (CSS expects `site/fonts/*.woff2`,
falls back to Helvetica Neue until they're added).

## "upload" = ship to production, now
When the user says **upload**, do it, don't ask:
1. **On the Mac** (`ssh paradoxica` works): run `paradoxica/bin/upload`. Instant; it
   checks `paradoxica.uk/deploy.txt` afterwards.
2. **Cloud / phone** (no SSH from the container): commit `paradoxica/site` changes and
   push. `.github/workflows/paradoxica-deploy.yml` uploads over SFTP on any push touching
   `paradoxica/site/**` (any branch) and fails unless `deploy.txt` on the live site
   matches the build. Then curl `http(s)://paradoxica.uk/deploy.txt` to confirm.

## Access
- SSH/SFTP: user `csh3485222`, host `ssh.paradoxica.uk` (77.68.64.22), port 22; SFTP
  host `sftp.paradoxica.uk` (77.68.64.36). Web folder `htdocs`.
- Mac: `paradoxica/bin/setup` once → then `ssh paradoxica` is the shell.
- Password lives only in Fasthosts and the repo secret `FASTHOSTS_PASSWORD`.
  **Never ask for it in chat.**

## Identity
- Company: PARADOXICA Ltd., England and Wales, no. 17145296. Director: Labern.
- Email: londarolichin@icloud.com is the same person as labern@paradoxica.uk.
  Planned/possible addresses: l@paradoxica.uk (primary, labern@ forwards in),
  paradoxica@paradoxica.co.uk, l@paradoxica.co.uk. The site's only address is the
  `mailto:l@paradoxica.uk` on cats/ — update it if the primary changes.
- Domains: paradoxica.uk (main); paradoxica.co.uk → forward to https://paradoxica.uk.

## Open
- SSL certificate was "Awaiting Verification".
- paradoxica.co.uk web forwarding; l@ mailbox; Graphik/Canela woff2 files.
- Later: Slow Down for Cats on its own domain (likely slowdownforcats.org).
