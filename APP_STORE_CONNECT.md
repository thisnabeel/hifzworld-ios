# Hifz.World — App Store Connect copy

Paste these into **App Store → iOS App Version 1.0.1**. Character counts are under Apple’s limits.

Replace anything in `[brackets]` before submit.

---

## Promotional Text
*(max 170 — shown above the description when you set one)*

```
Memorize with a partner. Build page decks, share them, and get live Mushaf feedback while you recite — plus clear qirāʾāt comparison on every page.
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

DECKS FOR REVIEW
• Save collections of Mushaf pages as decks
• Open a deck in the Mushaf and move through only those pages
• Perfect for juz’, surahs, or weak pages you need to strengthen

RECITE WITH A LISTENER
• Share a deck with a teacher, friend, or family member
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
Welcome to Hifz.World — Mushaf reading, qirāʾāt comparison, page decks, and live review with a listener.
```

---

## App Review — Sign-In

**Sign-in required:** Yes (for Decks / share / review). Mushaf browsing works without an account.

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
Thank you for reviewing Hifz.World (1.0.1, build 10).

RESOLUTION OF PRIOR REJECTION (vs build 7)
• 5.1.1 Account deletion: Permanent in-app deletion is available (not deactivate-only).
  Path: Sign in → Mushaf tab → open drawer (☰) → Delete Account → confirm.
  This calls DELETE /api/users/me and removes the account and associated server data.
• 2.5.4 Background modes: Removed UIBackgroundModes "audio" and "voip".
  This build has no persistent background audio and no VoIP/video calls.
• A screen recording of Sign in → Delete Account is attached / included with this reply.

SIGN IN
• Sign in with Apple only (no username/password).
• Please use your own Apple ID on the review device.
• After signing in, Decks, sharing, review, and deck recording unlock.

ACCOUNT DELETION (please verify)
1. Sign in with Apple.
2. Mushaf tab → open the left drawer (menu).
3. Tap Delete Account → confirm.
4. Account is deleted and you are signed out.

MICROPHONE (on-device only)
• Decks tab → mic on a deck starts a recitation recording.
• Audio is stored on the device only (not uploaded to our servers).
• List button (when takes exist) opens previous recordings; play opens that deck with saved marks.
• No background audio mode — playback is in-foreground.

WHAT TO TEST WITHOUT SIGN-IN
1. Mushaf tab — swipe pages / Go To Page.
2. Drawer → Settings — qirāʾāt / light-dark options.

WHAT TO TEST WITH SIGN-IN
1. Decks → create a deck → add pages from Mushaf.
2. Optional: share a deck / start a review session with another Apple ID.
3. Decks → mic → record while marking mistakes → Stop (tab bar) → play the take.
4. Feedback tab after a review session.
5. Drawer → Send Feedback.
6. Drawer → Delete Account.

NOTES
• No in-app purchases. No third-party social login. No VoIP/camera.
• No UIBackgroundModes audio or voip.
• We do not use tracking (ATT not required for advertising ID).
• Backend: hifzworld-api on Railway. Retry on Wi‑Fi if something fails to load.
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
3. Decks list  
4. Review / marks (listener or Feedback)  
5. Optional: landscape spread  

First **3** appear on the install sheet — make those the strongest.
