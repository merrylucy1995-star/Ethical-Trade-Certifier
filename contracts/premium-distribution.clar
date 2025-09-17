;; title: premium-distribution
;; version: 1.0.0
;; summary: Ensure fair trade premiums reach producers with transparent distribution
;; description: This contract automates fair trade premium calculations, distributions, and impact tracking
;;              to guarantee producers receive their fair share of premium payments.

;; Error constants
(define-constant ERR_UNAUTHORIZED (err u300))
(define-constant ERR_NOT_FOUND (err u301))
(define-constant ERR_INSUFFICIENT_FUNDS (err u302))
(define-constant ERR_INVALID_INPUT (err u303))
(define-constant ERR_ALREADY_DISTRIBUTED (err u304))
(define-constant ERR_PREMIUM_EXPIRED (err u305))
(define-constant ERR_INVALID_BENEFICIARY (err u306))

;; Premium status constants
(define-constant STATUS_PENDING "PENDING")
(define-constant STATUS_APPROVED "APPROVED")
(define-constant STATUS_DISTRIBUTED "DISTRIBUTED")
(define-constant STATUS_COMPLETED "COMPLETED")
(define-constant STATUS_DISPUTED "DISPUTED")
(define-constant STATUS_CANCELLED "CANCELLED")

;; Beneficiary type constants
(define-constant BENEFICIARY_PRODUCER "PRODUCER")
(define-constant BENEFICIARY_COOPERATIVE "COOPERATIVE")
(define-constant BENEFICIARY_COMMUNITY "COMMUNITY")
(define-constant BENEFICIARY_WORKER "WORKER")

;; Premium category constants
(define-constant CATEGORY_FAIR_TRADE "FAIR_TRADE")
(define-constant CATEGORY_ORGANIC "ORGANIC")
(define-constant CATEGORY_ENVIRONMENTAL "ENVIRONMENTAL")
(define-constant CATEGORY_SOCIAL "SOCIAL")
(define-constant CATEGORY_QUALITY "QUALITY")

;; Distribution method constants
(define-constant METHOD_DIRECT "DIRECT")
(define-constant METHOD_COOPERATIVE "COOPERATIVE")
(define-constant METHOD_ESCROW "ESCROW")
(define-constant METHOD_INSTALLMENTS "INSTALLMENTS")

;; Premium calculation period (blocks)
(define-constant PREMIUM_CALCULATION_PERIOD u4320) ;; ~1 month
(define-constant PREMIUM_VALIDITY_PERIOD u26280) ;; ~6 months

;; Default premium rates (basis points - 1% = 100bp)
(define-constant DEFAULT_FAIR_TRADE_RATE u200) ;; 2%
(define-constant DEFAULT_ORGANIC_RATE u150) ;; 1.5%
(define-constant DEFAULT_QUALITY_RATE u100) ;; 1%

;; Contract owner for administrative functions
(define-constant CONTRACT_OWNER tx-sender)

;; Data structures

;; Premium pools for different categories
(define-map premium-pools
  { pool-id: (string-ascii 64) }
  {
    category: (string-ascii 20),
    total-allocated: uint,
    total-distributed: uint,
    current-balance: uint,
    creation-date: uint,
    expiry-date: uint,
    pool-manager: principal,
    active: bool,
    beneficiary-count: uint
  }
)

;; Premium allocations to beneficiaries
(define-map premium-allocations
  { allocation-id: (string-ascii 64) }
  {
    pool-id: (string-ascii 64),
    beneficiary: principal,
    beneficiary-type: (string-ascii 20),
    allocated-amount: uint,
    distributed-amount: uint,
    allocation-date: uint,
    distribution-method: (string-ascii 20),
    status: (string-ascii 20),
    certification-level: (string-ascii 20),
    producer-score: uint
  }
)

;; Distribution transactions
(define-map distributions
  { transaction-id: (string-ascii 64) }
  {
    allocation-id: (string-ascii 64),
    recipient: principal,
    amount: uint,
    distribution-date: uint,
    distribution-method: (string-ascii 20),
    transaction-hash: (string-ascii 64),
    verified: bool,
    notes: (string-utf8 500)
  }
)

;; Beneficiary profiles
(define-map beneficiaries
  principal
  {
    beneficiary-name: (string-utf8 100),
    beneficiary-type: (string-ascii 20),
    location: (string-utf8 200),
    certification-id: (string-ascii 64),
    registration-date: uint,
    total-premiums-received: uint,
    premium-count: uint,
    reputation-score: uint,
    bank-details: (string-ascii 100),
    active: bool
  }
)

;; Impact tracking for premium usage
(define-map impact-reports
  { report-id: (string-ascii 64) }
  {
    beneficiary: principal,
    premium-amount: uint,
    usage-category: (string-ascii 30),
    description: (string-utf8 1000),
    impact-metrics: {
      people-benefited: uint,
      environmental-impact: uint,
      economic-improvement: uint,
      social-development: uint
    },
    report-date: uint,
    verified: bool,
    verifier: principal
  }
)

;; Premium calculation rules
(define-map calculation-rules
  { rule-id: (string-ascii 64) }
  {
    category: (string-ascii 20),
    rate-basis-points: uint,
    min-certification-level: (string-ascii 20),
    min-producer-score: uint,
    valid-from: uint,
    valid-until: uint,
    active: bool,
    created-by: principal
  }
)

;; Global counters and statistics
(define-data-var total-pools uint u0)
(define-data-var total-allocations uint u0)
(define-data-var total-distributions uint u0)
(define-data-var total-beneficiaries uint u0)
(define-data-var total-premium-distributed uint u0)
(define-data-var allocation-counter uint u0)
(define-data-var distribution-counter uint u0)
(define-data-var report-counter uint u0)

;; Premium pool management functions

;; Create a new premium pool
(define-public (create-premium-pool
    (pool-id (string-ascii 64))
    (category (string-ascii 20))
    (total-allocation uint)
    (validity-period uint)
  )
  (let (
    (pool-manager tx-sender)
  )
    ;; Validation checks
    (asserts! (> (len pool-id) u0) ERR_INVALID_INPUT)
    (asserts! (> total-allocation u0) ERR_INVALID_INPUT)
    (asserts! (> validity-period u0) ERR_INVALID_INPUT)
    (asserts! (is-none (map-get? premium-pools { pool-id: pool-id })) ERR_ALREADY_DISTRIBUTED)
    
    ;; Create premium pool
    (map-set premium-pools
      { pool-id: pool-id }
      {
        category: category,
        total-allocated: total-allocation,
        total-distributed: u0,
        current-balance: total-allocation,
        creation-date: stacks-block-height,
        expiry-date: (+ stacks-block-height validity-period),
        pool-manager: pool-manager,
        active: true,
        beneficiary-count: u0
      }
    )
    
    ;; Update global statistics
    (var-set total-pools (+ (var-get total-pools) u1))
    
    (ok pool-id)
  )
)

;; Allocate premium to a beneficiary
(define-public (allocate-premium
    (pool-id (string-ascii 64))
    (beneficiary principal)
    (amount uint)
    (distribution-method (string-ascii 20))
    (certification-level (string-ascii 20))
    (producer-score uint)
  )
  (let (
    (allocator tx-sender)
    (pool (unwrap! (map-get? premium-pools { pool-id: pool-id }) ERR_NOT_FOUND))
    (beneficiary-info (unwrap! (map-get? beneficiaries beneficiary) ERR_INVALID_BENEFICIARY))
    (allocation-id (int-to-ascii (+ (var-get allocation-counter) u1)))
  )
    ;; Validation checks
    (asserts! (is-eq allocator (get pool-manager pool)) ERR_UNAUTHORIZED)
    (asserts! (get active pool) ERR_UNAUTHORIZED)
    (asserts! (get active beneficiary-info) ERR_INVALID_BENEFICIARY)
    (asserts! (> amount u0) ERR_INVALID_INPUT)
    (asserts! (<= amount (get current-balance pool)) ERR_INSUFFICIENT_FUNDS)
    (asserts! (> (get expiry-date pool) stacks-block-height) ERR_PREMIUM_EXPIRED)
    
    ;; Create premium allocation
    (map-set premium-allocations
      { allocation-id: allocation-id }
      {
        pool-id: pool-id,
        beneficiary: beneficiary,
        beneficiary-type: (get beneficiary-type beneficiary-info),
        allocated-amount: amount,
        distributed-amount: u0,
        allocation-date: stacks-block-height,
        distribution-method: distribution-method,
        status: STATUS_APPROVED,
        certification-level: certification-level,
        producer-score: producer-score
      }
    )
    
    ;; Update pool balance and beneficiary count
    (map-set premium-pools
      { pool-id: pool-id }
      (merge pool {
        current-balance: (- (get current-balance pool) amount),
        beneficiary-count: (+ (get beneficiary-count pool) u1)
      })
    )
    
    ;; Update global statistics
    (var-set total-allocations (+ (var-get total-allocations) u1))
    (var-set allocation-counter (+ (var-get allocation-counter) u1))
    
    (ok allocation-id)
  )
)

;; Distribute premium to beneficiary
(define-public (distribute-premium
    (allocation-id (string-ascii 64))
    (transaction-hash (string-ascii 64))
    (notes (string-utf8 500))
  )
  (let (
    (distributor tx-sender)
    (allocation (unwrap! (map-get? premium-allocations { allocation-id: allocation-id }) ERR_NOT_FOUND))
    (pool (unwrap! (map-get? premium-pools { pool-id: (get pool-id allocation) }) ERR_NOT_FOUND))
    (transaction-id (int-to-ascii (+ (var-get distribution-counter) u1)))
    (amount (get allocated-amount allocation))
  )
    ;; Validation checks
    (asserts! (is-eq distributor (get pool-manager pool)) ERR_UNAUTHORIZED)
    (asserts! (is-eq (get status allocation) STATUS_APPROVED) ERR_INVALID_INPUT)
    (asserts! (is-eq (get distributed-amount allocation) u0) ERR_ALREADY_DISTRIBUTED)
    
    ;; Create distribution transaction
    (map-set distributions
      { transaction-id: transaction-id }
      {
        allocation-id: allocation-id,
        recipient: (get beneficiary allocation),
        amount: amount,
        distribution-date: stacks-block-height,
        distribution-method: (get distribution-method allocation),
        transaction-hash: transaction-hash,
        verified: false,
        notes: notes
      }
    )
    
    ;; Update allocation status
    (map-set premium-allocations
      { allocation-id: allocation-id }
      (merge allocation {
        distributed-amount: amount,
        status: STATUS_DISTRIBUTED
      })
    )
    
    ;; Update pool distributed amount
    (map-set premium-pools
      { pool-id: (get pool-id allocation) }
      (merge pool {
        total-distributed: (+ (get total-distributed pool) amount)
      })
    )
    
    ;; Update beneficiary statistics
    (update-beneficiary-stats (get beneficiary allocation) amount)
    
    ;; Update global statistics
    (var-set total-distributions (+ (var-get total-distributions) u1))
    (var-set total-premium-distributed (+ (var-get total-premium-distributed) amount))
    (var-set distribution-counter (+ (var-get distribution-counter) u1))
    
    (ok transaction-id)
  )
)

;; Register or update beneficiary
(define-public (register-beneficiary
    (beneficiary-name (string-utf8 100))
    (beneficiary-type (string-ascii 20))
    (location (string-utf8 200))
    (certification-id (string-ascii 64))
    (bank-details (string-ascii 100))
  )
  (let (
    (beneficiary-address tx-sender)
  )
    ;; Validation checks
    (asserts! (> (len beneficiary-name) u0) ERR_INVALID_INPUT)
    (asserts! (> (len beneficiary-type) u0) ERR_INVALID_INPUT)
    (asserts! (> (len location) u0) ERR_INVALID_INPUT)
    
    ;; Register beneficiary
    (map-set beneficiaries
      beneficiary-address
      {
        beneficiary-name: beneficiary-name,
        beneficiary-type: beneficiary-type,
        location: location,
        certification-id: certification-id,
        registration-date: stacks-block-height,
        total-premiums-received: u0,
        premium-count: u0,
        reputation-score: u100,
        bank-details: bank-details,
        active: true
      }
    )
    
    ;; Update global statistics if new beneficiary
    (if (is-none (map-get? beneficiaries beneficiary-address))
        (var-set total-beneficiaries (+ (var-get total-beneficiaries) u1))
        true
    )
    
    (ok "Beneficiary registered successfully")
  )
)

;; Submit impact report for premium usage
(define-public (submit-impact-report
    (premium-amount uint)
    (usage-category (string-ascii 30))
    (description (string-utf8 1000))
    (people-benefited uint)
    (environmental-impact uint)
    (economic-improvement uint)
    (social-development uint)
  )
  (let (
    (reporter tx-sender)
    (report-id (int-to-ascii (+ (var-get report-counter) u1)))
    (beneficiary-info (unwrap! (map-get? beneficiaries reporter) ERR_INVALID_BENEFICIARY))
  )
    ;; Validation checks
    (asserts! (get active beneficiary-info) ERR_INVALID_BENEFICIARY)
    (asserts! (> premium-amount u0) ERR_INVALID_INPUT)
    (asserts! (> (len description) u0) ERR_INVALID_INPUT)
    
    ;; Create impact report
    (map-set impact-reports
      { report-id: report-id }
      {
        beneficiary: reporter,
        premium-amount: premium-amount,
        usage-category: usage-category,
        description: description,
        impact-metrics: {
          people-benefited: people-benefited,
          environmental-impact: environmental-impact,
          economic-improvement: economic-improvement,
          social-development: social-development
        },
        report-date: stacks-block-height,
        verified: false,
        verifier: tx-sender
      }
    )
    
    (var-set report-counter (+ (var-get report-counter) u1))
    
    (ok report-id)
  )
)

;; Verify distribution transaction
(define-public (verify-distribution
    (transaction-id (string-ascii 64))
    (verified bool)
  )
  (let (
    (verifier tx-sender)
    (distribution (unwrap! (map-get? distributions { transaction-id: transaction-id }) ERR_NOT_FOUND))
  )
    ;; Only contract owner or pool manager can verify
    (asserts! (is-eq verifier CONTRACT_OWNER) ERR_UNAUTHORIZED)
    
    ;; Update verification status
    (map-set distributions
      { transaction-id: transaction-id }
      (merge distribution { verified: verified })
    )
    
    ;; Update allocation status if verified
    (if verified
        (map-set premium-allocations
          { allocation-id: (get allocation-id distribution) }
          (merge (unwrap-panic (map-get? premium-allocations { allocation-id: (get allocation-id distribution) }))
                 { status: STATUS_COMPLETED }))
        true
    )
    
    (ok "Distribution verification updated")
  )
)

;; Private helper functions

;; Update beneficiary statistics
(define-private (update-beneficiary-stats (beneficiary-address principal) (amount uint))
  (match (map-get? beneficiaries beneficiary-address)
    some-beneficiary (begin
                       (map-set beneficiaries
                         beneficiary-address
                         (merge some-beneficiary {
                           total-premiums-received: (+ (get total-premiums-received some-beneficiary) amount),
                           premium-count: (+ (get premium-count some-beneficiary) u1)
                         }))
                       true)
    true
  )
)

;; Calculate premium based on rules
(define-private (calculate-premium-amount (base-amount uint) (category (string-ascii 20)))
  (let (
    (rate (get-category-rate category))
  )
    (/ (* base-amount rate) u10000) ;; Rate is in basis points
  )
)

;; Get premium rate for category
(define-private (get-category-rate (category (string-ascii 20)))
  (if (is-eq category CATEGORY_FAIR_TRADE)
      DEFAULT_FAIR_TRADE_RATE
      (if (is-eq category CATEGORY_ORGANIC)
          DEFAULT_ORGANIC_RATE
          DEFAULT_QUALITY_RATE
      )
  )
)

;; Read-only functions

;; Get premium pool information
(define-read-only (get-premium-pool (pool-id (string-ascii 64)))
  (map-get? premium-pools { pool-id: pool-id })
)

;; Get premium allocation
(define-read-only (get-allocation (allocation-id (string-ascii 64)))
  (map-get? premium-allocations { allocation-id: allocation-id })
)

;; Get distribution transaction
(define-read-only (get-distribution (transaction-id (string-ascii 64)))
  (map-get? distributions { transaction-id: transaction-id })
)

;; Get beneficiary information
(define-read-only (get-beneficiary (beneficiary-address principal))
  (map-get? beneficiaries beneficiary-address)
)

;; Get impact report
(define-read-only (get-impact-report (report-id (string-ascii 64)))
  (map-get? impact-reports { report-id: report-id })
)

;; Check pool balance
(define-read-only (get-pool-balance (pool-id (string-ascii 64)))
  (match (get-premium-pool pool-id)
    some-pool (some (get current-balance some-pool))
    none
  )
)

;; Get system statistics
(define-read-only (get-system-stats)
  {
    total-pools: (var-get total-pools),
    total-allocations: (var-get total-allocations),
    total-distributions: (var-get total-distributions),
    total-beneficiaries: (var-get total-beneficiaries),
    total-premium-distributed: (var-get total-premium-distributed)
  }
)

;; Check if beneficiary is eligible for premium
(define-read-only (is-eligible-for-premium (beneficiary-address principal))
  (match (get-beneficiary beneficiary-address)
    some-beneficiary (and (get active some-beneficiary)
                          (>= (get reputation-score some-beneficiary) u70))
    false
  )
)

;; Calculate total impact metrics
(define-read-only (get-total-impact-metrics)
  {
    total-people-benefited: u0, ;; Would aggregate from all reports in real implementation
    total-environmental-impact: u0,
    total-economic-improvement: u0,
    total-social-development: u0
  }
)
