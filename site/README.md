# Ownlight public pages

This folder contains the minimal static pages needed for App Store readiness:

- `/privacy/zh-Hans/` for the Simplified Chinese Privacy Policy URL
- `/privacy/en/` for the English Privacy Policy URL
- `/privacy/` as a lightweight language chooser
- `/support/` for Support URL
- `/` as a lightweight link hub

Current production deployment:

- Cloudflare Pages project: `private-moments-site`
- Production domain: `https://private-moments.popcornnn.xyz`

Use these build settings for the App Store build:

```bash
PRIVATE_MOMENTS_PRIVACY_POLICY_URL=https://private-moments.popcornnn.xyz/privacy
PRIVATE_MOMENTS_PRIVACY_POLICY_URL_ZH_HANS=https://private-moments.popcornnn.xyz/privacy/zh-Hans
PRIVATE_MOMENTS_PRIVACY_POLICY_URL_EN=https://private-moments.popcornnn.xyz/privacy/en
PRIVATE_MOMENTS_SUPPORT_URL=https://private-moments.popcornnn.xyz/support
```

The support email currently assumes Cloudflare Email Routing or an equivalent mailbox for `support@popcornnn.xyz`; update the address before submission if a different support address is used.
