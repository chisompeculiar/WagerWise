;; WagerWise: A Prediction Market Smart Contract

;; Define data maps
(define-map markets
  { market-id: uint }
  {
    creator: principal,
    description: (string-utf8 256),
    options: (list 10 (string-utf8 64)),
    end-block: uint,
    total-bets: uint,
    is-settled: bool,
    winning-option: (optional uint)
  }
)

(define-map bets
  { market-id: uint, better: principal }
  { option: uint, amount: uint }
)

;; Define data variables
(define-data-var market-nonce uint u0)

;; Error constants
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-ALREADY-SETTLED (err u409))
(define-constant ERR-MARKET-ACTIVE (err u400))
(define-constant ERR-INVALID-INPUT (err u422))

;; Helper functions for input validation
(define-private (validate-string (input (string-utf8 256)))
  (< u0 (len input))
)

(define-private (validate-options (options (list 10 (string-utf8 64))))
  (and (< u0 (len options)) (<= (len options) u10))
)

(define-private (validate-end-block (end-block uint))
  (> end-block block-height)
)

;; Validate market ID exists and is within valid range
(define-private (validate-market-id (market-id uint))
  (and 
    (>= market-id u0) 
    (< market-id (var-get market-nonce))
  )
)

;; Create a new prediction market
(define-public (create-market (description (string-utf8 256)) (options (list 10 (string-utf8 64))) (end-block uint))
  (let
    (
      (market-id (var-get market-nonce))
    )
    (asserts! (validate-string description) ERR-INVALID-INPUT)
    (asserts! (validate-options options) ERR-INVALID-INPUT)
    (asserts! (validate-end-block end-block) ERR-INVALID-INPUT)
    (map-set markets
      { market-id: market-id }
      {
        creator: tx-sender,
        description: description,
        options: options,
        end-block: end-block,
        total-bets: u0,
        is-settled: false,
        winning-option: none
      }
    )
    (var-set market-nonce (+ market-id u1))
    (ok market-id)
  )
)

;; Place a bet on a market
(define-public (place-bet (market-id uint) (option uint) (amount uint))
  (begin
    (asserts! (validate-market-id market-id) ERR-INVALID-INPUT)
    (let
      (
        (market (unwrap! (map-get? markets { market-id: market-id }) ERR-NOT-FOUND))
      )
      (asserts! (< block-height (get end-block market)) ERR-MARKET-ACTIVE)
      (asserts! (not (get is-settled market)) ERR-ALREADY-SETTLED)
      (asserts! (and (> option u0) (<= option (len (get options market)))) ERR-INVALID-INPUT)
      (asserts! (> amount u0) ERR-INVALID-INPUT)
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      (map-set bets
        { market-id: market-id, better: tx-sender }
        { option: option, amount: amount }
      )
      (map-set markets
        { market-id: market-id }
        (merge market { total-bets: (+ (get total-bets market) amount) })
      )
      (ok true)
    )
  )
)

;; Settle a market (only callable by the market creator)
(define-public (settle-market (market-id uint) (winning-option uint))
  (begin
    (asserts! (validate-market-id market-id) ERR-INVALID-INPUT)
    (let
      (
        (market (unwrap! (map-get? markets { market-id: market-id }) ERR-NOT-FOUND))
      )
      (asserts! (is-eq tx-sender (get creator market)) ERR-UNAUTHORIZED)
      (asserts! (>= block-height (get end-block market)) ERR-MARKET-ACTIVE)
      (asserts! (not (get is-settled market)) ERR-ALREADY-SETTLED)
      (asserts! (and (> winning-option u0) (<= winning-option (len (get options market)))) ERR-INVALID-INPUT)
      (map-set markets
        { market-id: market-id }
        (merge market { is-settled: true, winning-option: (some winning-option) })
      )
      (ok true)
    )
  )
)

;; Claim winnings (if any)
(define-public (claim-winnings (market-id uint))
  (begin
    (asserts! (validate-market-id market-id) ERR-INVALID-INPUT)
    (let
      (
        (market (unwrap! (map-get? markets { market-id: market-id }) ERR-NOT-FOUND))
        (bet (unwrap! (map-get? bets { market-id: market-id, better: tx-sender }) ERR-NOT-FOUND))
        (winning-option (unwrap! (get winning-option market) ERR-NOT-FOUND))
      )
      (asserts! (get is-settled market) ERR-MARKET-ACTIVE)
      (asserts! (is-eq (get option bet) winning-option) ERR-UNAUTHORIZED)
      (let
        (
          (total-bets (get total-bets market))
          (winning-amount (/ (* total-bets (get amount bet)) (get amount bet)))
        )
        (try! (as-contract (stx-transfer? winning-amount tx-sender tx-sender)))
        (map-delete bets { market-id: market-id, better: tx-sender })
        (ok winning-amount)
      )
    )
  )
)

;; Read-only functions

;; Get market details
(define-read-only (get-market (market-id uint))
  (map-get? markets { market-id: market-id })
)

;; Get bet details
(define-read-only (get-bet (market-id uint) (better principal))
  (map-get? bets { market-id: market-id, better: better })
)