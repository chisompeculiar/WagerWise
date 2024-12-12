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

;; Track bets with claimed amount
(define-map bets
  { market-id: uint, better: principal, option: uint }
  { 
    amount: uint,
    claimed-amount: uint  ;; Track how much has been claimed
  }
)

;; Track total amount bet per option
(define-map option-totals
  { market-id: uint, option: uint }
  { total-amount: uint }
)

;; Define data variables
(define-data-var market-nonce uint u0)

;; Error constants
(define-constant ERR-NOT-FOUND (err u404))
(define-constant ERR-UNAUTHORIZED (err u401))
(define-constant ERR-ALREADY-SETTLED (err u409))
(define-constant ERR-MARKET-ACTIVE (err u400))
(define-constant ERR-INVALID-INPUT (err u422))
(define-constant ERR-INSUFFICIENT-BALANCE (err u423))
(define-constant ERR-ALREADY-CLAIMED (err u424))

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

(define-private (validate-market-id (market-id uint))
  (and 
    (>= market-id u0) 
    (< market-id (var-get market-nonce))
  )
)

;; Helper function to update option totals
(define-private (update-option-total (market-id uint) (option uint) (amount uint))
  (let
    (
      (current-total (default-to { total-amount: u0 } 
        (map-get? option-totals { market-id: market-id, option: option })))
    )
    (map-set option-totals
      { market-id: market-id, option: option }
      { total-amount: (+ (get total-amount current-total) amount) }
    )
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
        (existing-bet (default-to { amount: u0, claimed-amount: u0 }
          (map-get? bets { market-id: market-id, better: tx-sender, option: option })))
      )
      (asserts! (< block-height (get end-block market)) ERR-MARKET-ACTIVE)
      (asserts! (not (get is-settled market)) ERR-ALREADY-SETTLED)
      (asserts! (and (> option u0) (<= option (len (get options market)))) ERR-INVALID-INPUT)
      (asserts! (> amount u0) ERR-INVALID-INPUT)
      
      ;; Transfer STX from better to contract
      (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
      
      ;; Update or create bet
      (map-set bets
        { market-id: market-id, better: tx-sender, option: option }
        { 
          amount: (+ amount (get amount existing-bet)),
          claimed-amount: (get claimed-amount existing-bet)
        }
      )
      
      ;; Update option totals
      (update-option-total market-id option amount)
      
      ;; Update market totals
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

;; Calculate total winnings for a bet
(define-read-only (calculate-winnings (market-id uint) (option uint) (bet-amount uint))
  (let
    (
      (market (unwrap! (map-get? markets { market-id: market-id }) ERR-NOT-FOUND))
      (option-total (unwrap! (map-get? option-totals { market-id: market-id, option: option }) ERR-NOT-FOUND))
    )
    (ok (/ (* (get total-bets market) bet-amount) (get total-amount option-total)))
  )
)

;; Claim partial winnings
(define-public (claim-partial-winnings (market-id uint) (option uint) (amount-to-claim uint))
  (begin
    (asserts! (validate-market-id market-id) ERR-INVALID-INPUT)
    (let
      (
        (market (unwrap! (map-get? markets { market-id: market-id }) ERR-NOT-FOUND))
        (bet (unwrap! (map-get? bets { market-id: market-id, better: tx-sender, option: option }) ERR-NOT-FOUND))
        (winning-option (unwrap! (get winning-option market) ERR-NOT-FOUND))
      )
      (asserts! (get is-settled market) ERR-MARKET-ACTIVE)
      (asserts! (is-eq option winning-option) ERR-UNAUTHORIZED)
      (asserts! (<= (+ (get claimed-amount bet) amount-to-claim) (get amount bet)) ERR-INSUFFICIENT-BALANCE)
      
      (let
        (
          (total-bets (get total-bets market))
          (winning-amount (unwrap! (calculate-winnings market-id option amount-to-claim) ERR-INVALID-INPUT))
        )
        ;; Transfer winnings
        (try! (as-contract (stx-transfer? winning-amount tx-sender tx-sender)))
        
        ;; Update claimed amount
        (map-set bets
          { market-id: market-id, better: tx-sender, option: option }
          { 
            amount: (get amount bet),
            claimed-amount: (+ (get claimed-amount bet) amount-to-claim)
          }
        )
        
        ;; If fully claimed, delete the bet
        (if (is-eq (+ (get claimed-amount bet) amount-to-claim) (get amount bet))
          (map-delete bets { market-id: market-id, better: tx-sender, option: option })
          true
        )
        
        (ok winning-amount)
      )
    )
  )
)

;; Claim all remaining winnings
(define-public (claim-all-winnings (market-id uint) (option uint))
  (let
    (
      (bet (unwrap! (map-get? bets { market-id: market-id, better: tx-sender, option: option }) ERR-NOT-FOUND))
      (unclaimed-amount (- (get amount bet) (get claimed-amount bet)))
    )
    (asserts! (> unclaimed-amount u0) ERR-ALREADY-CLAIMED)
    (claim-partial-winnings market-id option unclaimed-amount)
  )
)

;; Read-only functions

;; Get market details
(define-read-only (get-market (market-id uint))
  (map-get? markets { market-id: market-id })
)

;; Get specific bet details
(define-read-only (get-bet (market-id uint) (better principal) (option uint))
  (map-get? bets { market-id: market-id, better: better, option: option })
)

;; Get option total
(define-read-only (get-option-total (market-id uint) (option uint))
  (map-get? option-totals { market-id: market-id, option: option })
)

;; Get unclaimed amount for a bet
(define-read-only (get-unclaimed-amount (market-id uint) (better principal) (option uint))
  (let
    (
      (bet (unwrap! (map-get? bets { market-id: market-id, better: better, option: option }) ERR-NOT-FOUND))
    )
    (ok (- (get amount bet) (get claimed-amount bet)))
  )
)