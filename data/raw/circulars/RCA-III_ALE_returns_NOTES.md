# RCA-III and ALE — return metadata (templates gated)

From RBI's "List of Returns Submitted to RBI" (`rbi.org.in/scripts/BS_Listofallreturns.aspx`), confirmed real entries with direct download URLs — but the URLs resolve to `rbidocs.rbi.org.in`, which returns a CAPTCHA-challenge page (bot-detection JS, TSPD cookie) disguised as a 200-status `.pdf`, same gate as the circular PDFs found earlier. Template files not retrieved; metadata below is from the list page itself, which is not gated.

## Return on Capital Adequacy-III (RCA-III)
- **Purpose:** "Computation of capital base; computation of risk weighted assets; and risk based capital as per BASEL-III Capital Adequacy framework"
- **Frequency:** Quarterly
- **Department:** DoS
- **India's actual structured equivalent** to the Basel III Pillar 3 disclosure we're using (HDFC Bank PDF) — worth trying to get this template if it becomes reachable later, as it would let `LINE_ITEM_MAP` be seeded from RBI's own field list rather than a bank's public disclosure.
- Attempted URL: `rbidocs.rbi.org.in/rdocs/Forms/PDFs/200Report on Capital Adequacy-III (RCA - III)_1.pdf` (and `_2.pdf`) — gated.

## Return on Asset Liability and Off-Balance Sheet Exposures (ALE)
- **Purpose:** "granular breakup of Assets and liability items along with details regarding off balance sheet and derivative exposures"
- **Frequency:** Monthly
- **Department:** DoS
- Closely matches the granularity `GL_ENTRIES`/`POSITIONS` need — same gate applies.

## Fraud Monitoring Return (FMR) — resolved, no gap
Its listing links directly to `BS_ViewMasDirections.aspx?id=13641` — i.e. MD 412 (Fraud Risk Management), which we already have in full. FMR has no separate downloadable template; its structure is defined inside MD 412's text itself.
