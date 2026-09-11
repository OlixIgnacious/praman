# DoS.CO.PPG.66/11.01.005/2026-27 — "Consolidation of Supervisory Instructions – Repeal of Circulars"

**Status: notification PDF retrieved (real browser got past the gate — `DoS_CO_PPG_66_notification.pdf`, same folder). It's genuinely 1 page (confirmed via `pdfinfo`) — the "Annex" is a hyperlink, not embedded content. Traced the link: it goes to `NotificationUserWithdrawnCircular.aspx` (the general Circulars Withdrawn page), not a static file. Also checked the linked press release (`BS_PressReleaseDisplay.aspx?prid=63265`) — it confirms the same thing in its own words: "The repealed circulars can be accessed under Notifications → Circulars Withdrawn → Circulars withdrawn by the Department of Supervision." There is no single downloadable list — this is RBI's own stated access path, an interactive filtered browse page, not a file to fetch.**

## What it is

A short RBI notification, RBI/DoS/2026-27/221, DoS.CO.PPG.66/11.01.005/2026-27, dated **July 31, 2026**, signed by Monisha Chakraborty (Chief General Manager-in-Charge). Full text of the notification body:

> "Please refer to the press release issued on July 31, 2026 announcing the release of 64 Consolidated Directions administered by the Department of Supervision (DoS) of the Reserve Bank of India.
>
> 2. These Directions encompass all instructions issued by DoS as well as the erstwhile Departments whose supervisory functions have been merged into DoS, either partly or fully. Further, the extant instructions considered obsolete have been excluded from the consolidated Directions as they are no longer relevant.
>
> 3. Accordingly, the 628 circulars listed in the **Annex**, comprising those whose instructions have been consolidated into these Directions, as well as those which have become obsolete or redundant, are hereby repealed by the Reserve Bank with immediate effect.
>
> 4. Notwithstanding such repeal, any action taken or purported to have been taken, or initiated under the repealed Directions, instructions, or guidelines shall continue to be governed by the provisions thereof."

This is the master circular that MD 412, MD 414, and MD 415 (and presumably all 64 consolidated Master Directions) each cite as the authority for their repeal clause. It confirms the consolidation is real, dated, and named — but the notification text itself is just the cover memo. **The actual itemized list of 628 circulars is in an attached Annex, not in this text.**

## How to get it

- **Page (retrieved):** `https://www.rbi.org.in/scripts/NotificationUser.aspx?Id=13663&Mode=0` — this is not gated, fetches fine directly.
- **Full notification + Annex PDF (gated):** `https://rbidocs.rbi.org.in/rdocs/notification/PDFs/NT221FE0A4B324CB7415EAFFA02710AC67A48.PDF` (262 KB per the page header). Confirmed the same way as every other `rbidocs.rbi.org.in` link: HTTP 200, but the response body is a bot-detection challenge page (TSPD cookie script), not the real PDF — automated fetch cannot get past this.

## Final status: confirmed dead end, not a rendering limitation

Used live browser automation (not static fetch) to open `NotificationUserWithdrawnCircular.aspx` → "Circulars Withdrawn by the Department of Supervision" directly. Got the full rendered table — no pagination, no JS gate, a single page listing entries **back to 1999** (362+ rows visible, likely more). Searched the complete text (82,000+ characters): `DoS.CO.PPG.66`, "July 31, 2026", and "628 circular" appear **zero times**. Most recent entry in this table is `DoS.CO.PPG.SEC.1/11.01.005/2026-27`, dated May 21, 2026.

**Conclusion:** RBI's own notification PDF points to this exact page as the source of the itemized 628-circular list, but the page's actual content doesn't contain it as of Sept 12, 2026 — likely a data-lag on RBI's side between the July 31, 2026 announcement and this index being updated, not something retrievable by any client-side method (static fetch or live browser). Every automated avenue is exhausted. **Whether to accept this as a scope cut or pursue it another way (e.g. contacting RBI directly, checking back later for the index to update, an alternate archive/mirror) is an open decision for the project owner, not made here.** If left unresolved, the fallback is real but partial: three Master Directions (412, 414, 415) each confirming a specific prior state was repealed on July 31, 2026 by this named circular — real Stage-1-eval-usable ground truth, just without the itemized delta.
