# CVExcel

A small, self-contained PowerShell utility that lets an analyst **pick a product** and **date range** from a simple GUI, queries the **NVD v2 CVE API**, and exports a **timestamped CSV** of matching vulnerabilities.

- **Inputs**: `products.txt` (one product or CPE per line) + chosen dates
- **Output**: `./out/<Product>_<yyyyMMdd_HHmmss>.csv`
- **No paid dependencies**. Works on Windows PowerShell 5.1+ or PowerShell 7+

---

## Features

- **GUI** (WPF): dropdown for products + two calendar pickers for start/end dates
- **Product filters**:
  - If an entry starts with `cpe:2.3:` → uses `cpeName=<CPE>` for precise matching
  - Otherwise → uses `keywordSearch=<text>` for broad matching
- **Paging**: fetches all results from NVD (handles thousands)
- **Flattened export**: CVE metadata, CVSS score + derived severity, references, and affected CPEs (vendor/product/version)
- **Safe filenames**: cleans product name for filesystem compatibility

---

## Requirements

- Windows PowerShell **5.1+** _or_ PowerShell **7+**
- Internet egress to `services.nvd.nist.gov`
- Optional: free **NVD API key** (raises rate limits)

---

## Quick Start

1. **Clone** the repo and open a PowerShell prompt in the project folder.
2. Create a `products.txt` file next to the script:

   ```text
   # Examples (one per line)
   microsoft edge
   cpe:2.3:a:microsoft:edge:*:*:*:*:*:*:*:*
   adobe acrobat
   cpe:2.3:o:cisco:ios:*:*:*:*:*:*:*:*
   ```
3. (Optional) Set your NVD API key:

   ```powershell
   setx NVD_API_KEY "<your-nvd-api-key>"
   ```
   Restart your shell so the environment variable is available.

4. Run the tool:

   ```powershell
   .\NvdGuiExport.ps1
   ```

5. Choose a product and date window → **OK**.
6. Open the generated CSV under `.\out\`.

---

## Usage Details

### Script

* **Name**: `NvdGuiExport.ps1`
* **Behavior**:

  * Reads `.\products.txt` and ignores blank lines or lines starting with `#`
  * Initializes WPF window with:

    * Product dropdown (from `products.txt`)
    * Start/End **DatePickers** (defaults: last 7 days to today, UTC)
  * Builds an ISO-8601 UTC **publication window** for NVD (`pubStartDate`, `pubEndDate`)
  * Selects **CPE** vs **keyword** mode based on the dropdown value
  * Paginates through NVD results, flattens records, writes a CSV

### Output Schema

Each row corresponds to a CVE (duplicated per affected CPE when present):

| Column           | Description                                     |   |
| ---------------- | ----------------------------------------------- | - |
| `ProductFilter`  | The selected product/CPE from the GUI           |   |
| `CVE`            | CVE identifier (e.g., `CVE-2025-12345`)         |   |
| `Published`      | NVD publication timestamp                       |   |
| `LastModified`   | Last modified timestamp                         |   |
| `CVSS_BaseScore` | Base score (prefers v3.1 → v3.0 → v2 if needed) |   |
| `Severity`       | Derived label: Critical/High/Medium/Low         |   |
| `Summary`        | English description                             |   |
| `RefUrls`        | Reference URLs joined with `                    | ` |
| `Vendor`         | Parsed from CPE 2.3 (if available)              |   |
| `Product`        | Parsed from CPE 2.3 (if available)              |   |
| `Version`        | Parsed from CPE 2.3 (if available)              |   |
| `CPE23Uri`       | Full CPE 2.3 URI (if available)                 |   |

---

## Examples

### Keywords (broad)

* `products.txt` line: `microsoft edge`
  Query uses: `keywordSearch=microsoft edge`

### CPE (precise)

* `products.txt` line: `cpe:2.3:a:microsoft:edge:*:*:*:*:*:*:*:*`
  Query uses: `cpeName=cpe:2.3:a:microsoft:edge:*:*:*:*:*:*:*:*`

---

## Tips & Good Practices

* Prefer **CPE entries** for cleaner, vendor-scoped results when you know them.
* Use **keyword lines** to explore or when you don’t know the CPE yet.
* Keep separate `products.txt` files per client/product family to reduce noise.
* If you hit rate limits, request and set an **NVD API key** and keep `Days` windows reasonable.

---

## Troubleshooting

* **No GUI appears**

  * Ensure you’re running in a **desktop session** (WPF requires it).
  * On PowerShell 7, WPF works on Windows; if you’re remoting headlessly, use CSV mode in a non-GUI script instead.
* **Empty results**

  * Check dates (UTC). NVD uses `pubStartDate`/`pubEndDate` in UTC.
  * Try a broader **keyword** first, then refine to CPE.
* **Rate limit / 403**

  * Set `NVD_API_KEY` and restart shell.
* **CSV not created**

  * Confirm write permissions to `.\out\`. The script creates the folder if missing.

---

## Roadmap

* Optional **CPE discovery** step (search NVD CPE API from a human keyword and let the user pick a precise CPE).
* **CISA KEV** checkbox to tag exploited-in-the-wild CVEs.
* Export to **Excel** (`.xlsx`) with multiple sheets (CVEs, AffectedProducts, References).
* Webhook push to **Microsoft Teams/Slack** after export.
* Saved **profiles** for common product sets per customer.

---

## Security Notes

* No secrets are stored; NVD API key can be provided via environment variable.
* Output is local CSV only; review before sharing to avoid leaking internal product lists.

---

## License

MIT. See `LICENSE` file.

---

## Acknowledgments

* Data powered by the **NVD (NIST) CVE API v2**.
* CPE parsing follows **CPE 2.3** URI conventions.

```
::contentReference[oaicite:0]{index=0}
```
