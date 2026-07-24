# Hifz.World — App Store Connect copy

Paste these into **App Store → iOS App Version 1.0**. Character counts are under Apple’s limits.

Replace anything in `[brackets]` before submit.

---

## Promotional Text
*(max 170 — shown above the description when you set one)*

```
Memorize with a partner. Build page bundles, share them, and get live Mushaf feedback while you recite — plus clear qirāʾāt comparison on every page.
```

---

## Description
*(max 4,000)*

```
Hifz.World helps you memorize and review the Qur’an with a clear Mushaf, qirāʾāt awareness, and real feedback from someone listening with you.

MUSHAF YOU CAN TRUST
• Read page by page in a clean, full-screen Mushaf
• Jump to any page quickly
• Light and dark modes for comfortable reading
• Landscape two-page spread on supported devices

COMPARE QIRĀʾĀT
• See differences between readings side by side
• Highlight variations as you study
• Focus on what matters for your memorization

BUNDLES FOR REVIEW
• Save collections of Mushaf pages as bundles
• Open a bundle in the Mushaf and move through only those pages
• Perfect for juz’, surahs, or weak pages you need to strengthen

RECITE WITH A LISTENER
• Share a bundle with a teacher, friend, or family member
• They follow along on the same pages while you recite
• Listeners can mark mistakes on the Mushaf in real time
• Review marks later in Feedback so you know what to fix

BUILT FOR HUFFĀZ
• Sign in with Apple to sync and share securely
• Send product feedback from the app when you need help
• Designed for focused practice — not distraction

Whether you are reviewing alone or with a partner, Hifz.World keeps the Mushaf, your pages, and your feedback in one place.
```

---

## Keywords
*(max 100 characters, comma-separated, no spaces after commas preferred)*

```
quran,hifz,memorize,mushaf,qiraat,recitation,tajweed,hafiz,review,islam
```

*(99 characters)*

---

## URLs

Hosted on hifzworld-api (same Railway service). After deploy, paste these:

| Field | Value |
| --- | --- |
| **Support URL** *(required)* | `https://hifzworld-api-production.up.railway.app/support` |
| **Marketing URL** *(optional)* | `https://hifzworld-api-production.up.railway.app/` |
| **Privacy Policy URL** *(App Privacy / App Information — required)* | `https://hifzworld-api-production.up.railway.app/privacy` |
| **Contact** | `nabeel@iqra.life` (also on `/contact`) |

---

## Version & legal

| Field | Value |
| --- | --- |
| **Version** | `1.0` |
| **Copyright** | `2026 Nabeel Khan` |
| **Age Rating** | 4+ (no objectionable content; educational/religious) |

---

## What’s New
*(for 1.0 you can leave blank or use this)*

```
Welcome to Hifz.World — Mushaf reading, qirāʾāt comparison, page bundles, and live review with a listener.
```

---

## App Review — Sign-In

**Sign-in required:** Yes (for Bundles / share / review). Mushaf browsing works without an account.

| Field | Value |
| --- | --- |
| **User name** | Leave blank — Sign in with Apple only |
| **Password** | Leave blank |
| **Sign-in required** toggle | On if Connect asks; explain below that Apple ID is used |

### Contact Information

| Field | Suggested |
| --- | --- |
| First name | `Nabeel` |
| Last name | `Khan` |
| Phone | `[your phone]` |
| Email | `nabeel@iqra.life` |

---

## App Review Notes
*(paste into Notes — max 4,000)*

```
Thank you for reviewing Hifz.World.

RESOLUTION OF PRIOR REJECTION (build 8)
• Account deletion (5.1.1): Signed-in users can permanently delete their account in-app.
  Path: Mushaf tab → open drawer (menu) → Delete Account → confirm.
  This calls DELETE /api/users/me and removes the account and associated server data (not a temporary deactivation).
• Background modes (2.5.4): Removed UIBackgroundModes values "audio" and "voip". The shipping app does not provide persistent background audio or VoIP. Short in-app verse clips do not require background audio. Camera/microphone usage strings were also removed (no video/VoIP feature in this build).

SIGN IN
• The app uses Sign in with Apple only (no username/password account).
• Please use your own Apple ID on the review device.
• After signing in, Bundles, sharing, and review sessions unlock.

ACCOUNT DELETION DEMO
1. Sign in with Apple.
2. Mushaf tab → open the left drawer (menu).
3. Tap Delete Account → confirm in the alert.
4. Account is deleted; you are signed out.

WHAT TO TEST WITHOUT SIGN-IN
1. Open the Mushaf tab.
2. Swipe between pages; use Go To Page if available.
3. Open settings/qirāʾāt controls from the drawer and toggle comparison options.
4. Try light/dark Mushaf mode.

WHAT TO TEST WITH SIGN-IN
1. Sign in with Apple.
2. Bundles tab → create a bundle → add pages from the Mushaf (or from bundle UI).
3. Share a bundle with another Apple ID if a second device is available.
4. Start a review session: listener follows pages and can mark words; reciter sees marks / page sync.
5. Feedback tab shows review marks after a session.
6. Drawer → Send Feedback submits product feedback to our API.
7. Drawer → Delete Account (permanent deletion as above).

NOTES
• No in-app purchases.
• No third-party social login.
• No VoIP / background audio / camera / microphone features in this build.
• Core reading works offline for cached content; account features need network.
• We do not use tracking (ATT not required for advertising ID).

If anything fails to load, please retry on Wi‑Fi. Backend: hifzworld-api on Railway.
```

---

## Pricing & Availability (checklist)

- [ ] Free
- [ ] All countries you want (or start with primary markets)
- [ ] Release: **Manually release** until you’re ready (recommended for 1.0)

---

## App Privacy questionnaire (quick guide)

Declare only what you actually collect via Sign in with Apple + your API:

| Data | Collect? | Linked to identity? | Used for tracking? |
| --- | --- | --- | --- |
| Name / display name | Yes (Apple / profile) | Yes | No |
| Email | Yes (if user shares it) | Yes | No |
| User ID | Yes | Yes | No |
| Product interaction / feedback | Yes (optional feedback + review marks) | Yes | No |
| Diagnostics | Only if you add crash tools later | — | No |

**Tracking:** No  
**Privacy Nutrition Labels:** Contact Info, User ID, and optionally Other User Content (feedback / marks)

---

## After approval — force update

App Store numeric ID (for `IOS_APP_STORE_ID` on Railway) is under **App Information → Apple ID**, not the team member number (`1086717619`).

1. Ship build → wait until live  
2. Set Railway `MIN_APP_VERSION` to the marketing version (e.g. `1.0.1`)  
3. Set `IOS_APP_STORE_ID` to that Apple ID number  

---

## Screenshot tip

You already have 4 of 10 on 6.5". Prioritize order:

1. Mushaf page (hero)  
2. Qirāʾāt / variation highlight  
3. Bundles list  
4. Review / marks (listener or Feedback)  
5. Optional: landscape spread  

First **3** appear on the install sheet — make those the strongest.
