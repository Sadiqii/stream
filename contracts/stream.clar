(define-constant ERR_STREAM_EXISTS u100)
(define-constant ERR_STREAM_NOT_FOUND u101)
(define-constant ERR_STREAM_PAUSED u102)
(define-constant ERR_STREAM_CLOSED u103)
(define-constant ERR_INVALID_RATE u104)
(define-constant ERR_INVALID_END_HEIGHT u105)
(define-constant ERR_INVALID_TOKEN u106)
(define-constant ERR_ZERO_BLOCKS u107)
(define-constant ERR_INVALID_LAST_PAID u108)

(define-constant TOKEN_STX u0)
(define-constant TOKEN_FT u1)

(define-constant STATUS_ACTIVE u0)
(define-constant STATUS_PAUSED u1)
(define-constant STATUS_CLOSED u2)

(define-constant MAX_BLOCKS_PER_PAYMENT u1440)

(define-trait sip010-ft-trait
  (
    (transfer (uint principal principal) (response bool uint))
  )
)

(define-map streams
  { sender: principal, provider: principal }
  {
    rate-per-block: uint,
    token-type: uint,
    token-contract: (optional principal),
    start-height: uint,
    last-paid: uint,
    end-height: (optional uint),
    status: uint
  }
)

(define-read-only (get-stream (sender principal) (provider principal))
  (map-get? streams { sender: sender, provider: provider })
)

(define-private (min-uint (a uint) (b uint))
  (if (< a b) a b)
)

(define-private (effective-height (end-height (optional uint)))
  (match end-height end
    (min-uint burn-block-height end)
    burn-block-height
  )
)

(define-private (require-stream (sender principal) (provider principal))
  (match (map-get? streams { sender: sender, provider: provider })
    stream (ok stream)
    (err ERR_STREAM_NOT_FOUND)
  )
)

(define-private (require (condition bool) (err-code uint))
  (if condition (ok true) (err err-code))
)

(define-private (validate-end-height (end-height (optional uint)))
  (match end-height end
    (require (>= end burn-block-height) ERR_INVALID_END_HEIGHT)
    (ok true)
  )
)

(define-private (pay-stream (token-type uint) (stored-token (optional principal)) (provided-token (optional <sip010-ft-trait>)) (amount uint) (sender principal) (provider principal))
  (if (is-eq token-type TOKEN_STX)
      (if (is-none provided-token)
          (stx-transfer? amount sender provider)
          (err ERR_INVALID_TOKEN)
      )
      (match provided-token token
        (match stored-token stored
          (if (is-eq (contract-of token) stored)
              (contract-call? token transfer amount sender provider)
              (err ERR_INVALID_TOKEN)
          )
          (err ERR_INVALID_TOKEN)
        )
        (err ERR_INVALID_TOKEN)
      )
  )
)

(define-public (open-stream (provider principal) (rate-per-block uint) (token-type uint) (token-contract (optional <sip010-ft-trait>)) (end-height (optional uint)))
  (begin
    (try! (require (> rate-per-block u0) ERR_INVALID_RATE))
    (try! (require (or (is-eq token-type TOKEN_STX) (is-eq token-type TOKEN_FT)) ERR_INVALID_TOKEN))
    (if (is-eq token-type TOKEN_STX)
        (try! (require (is-none token-contract) ERR_INVALID_TOKEN))
        (try! (require (is-some token-contract) ERR_INVALID_TOKEN))
    )
    (try! (validate-end-height end-height))
    (if (is-some (map-get? streams { sender: tx-sender, provider: provider }))
        (err ERR_STREAM_EXISTS)
        (begin
          (map-set streams
            { sender: tx-sender, provider: provider }
            {
              rate-per-block: rate-per-block,
              token-type: token-type,
              token-contract: (match token-contract token (some (contract-of token)) none),
              start-height: burn-block-height,
              last-paid: burn-block-height,
              end-height: end-height,
              status: STATUS_ACTIVE
            }
          )
          (print { event: "stream-opened", sender: tx-sender, provider: provider, rate: rate-per-block, token-type: token-type })
          (ok true)
        )
    )
  )
)

(define-public (pause-stream (provider principal))
  (let ((stream (try! (require-stream tx-sender provider))))
    (if (is-eq (get status stream) STATUS_CLOSED)
        (err ERR_STREAM_CLOSED)
        (begin
          (map-set streams
            { sender: tx-sender, provider: provider }
            (merge stream { status: STATUS_PAUSED })
          )
          (print { event: "stream-paused", sender: tx-sender, provider: provider })
          (ok true)
        )
    )
  )
)

(define-public (resume-stream (provider principal))
  (let ((stream (try! (require-stream tx-sender provider))))
    (if (is-eq (get status stream) STATUS_CLOSED)
        (err ERR_STREAM_CLOSED)
        (begin
          (map-set streams
            { sender: tx-sender, provider: provider }
            (merge stream { status: STATUS_ACTIVE })
          )
          (print { event: "stream-resumed", sender: tx-sender, provider: provider })
          (ok true)
        )
    )
  )
)

(define-public (close-stream (provider principal))
  (let ((stream (try! (require-stream tx-sender provider))))
    (begin
      (map-set streams
        { sender: tx-sender, provider: provider }
        (merge stream { status: STATUS_CLOSED })
      )
      (print { event: "stream-closed", sender: tx-sender, provider: provider })
      (ok true)
    )
  )
)

(define-public (stream-payment (provider principal) (token-contract (optional <sip010-ft-trait>)))
  (let ((stream (try! (require-stream tx-sender provider))))
    (begin
      (try! (require (not (is-eq (get status stream) STATUS_CLOSED)) ERR_STREAM_CLOSED))
      (try! (require (is-eq (get status stream) STATUS_ACTIVE) ERR_STREAM_PAUSED))
      (let (
        (current-effective (effective-height (get end-height stream)))
        (last-paid (get last-paid stream))
      )
        (begin
          (try! (require (>= current-effective last-paid) ERR_INVALID_LAST_PAID))
          (let (
            (uncapped-blocks (- current-effective last-paid))
            (blocks-passed (min-uint uncapped-blocks MAX_BLOCKS_PER_PAYMENT))
          )
            (begin
              (try! (require (> blocks-passed u0) ERR_ZERO_BLOCKS))
              (let (
                (amount (* blocks-passed (get rate-per-block stream)))
                (new-last (+ last-paid blocks-passed))
                (should-close (match (get end-height stream) end (is-eq new-last end) false))
              )
                (begin
                  (try! (pay-stream (get token-type stream) (get token-contract stream) token-contract amount tx-sender provider))
                  (map-set streams
                    { sender: tx-sender, provider: provider }
                    (merge stream { last-paid: new-last, status: (if should-close STATUS_CLOSED (get status stream)) })
                  )
                  (print { event: "stream-paid", sender: tx-sender, provider: provider, amount: amount, last-paid: new-last, token-type: (get token-type stream) })
                  (ok amount)
                )
              )
            )
          )
        )
      )
    )
  )
)
