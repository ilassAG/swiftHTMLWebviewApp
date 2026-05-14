# Stripe Tap to Pay Example

Example web integration for the optional native Tap to Pay bridge.

The native app must provide Stripe Terminal support and your backend must create:

- Stripe Terminal connection tokens
- PaymentIntents with `card_present`
- Terminal locations

See `docs/stripe-tap-to-pay.md` for the bridge contract.
