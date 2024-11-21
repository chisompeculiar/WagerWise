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

;; Create a new prediction market
(define-public (create-market (description (string-utf8 256)) (options (list 10 (string-utf8 64))) (end-block uint))
  (let
    (
      (market-id (var-get market-nonce))
    )
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
  (let
    (
      (market (unwrap! (map-get? markets { market-id: market-id }) ERR-NOT-FOUND))
    )
    (asserts! (< block-height (get end-block market)) ERR-MARKET-ACTIVE)
    (asserts! (not (get is-settled market)) ERR-ALREADY-SETTLED)
    (asserts! (<= option (len (get options market))) ERR-NOT-FOUND)
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

;; Settle a market (only callable by the market creator)
(define-public (settle-market (market-id uint) (winning-option uint))
  (let
    (
      (market (unwrap! (map-get? markets { market-id: market-id }) ERR-NOT-FOUND))
    )
    (asserts! (is-eq tx-sender (get creator market)) ERR-UNAUTHORIZED)
    (asserts! (>= block-height (get end-block market)) ERR-MARKET-ACTIVE)
    (asserts! (not (get is-settled market)) ERR-ALREADY-SETTLED)
    (asserts! (<= winning-option (len (get options market))) ERR-NOT-FOUND)
    (map-set markets
      { market-id: market-id }
      (merge market { is-settled: true, winning-option: (some winning-option) })
    )
    (ok true)
  )
)

;; Claim winnings (if any)
(define-public (claim-winnings (market-id uint))
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

;; Read-only functions

;; Get market details
(define-read-only (get-market (market-id uint))
  (map-get? markets { market-id: market-id })
)

;; Get bet details
(define-read-only (get-bet (market-id uint) (better principal))
  (map-get? bets { market-id: market-id, better: better })
)