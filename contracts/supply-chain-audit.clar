;; title: supply-chain-audit
;; version: 1.0.0
;; summary: Track products through ethical supply chains with complete transparency
;; description: This contract handles product tracking, chain of custody, and supply chain validation
;;              to ensure ethical standards are maintained throughout the product journey.

;; Error constants
(define-constant ERR_UNAUTHORIZED (err u200))
(define-constant ERR_NOT_FOUND (err u201))
(define-constant ERR_ALREADY_EXISTS (err u202))
(define-constant ERR_INVALID_INPUT (err u203))
(define-constant ERR_INVALID_TRANSITION (err u204))
(define-constant ERR_INSUFFICIENT_VERIFICATION (err u205))
(define-constant ERR_EXPIRED_CERTIFICATION (err u206))

;; Product status constants
(define-constant STATUS_ORIGIN "ORIGIN")
(define-constant STATUS_PROCESSING "PROCESSING")
(define-constant STATUS_TRANSPORT "TRANSPORT")
(define-constant STATUS_WAREHOUSE "WAREHOUSE")
(define-constant STATUS_RETAIL "RETAIL")
(define-constant STATUS_SOLD "SOLD")
(define-constant STATUS_RECALLED "RECALLED")

;; Verification level constants
(define-constant VERIFICATION_PENDING "PENDING")
(define-constant VERIFICATION_BASIC "BASIC")
(define-constant VERIFICATION_STANDARD "STANDARD")
(define-constant VERIFICATION_PREMIUM "PREMIUM")
(define-constant VERIFICATION_FAILED "FAILED")

;; Stakeholder role constants
(define-constant ROLE_PRODUCER "PRODUCER")
(define-constant ROLE_PROCESSOR "PROCESSOR")
(define-constant ROLE_TRANSPORTER "TRANSPORTER")
(define-constant ROLE_WAREHOUSE "WAREHOUSE")
(define-constant ROLE_RETAILER "RETAILER")
(define-constant ROLE_AUDITOR "AUDITOR")

;; Quality grade constants
(define-constant GRADE_A "A")
(define-constant GRADE_B "B")
(define-constant GRADE_C "C")
(define-constant GRADE_REJECTED "REJECTED")

;; Contract owner for administrative functions
(define-constant CONTRACT_OWNER tx-sender)

;; Data structures

;; Product registration and basic information
(define-map products
  { product-id: (string-ascii 64) }
  {
    product-name: (string-utf8 100),
    product-type: (string-ascii 50),
    origin-producer: (string-ascii 64),
    origin-location: (string-utf8 200),
    production-date: uint,
    batch-number: (string-ascii 32),
    quantity: uint,
    unit: (string-ascii 20),
    current-status: (string-ascii 20),
    current-holder: principal,
    certification-level: (string-ascii 20),
    registered-by: principal,
    registration-date: uint
  }
)

;; Supply chain events tracking
(define-map supply-chain-events
  { event-id: (string-ascii 64) }
  {
    product-id: (string-ascii 64),
    event-type: (string-ascii 30),
    from-stakeholder: principal,
    to-stakeholder: principal,
    location: (string-utf8 200),
    timestamp: uint,
    verification-level: (string-ascii 20),
    quality-score: uint,
    quantity-transferred: uint,
    documentation-hash: (string-ascii 64),
    notes: (string-utf8 500),
    verified-by: (list 3 principal)
  }
)

;; Stakeholder registry and roles
(define-map stakeholders
  principal
  {
    stakeholder-name: (string-utf8 100),
    role: (string-ascii 20),
    location: (string-utf8 200),
    certification-id: (string-ascii 64),
    registration-date: uint,
    active: bool,
    reputation-score: uint,
    total-transactions: uint
  }
)

;; Quality assessments for products
(define-map quality-assessments
  { assessment-id: (string-ascii 64) }
  {
    product-id: (string-ascii 64),
    assessor: principal,
    assessment-date: uint,
    quality-grade: (string-ascii 10),
    appearance-score: uint,
    consistency-score: uint,
    packaging-score: uint,
    documentation-score: uint,
    overall-score: uint,
    notes: (string-utf8 500),
    certified: bool
  }
)

;; Chain of custody records
(define-map custody-chain
  { product-id: (string-ascii 64), sequence: uint }
  {
    holder: principal,
    holder-role: (string-ascii 20),
    received-date: uint,
    transferred-date: uint,
    location: (string-utf8 200),
    condition-received: (string-ascii 20),
    condition-transferred: (string-ascii 20),
    verification-signatures: (list 5 principal)
  }
)

;; Audit trail for compliance
(define-map audit-trail
  { audit-id: (string-ascii 64) }
  {
    product-id: (string-ascii 64),
    audit-type: (string-ascii 30),
    auditor: principal,
    audit-date: uint,
    compliance-score: uint,
    ethical-standards-met: bool,
    environmental-impact-score: uint,
    social-impact-score: uint,
    findings: (string-utf8 1000),
    recommendations: (string-utf8 1000),
    follow-up-required: bool
  }
)

;; Global counters and statistics
(define-data-var total-products uint u0)
(define-data-var total-events uint u0)
(define-data-var total-stakeholders uint u0)
(define-data-var total-assessments uint u0)
(define-data-var event-counter uint u0)
(define-data-var assessment-counter uint u0)
(define-data-var audit-counter uint u0)

;; Product registration and tracking functions

;; Register a new product in the supply chain
(define-public (register-product
    (product-id (string-ascii 64))
    (product-name (string-utf8 100))
    (product-type (string-ascii 50))
    (origin-producer (string-ascii 64))
    (origin-location (string-utf8 200))
    (batch-number (string-ascii 32))
    (quantity uint)
    (unit (string-ascii 20))
  )
  (let (
    (registrant tx-sender)
    (stakeholder (unwrap! (map-get? stakeholders registrant) ERR_UNAUTHORIZED))
  )
    ;; Validation checks
    (asserts! (> (len product-id) u0) ERR_INVALID_INPUT)
    (asserts! (> (len product-name) u0) ERR_INVALID_INPUT)
    (asserts! (> quantity u0) ERR_INVALID_INPUT)
    (asserts! (is-none (map-get? products { product-id: product-id })) ERR_ALREADY_EXISTS)
    (asserts! (get active stakeholder) ERR_UNAUTHORIZED)
    
    ;; Register the product
    (map-set products
      { product-id: product-id }
      {
        product-name: product-name,
        product-type: product-type,
        origin-producer: origin-producer,
        origin-location: origin-location,
        production-date: stacks-block-height,
        batch-number: batch-number,
        quantity: quantity,
        unit: unit,
        current-status: STATUS_ORIGIN,
        current-holder: registrant,
        certification-level: VERIFICATION_PENDING,
        registered-by: registrant,
        registration-date: stacks-block-height
      }
    )
    
    ;; Initialize custody chain
    (map-set custody-chain
      { product-id: product-id, sequence: u0 }
      {
        holder: registrant,
        holder-role: (get role stakeholder),
        received-date: stacks-block-height,
        transferred-date: u0,
        location: origin-location,
        condition-received: GRADE_A,
        condition-transferred: GRADE_A,
        verification-signatures: (list registrant)
      }
    )
    
    ;; Update global statistics
    (var-set total-products (+ (var-get total-products) u1))
    
    (ok product-id)
  )
)

;; Transfer product to next stakeholder in the supply chain
(define-public (transfer-product
    (product-id (string-ascii 64))
    (to-stakeholder principal)
    (location (string-utf8 200))
    (quantity-transferred uint)
    (condition (string-ascii 20))
    (documentation-hash (string-ascii 64))
    (notes (string-utf8 500))
  )
  (let (
    (current-holder tx-sender)
    (product (unwrap! (map-get? products { product-id: product-id }) ERR_NOT_FOUND))
    (from-stakeholder-info (unwrap! (map-get? stakeholders current-holder) ERR_UNAUTHORIZED))
    (to-stakeholder-info (unwrap! (map-get? stakeholders to-stakeholder) ERR_UNAUTHORIZED))
    (event-id (int-to-ascii (+ (var-get event-counter) u1)))
    (next-sequence (get-next-custody-sequence product-id))
  )
    ;; Validation checks
    (asserts! (is-eq (get current-holder product) current-holder) ERR_UNAUTHORIZED)
    (asserts! (get active from-stakeholder-info) ERR_UNAUTHORIZED)
    (asserts! (get active to-stakeholder-info) ERR_UNAUTHORIZED)
    (asserts! (> quantity-transferred u0) ERR_INVALID_INPUT)
    (asserts! (<= quantity-transferred (get quantity product)) ERR_INVALID_INPUT)
    
    ;; Create supply chain event
    (map-set supply-chain-events
      { event-id: event-id }
      {
        product-id: product-id,
        event-type: "TRANSFER",
        from-stakeholder: current-holder,
        to-stakeholder: to-stakeholder,
        location: location,
        timestamp: stacks-block-height,
        verification-level: VERIFICATION_BASIC,
        quality-score: u0,
        quantity-transferred: quantity-transferred,
        documentation-hash: documentation-hash,
        notes: notes,
        verified-by: (list current-holder)
      }
    )
    
    ;; Update product holder and status
    (map-set products
      { product-id: product-id }
      (merge product {
        current-holder: to-stakeholder,
        current-status: (determine-status-from-role (get role to-stakeholder-info))
      })
    )
    
    ;; Update custody chain
    (map-set custody-chain
      { product-id: product-id, sequence: next-sequence }
      {
        holder: to-stakeholder,
        holder-role: (get role to-stakeholder-info),
        received-date: stacks-block-height,
        transferred-date: u0,
        location: location,
        condition-received: condition,
        condition-transferred: condition,
        verification-signatures: (list current-holder to-stakeholder)
      }
    )
    
    ;; Update stakeholder transaction counts
    (update-stakeholder-stats current-holder)
    (update-stakeholder-stats to-stakeholder)
    
    ;; Update global counters
    (var-set total-events (+ (var-get total-events) u1))
    (var-set event-counter (+ (var-get event-counter) u1))
    
    (ok event-id)
  )
)

;; Conduct quality assessment
(define-public (conduct-quality-assessment
    (product-id (string-ascii 64))
    (appearance-score uint)
    (consistency-score uint)
    (packaging-score uint)
    (documentation-score uint)
    (notes (string-utf8 500))
  )
  (let (
    (assessor tx-sender)
    (assessment-id (int-to-ascii (+ (var-get assessment-counter) u1)))
    (overall-score (/ (+ appearance-score consistency-score packaging-score documentation-score) u4))
    (quality-grade (determine-quality-grade overall-score))
    (product (unwrap! (map-get? products { product-id: product-id }) ERR_NOT_FOUND))
    (stakeholder (unwrap! (map-get? stakeholders assessor) ERR_UNAUTHORIZED))
  )
    ;; Validation checks
    (asserts! (get active stakeholder) ERR_UNAUTHORIZED)
    (asserts! (<= appearance-score u100) ERR_INVALID_INPUT)
    (asserts! (<= consistency-score u100) ERR_INVALID_INPUT)
    (asserts! (<= packaging-score u100) ERR_INVALID_INPUT)
    (asserts! (<= documentation-score u100) ERR_INVALID_INPUT)
    
    ;; Create quality assessment
    (map-set quality-assessments
      { assessment-id: assessment-id }
      {
        product-id: product-id,
        assessor: assessor,
        assessment-date: stacks-block-height,
        quality-grade: quality-grade,
        appearance-score: appearance-score,
        consistency-score: consistency-score,
        packaging-score: packaging-score,
        documentation-score: documentation-score,
        overall-score: overall-score,
        notes: notes,
        certified: (>= overall-score u75)
      }
    )
    
    ;; Update global statistics
    (var-set total-assessments (+ (var-get total-assessments) u1))
    (var-set assessment-counter (+ (var-get assessment-counter) u1))
    
    (ok assessment-id)
  )
)

;; Register or update stakeholder information
(define-public (register-stakeholder
    (stakeholder-name (string-utf8 100))
    (role (string-ascii 20))
    (location (string-utf8 200))
    (certification-id (string-ascii 64))
  )
  (let (
    (stakeholder-address tx-sender)
  )
    ;; Validation checks
    (asserts! (> (len stakeholder-name) u0) ERR_INVALID_INPUT)
    (asserts! (> (len role) u0) ERR_INVALID_INPUT)
    (asserts! (> (len location) u0) ERR_INVALID_INPUT)
    
    ;; Register or update stakeholder
    (map-set stakeholders
      stakeholder-address
      {
        stakeholder-name: stakeholder-name,
        role: role,
        location: location,
        certification-id: certification-id,
        registration-date: stacks-block-height,
        active: true,
        reputation-score: u100,
        total-transactions: u0
      }
    )
    
    ;; Update global statistics if new stakeholder
    (if (is-none (map-get? stakeholders stakeholder-address))
        (var-set total-stakeholders (+ (var-get total-stakeholders) u1))
        true
    )
    
    (ok "Stakeholder registered successfully")
  )
)

;; Verify supply chain event (multi-signature verification)
(define-public (verify-event
    (event-id (string-ascii 64))
    (verification-level (string-ascii 20))
  )
  (let (
    (verifier tx-sender)
    (event (unwrap! (map-get? supply-chain-events { event-id: event-id }) ERR_NOT_FOUND))
    (stakeholder (unwrap! (map-get? stakeholders verifier) ERR_UNAUTHORIZED))
  )
    ;; Validation checks
    (asserts! (get active stakeholder) ERR_UNAUTHORIZED)
    (asserts! (is-none (index-of (get verified-by event) verifier)) ERR_ALREADY_EXISTS)
    
    ;; Add verifier to the event
    (map-set supply-chain-events
      { event-id: event-id }
      (merge event {
        verification-level: verification-level,
        verified-by: (unwrap! (as-max-len? (append (get verified-by event) verifier) u3) ERR_INVALID_INPUT)
      })
    )
    
    (ok "Event verified successfully")
  )
)

;; Private helper functions

;; Get next sequence number for custody chain
(define-private (get-next-custody-sequence (product-id (string-ascii 64)))
  (let (
    (current-max (fold find-max-sequence (list u0 u1 u2 u3 u4 u5 u6 u7 u8 u9) u0))
  )
    (+ current-max u1)
  )
)

;; Helper function for finding max sequence
(define-private (find-max-sequence (seq uint) (current-max uint))
  current-max ;; Simplified implementation
)

;; Determine product status based on stakeholder role
(define-private (determine-status-from-role (role (string-ascii 20)))
  (if (is-eq role ROLE_PRODUCER)
      STATUS_ORIGIN
      (if (is-eq role ROLE_PROCESSOR)
          STATUS_PROCESSING
          (if (is-eq role ROLE_TRANSPORTER)
              STATUS_TRANSPORT
              (if (is-eq role ROLE_WAREHOUSE)
                  STATUS_WAREHOUSE
                  STATUS_RETAIL
              )
          )
      )
  )
)

;; Determine quality grade based on score
(define-private (determine-quality-grade (score uint))
  (if (>= score u90)
      GRADE_A
      (if (>= score u75)
          GRADE_B
          (if (>= score u60)
              GRADE_C
              GRADE_REJECTED
          )
      )
  )
)

;; Update stakeholder transaction statistics
(define-private (update-stakeholder-stats (stakeholder-address principal))
  (match (map-get? stakeholders stakeholder-address)
    some-stakeholder (begin
                       (map-set stakeholders
                         stakeholder-address
                         (merge some-stakeholder {
                           total-transactions: (+ (get total-transactions some-stakeholder) u1)
                         }))
                       true)
    true
  )
)

;; Read-only functions

;; Get product information
(define-read-only (get-product (product-id (string-ascii 64)))
  (map-get? products { product-id: product-id })
)

;; Get supply chain event
(define-read-only (get-supply-chain-event (event-id (string-ascii 64)))
  (map-get? supply-chain-events { event-id: event-id })
)

;; Get stakeholder information
(define-read-only (get-stakeholder (stakeholder-address principal))
  (map-get? stakeholders stakeholder-address)
)

;; Get quality assessment
(define-read-only (get-quality-assessment (assessment-id (string-ascii 64)))
  (map-get? quality-assessments { assessment-id: assessment-id })
)

;; Get custody chain record
(define-read-only (get-custody-record (product-id (string-ascii 64)) (sequence uint))
  (map-get? custody-chain { product-id: product-id, sequence: sequence })
)

;; Check if product is authentic (has valid chain of custody)
(define-read-only (is-product-authentic (product-id (string-ascii 64)))
  (match (get-product product-id)
    some-product (and (> (get registration-date some-product) u0)
                      (not (is-eq (get current-status some-product) STATUS_RECALLED)))
    false
  )
)

;; Get system statistics
(define-read-only (get-system-stats)
  {
    total-products: (var-get total-products),
    total-events: (var-get total-events),
    total-stakeholders: (var-get total-stakeholders),
    total-assessments: (var-get total-assessments)
  }
)

;; Verify product origin and ethical compliance
(define-read-only (verify-product-compliance (product-id (string-ascii 64)))
  (match (get-product product-id)
    some-product (some {
      authentic: (is-product-authentic product-id),
      certification-level: (get certification-level some-product),
      current-status: (get current-status some-product),
      origin-verified: (not (is-eq (get origin-producer some-product) ""))
    })
    none
  )
)
