;; title: producer-verification
;; version: 1.0.0
;; summary: Verify and certify ethical production practices for fair trade compliance
;; description: This contract manages producer certification, compliance tracking, and verification processes
;;              to ensure ethical production standards are met and maintained.

;; Error constants
(define-constant ERR_UNAUTHORIZED (err u100))
(define-constant ERR_NOT_FOUND (err u101))
(define-constant ERR_ALREADY_EXISTS (err u102))
(define-constant ERR_INVALID_INPUT (err u103))
(define-constant ERR_CERTIFICATION_EXPIRED (err u104))
(define-constant ERR_INSUFFICIENT_SCORE (err u105))
(define-constant ERR_PENDING_AUDIT (err u106))

;; Certification status constants
(define-constant STATUS_PENDING "PENDING")
(define-constant STATUS_ACTIVE "ACTIVE")
(define-constant STATUS_EXPIRED "EXPIRED")
(define-constant STATUS_SUSPENDED "SUSPENDED")
(define-constant STATUS_REVOKED "REVOKED")

;; Audit type constants
(define-constant AUDIT_INITIAL "INITIAL")
(define-constant AUDIT_RENEWAL "RENEWAL")
(define-constant AUDIT_COMPLIANCE "COMPLIANCE")
(define-constant AUDIT_SPOT_CHECK "SPOT_CHECK")

;; Certification level constants
(define-constant LEVEL_BRONZE "BRONZE")
(define-constant LEVEL_SILVER "SILVER")
(define-constant LEVEL_GOLD "GOLD")
(define-constant LEVEL_PLATINUM "PLATINUM")

;; Minimum scores for certification levels
(define-constant MIN_BRONZE_SCORE u60)
(define-constant MIN_SILVER_SCORE u75)
(define-constant MIN_GOLD_SCORE u85)
(define-constant MIN_PLATINUM_SCORE u95)

;; Certification validity period (blocks)
(define-constant CERTIFICATION_VALIDITY u52560) ;; ~1 year

;; Contract owner for administrative functions
(define-constant CONTRACT_OWNER tx-sender)

;; Data structures

;; Producer registry with basic information
(define-map producers
  { producer-id: (string-ascii 64) }
  {
    name: (string-utf8 100),
    location: (string-utf8 200),
    contact-info: (string-utf8 300),
    registration-date: uint,
    producer-type: (string-ascii 50),
    size-category: (string-ascii 20),
    registration-status: (string-ascii 20),
    registered-by: principal
  }
)

;; Certification records
(define-map certifications
  { producer-id: (string-ascii 64) }
  {
    certification-id: (string-ascii 64),
    certification-level: (string-ascii 20),
    issue-date: uint,
    expiry-date: uint,
    status: (string-ascii 20),
    overall-score: uint,
    audit-count: uint,
    last-audit-date: uint,
    certified-by: principal
  }
)

;; Audit records
(define-map audit-records
  { audit-id: (string-ascii 64) }
  {
    producer-id: (string-ascii 64),
    audit-type: (string-ascii 20),
    audit-date: uint,
    auditor: principal,
    labor-score: uint,
    environmental-score: uint,
    social-score: uint,
    economic-score: uint,
    overall-score: uint,
    findings: (string-utf8 1000),
    recommendations: (string-utf8 1000),
    next-audit-due: uint
  }
)

;; Compliance violations
(define-map violations
  { violation-id: (string-ascii 64) }
  {
    producer-id: (string-ascii 64),
    violation-type: (string-ascii 50),
    severity: (string-ascii 10),
    description: (string-utf8 500),
    reported-date: uint,
    status: (string-ascii 20),
    corrective-action: (string-utf8 500),
    resolution-date: uint,
    reported-by: principal
  }
)

;; Authorized auditors
(define-map authorized-auditors
  principal
  {
    auditor-name: (string-utf8 100),
    credentials: (string-utf8 300),
    authorization-date: uint,
    active: bool,
    audit-count: uint,
    specializations: (list 10 (string-ascii 50))
  }
)

;; Global counters and statistics
(define-data-var total-producers uint u0)
(define-data-var total-certifications uint u0)
(define-data-var total-audits uint u0)
(define-data-var total-violations uint u0)
(define-data-var audit-counter uint u0)
(define-data-var violation-counter uint u0)

;; Producer registration and management functions

;; Register a new producer
(define-public (register-producer
    (producer-id (string-ascii 64))
    (name (string-utf8 100))
    (location (string-utf8 200))
    (contact-info (string-utf8 300))
    (producer-type (string-ascii 50))
    (size-category (string-ascii 20))
  )
  (let (
    (registrant tx-sender)
  )
    ;; Validation checks
    (asserts! (> (len producer-id) u0) ERR_INVALID_INPUT)
    (asserts! (> (len name) u0) ERR_INVALID_INPUT)
    (asserts! (> (len location) u0) ERR_INVALID_INPUT)
    (asserts! (is-none (map-get? producers { producer-id: producer-id })) ERR_ALREADY_EXISTS)
    
    ;; Register the producer
    (map-set producers
      { producer-id: producer-id }
      {
        name: name,
        location: location,
        contact-info: contact-info,
        registration-date: stacks-block-height,
        producer-type: producer-type,
        size-category: size-category,
        registration-status: STATUS_PENDING,
        registered-by: registrant
      }
    )
    
    ;; Update global statistics
    (var-set total-producers (+ (var-get total-producers) u1))
    
    (ok "Producer registered successfully")
  )
)

;; Update producer information
(define-public (update-producer-info
    (producer-id (string-ascii 64))
    (name (string-utf8 100))
    (location (string-utf8 200))
    (contact-info (string-utf8 300))
  )
  (let (
    (producer (unwrap! (map-get? producers { producer-id: producer-id }) ERR_NOT_FOUND))
  )
    ;; Check authorization (producer owner or admin)
    (asserts! (or (is-eq tx-sender (get registered-by producer))
                  (is-eq tx-sender CONTRACT_OWNER)) ERR_UNAUTHORIZED)
    
    ;; Update producer information
    (map-set producers
      { producer-id: producer-id }
      (merge producer {
        name: name,
        location: location,
        contact-info: contact-info
      })
    )
    
    (ok "Producer information updated")
  )
)

;; Audit and certification functions

;; Conduct an audit for a producer
(define-public (conduct-audit
    (producer-id (string-ascii 64))
    (audit-type (string-ascii 20))
    (labor-score uint)
    (environmental-score uint)
    (social-score uint)
    (economic-score uint)
    (findings (string-utf8 1000))
    (recommendations (string-utf8 1000))
  )
  (let (
    (auditor tx-sender)
    (audit-id (int-to-ascii (+ (var-get audit-counter) u1)))
    (overall-score (/ (+ labor-score environmental-score social-score economic-score) u4))
    (producer (unwrap! (map-get? producers { producer-id: producer-id }) ERR_NOT_FOUND))
    (auditor-info (unwrap! (map-get? authorized-auditors auditor) ERR_UNAUTHORIZED))
  )
    ;; Validation checks
    (asserts! (get active auditor-info) ERR_UNAUTHORIZED)
    (asserts! (<= labor-score u100) ERR_INVALID_INPUT)
    (asserts! (<= environmental-score u100) ERR_INVALID_INPUT)
    (asserts! (<= social-score u100) ERR_INVALID_INPUT)
    (asserts! (<= economic-score u100) ERR_INVALID_INPUT)
    
    ;; Create audit record
    (map-set audit-records
      { audit-id: audit-id }
      {
        producer-id: producer-id,
        audit-type: audit-type,
        audit-date: stacks-block-height,
        auditor: auditor,
        labor-score: labor-score,
        environmental-score: environmental-score,
        social-score: social-score,
        economic-score: economic-score,
        overall-score: overall-score,
        findings: findings,
        recommendations: recommendations,
        next-audit-due: (+ stacks-block-height CERTIFICATION_VALIDITY)
      }
    )
    
    ;; Update producer status based on audit
    (update-producer-certification producer-id overall-score)
    
    ;; Update auditor statistics
    (map-set authorized-auditors
      auditor
      (merge auditor-info {
        audit-count: (+ (get audit-count auditor-info) u1)
      })
    )
    
    ;; Update global counters
    (var-set total-audits (+ (var-get total-audits) u1))
    (var-set audit-counter (+ (var-get audit-counter) u1))
    
    (ok audit-id)
  )
)

;; Issue or update certification based on audit score
(define-private (update-producer-certification (producer-id (string-ascii 64)) (score uint))
  (let (
    (certification-level (determine-certification-level score))
    (existing-cert (map-get? certifications { producer-id: producer-id }))
    (certification-id (if (is-some existing-cert)
                         (get certification-id (unwrap-panic existing-cert))
                         ""))
  )
    (if (>= score MIN_BRONZE_SCORE)
        ;; Issue new certification or update existing
        (map-set certifications
          { producer-id: producer-id }
          {
            certification-id: (if (is-eq certification-id "") 
                                 (int-to-ascii (+ (var-get total-certifications) u1))
                                 certification-id),
            certification-level: certification-level,
            issue-date: stacks-block-height,
            expiry-date: (+ stacks-block-height CERTIFICATION_VALIDITY),
            status: STATUS_ACTIVE,
            overall-score: score,
            audit-count: (+ (if (is-some existing-cert)
                               (get audit-count (unwrap-panic existing-cert))
                               u0) u1),
            last-audit-date: stacks-block-height,
            certified-by: tx-sender
          }
        )
        ;; Score too low for certification
        (map-set producers
          { producer-id: producer-id }
          (merge (unwrap-panic (map-get? producers { producer-id: producer-id })) {
            registration-status: STATUS_PENDING
          })
        )
    )
    
    ;; Update certification counter if new certification
    (if (and (>= score MIN_BRONZE_SCORE) (is-eq certification-id ""))
        (var-set total-certifications (+ (var-get total-certifications) u1))
        true
    )
    
    true
  )
)

;; Determine certification level based on score
(define-private (determine-certification-level (score uint))
  (if (>= score MIN_PLATINUM_SCORE)
      LEVEL_PLATINUM
      (if (>= score MIN_GOLD_SCORE)
          LEVEL_GOLD
          (if (>= score MIN_SILVER_SCORE)
              LEVEL_SILVER
              LEVEL_BRONZE
          )
      )
  )
)

;; Administrative functions

;; Authorize a new auditor
(define-public (authorize-auditor
    (auditor principal)
    (auditor-name (string-utf8 100))
    (credentials (string-utf8 300))
    (specializations (list 10 (string-ascii 50)))
  )
  (begin
    (asserts! (is-eq tx-sender CONTRACT_OWNER) ERR_UNAUTHORIZED)
    (asserts! (is-none (map-get? authorized-auditors auditor)) ERR_ALREADY_EXISTS)
    
    (map-set authorized-auditors
      auditor
      {
        auditor-name: auditor-name,
        credentials: credentials,
        authorization-date: stacks-block-height,
        active: true,
        audit-count: u0,
        specializations: specializations
      }
    )
    
    (ok "Auditor authorized successfully")
  )
)

;; Report a compliance violation
(define-public (report-violation
    (producer-id (string-ascii 64))
    (violation-type (string-ascii 50))
    (severity (string-ascii 10))
    (description (string-utf8 500))
  )
  (let (
    (reporter tx-sender)
    (violation-id (int-to-ascii (+ (var-get violation-counter) u1)))
    (producer (unwrap! (map-get? producers { producer-id: producer-id }) ERR_NOT_FOUND))
  )
    ;; Validation checks
    (asserts! (> (len producer-id) u0) ERR_INVALID_INPUT)
    (asserts! (> (len violation-type) u0) ERR_INVALID_INPUT)
    (asserts! (> (len description) u0) ERR_INVALID_INPUT)
    
    ;; Create violation record
    (map-set violations
      { violation-id: violation-id }
      {
        producer-id: producer-id,
        violation-type: violation-type,
        severity: severity,
        description: description,
        reported-date: stacks-block-height,
        status: STATUS_PENDING,
        corrective-action: u"",
        resolution-date: u0,
        reported-by: reporter
      }
    )
    
    ;; Update certification status if severe violation
    (if (is-eq severity "HIGH")
        (suspend-certification producer-id)
        true
    )
    
    ;; Update global counters
    (var-set total-violations (+ (var-get total-violations) u1))
    (var-set violation-counter (+ (var-get violation-counter) u1))
    
    (ok violation-id)
  )
)

;; Suspend a producer's certification
(define-private (suspend-certification (producer-id (string-ascii 64)))
  (match (map-get? certifications { producer-id: producer-id })
    some-cert (begin
                 (map-set certifications
                   { producer-id: producer-id }
                   (merge some-cert { status: STATUS_SUSPENDED }))
                 true)
    true
  )
)

;; Read-only functions

;; Get producer information
(define-read-only (get-producer (producer-id (string-ascii 64)))
  (map-get? producers { producer-id: producer-id })
)

;; Get certification information
(define-read-only (get-certification (producer-id (string-ascii 64)))
  (map-get? certifications { producer-id: producer-id })
)

;; Get audit record
(define-read-only (get-audit-record (audit-id (string-ascii 64)))
  (map-get? audit-records { audit-id: audit-id })
)

;; Get violation record
(define-read-only (get-violation (violation-id (string-ascii 64)))
  (map-get? violations { violation-id: violation-id })
)

;; Check if auditor is authorized
(define-read-only (is-authorized-auditor (auditor principal))
  (match (map-get? authorized-auditors auditor)
    some-auditor (get active some-auditor)
    false
  )
)

;; Check if certification is valid
(define-read-only (is-certification-valid (producer-id (string-ascii 64)))
  (match (get-certification producer-id)
    some-cert (and (is-eq (get status some-cert) STATUS_ACTIVE)
                   (> (get expiry-date some-cert) stacks-block-height))
    false
  )
)

;; Get system statistics
(define-read-only (get-system-stats)
  {
    total-producers: (var-get total-producers),
    total-certifications: (var-get total-certifications),
    total-audits: (var-get total-audits),
    total-violations: (var-get total-violations)
  }
)
