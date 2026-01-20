# Stream Contract

A Clarity contract for block-based payment streams between a sender (`tx-sender`) and a provider. Streams are stored per `(sender, provider)` pair and payments are settled when `stream-payment` is called.

## Data Model

- `streams` map keyed by `{ sender, provider }` with:
  - `rate-per-block` (uint)
  - `token-type` (`TOKEN_STX` = `u0`, `TOKEN_FT` = `u1`)
  - `token-contract` (optional principal) stored for FT streams
  - `start-height`, `last-paid` (uint)
  - `end-height` (optional uint)
  - `status` (`STATUS_ACTIVE` = `u0`, `STATUS_PAUSED` = `u1`, `STATUS_CLOSED` = `u2`)

## Public Functions

- `open-stream(provider, rate-per-block, token-type, token-contract, end-height)`
  - Creates a new stream for `tx-sender` → `provider` if one does not already exist.
  - Validates rate, token type, and end height.
  - Stores the FT contract principal if `TOKEN_FT` is used.
- `pause-stream(provider)`, `resume-stream(provider)`, `close-stream(provider)`
  - Update stream status for the caller’s stream.
- `stream-payment(provider, token-contract)`
  - Computes blocks since `last-paid`, capped by `MAX_BLOCKS_PER_PAYMENT` (`u1440`).
  - Transfers `amount = blocks-passed * rate-per-block` from `tx-sender` to `provider`.
  - Updates `last-paid`; closes the stream if `end-height` is reached.
- `get-stream(sender, provider)` (read-only)
  - Returns the stored stream record (or `none`).

## Token Handling

- STX: use `TOKEN_STX` and pass `none` for `token-contract`.
- FT (SIP-010): use `TOKEN_FT`, pass `(some <sip010-ft-trait>)` to `open-stream`,
  and pass the same contract as `token-contract` to `stream-payment`.
  The contract principal must match the stored `token-contract`.

## Events

The contract uses `print` with event objects:
- `stream-opened`, `stream-paused`, `stream-resumed`, `stream-closed`, `stream-paid`

## Error Codes

- `u100` `ERR_STREAM_EXISTS`
- `u101` `ERR_STREAM_NOT_FOUND`
- `u102` `ERR_STREAM_PAUSED`
- `u103` `ERR_STREAM_CLOSED`
- `u104` `ERR_INVALID_RATE`
- `u105` `ERR_INVALID_END_HEIGHT`
- `u106` `ERR_INVALID_TOKEN`
- `u107` `ERR_ZERO_BLOCKS`
- `u108` `ERR_INVALID_LAST_PAID`
