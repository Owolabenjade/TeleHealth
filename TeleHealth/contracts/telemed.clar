;; Smart Contract: Decentralized Telemedicine and Prescription Management Platform


;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Constants and Error Codes
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-constant ERR-NOT-AUTHORIZED (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-ALREADY-EXISTS (err u102))
(define-constant ERR-PERMISSION-DENIED (err u103))
(define-constant ERR-INVALID-ROLE (err u104))
(define-constant ERR-INVALID-INPUT (err u105))
(define-constant ERR-OPERATION-FAILED (err u106))
(define-constant ERR-NOT-PATIENT (err u107))
(define-constant ERR-NOT-DOCTOR (err u108))
(define-constant ERR-NOT-PHARMACY (err u109))
(define-constant ERR-DATA-EXISTS (err u110))
(define-constant ERR-RATE-LIMIT (err u111))
(define-constant ERR-EXPIRED (err u112))

;; Token constants
(define-constant CONTRACT-OWNER tx-sender)

;; Define SIP-010 fungible token trait interface
(define-trait ft-trait
    (
        ;; Transfer from the caller to a new principal
        (transfer (uint principal principal (optional (buff 34))) (response bool uint))
        ;; Get the token balance of the specified principal
        (get-balance (principal) (response uint uint))
        ;; Get the total number of tokens
        (get-total-supply () (response uint uint))
        ;; Get the token uri
        (get-token-uri () (response (optional (string-utf8 256)) uint))
        ;; Get the token decimals
        (get-decimals () (response uint uint))
        ;; Get the token name
        (get-name () (response (string-ascii 32) uint))
        ;; Get the symbol
        (get-symbol () (response (string-ascii 32) uint))
    )
)

;; Token contract variable
(define-data-var payment-token-contract principal 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.token-contract)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Data Structures
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; User roles: "patient", "doctor", "pharmacy"
(define-map users 
    {user-id: principal}
    {role: (string-ascii 10),
     public-key: (string-ascii 66)}
)

;; Medical records per patient (stored off-chain reference)
(define-map medical-records 
    {patient-id: principal}
    {data-hash: (string-ascii 64),
     updated-at: uint}
)

;; Consultations with unique IDs
(define-map consultations 
    {consultation-id: uint}
    {patient: principal,
     doctor: principal,
     timestamp: uint,
     notes-hash: (string-ascii 64)}
)

;; Prescriptions with unique IDs
(define-map prescriptions 
    {prescription-id: uint}
    {patient: principal,
     doctor: principal,
     pharmacy: (optional principal),
     medication: (string-ascii 100),
     quantity: uint,
     timestamp: uint,
     is-dispensed: bool}
)

;; Access control map: patient grants access to authorized users
(define-map access-control 
    {patient-id: principal, 
     authorized: principal}
    {granted: bool}
)

;; Payment records
(define-map payments 
    {payment-id: uint}
    {payer: principal,
     recipient: principal,
     amount: uint,
     timestamp: uint}
)

;; Consultation rate limiting
(define-map consultation-rate-limit 
    {doctor: principal}
    {last-consultation: uint,
     count: uint}
)

;; Consultation and Prescription ID Counters
(define-data-var consultation-id-counter uint u0)
(define-data-var prescription-id-counter uint u0)
(define-data-var payment-id-counter uint u0)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Constants for Business Rules
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-constant MAX-QUANTITY u1000)
(define-constant MIN-QUANTITY u1)
(define-constant RATE-LIMIT-PERIOD u144)          ;; Approximately 24 hours in blocks
(define-constant MAX-CONSULTATIONS-PER-PERIOD u20)
(define-constant PRESCRIPTION-TIMEOUT u1008)      ;; Approximately 7 days in blocks

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Utility Functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-private (is-valid-id (id uint) (counter uint))
    (<= id counter)
)

(define-private (is-user-registered (user principal))
    (is-some (map-get? users {user-id: user}))
)

(define-private (get-user-role (user principal))
    (get role (unwrap-panic (map-get? users {user-id: user})))
)

(define-private (assert-is-patient (user principal))
    (ok (asserts! (is-eq (get-user-role user) "patient") ERR-NOT-PATIENT))
)

(define-private (assert-is-doctor (user principal))
    (ok (asserts! (is-eq (get-user-role user) "doctor") ERR-NOT-DOCTOR))
)

(define-private (assert-is-pharmacy (user principal))
    (ok (asserts! (is-eq (get-user-role user) "pharmacy") ERR-NOT-PHARMACY))
)

(define-private (increment-consultation-id)
    (let ((new-id (+ (var-get consultation-id-counter) u1)))
        (var-set consultation-id-counter new-id)
        new-id
    )
)

(define-private (increment-prescription-id)
    (let ((new-id (+ (var-get prescription-id-counter) u1)))
        (var-set prescription-id-counter new-id)
        new-id
    )
)

(define-private (increment-payment-id)
    (let ((new-id (+ (var-get payment-id-counter) u1)))
        (var-set payment-id-counter new-id)
        new-id
    )
)

;; Validate if the principal is marked as a contract principal
(define-private (is-valid-contract-principal (contract principal) (is-contract bool))
    (if is-contract
        true       ;; It's a contract principal as per input flag
        false      ;; Otherwise, it is a standard principal
    )
)

;; Simplified hash validation - checks length only
(define-private (is-valid-hash (hash (string-ascii 64)))
    (>= (len hash) u64)  ;; Ensure hash is exactly 64 characters
)

;; Check rate limit for consultations
(define-private (check-rate-limit (doctor principal))
    (let ((current-limit (default-to 
            {last-consultation: u0, count: u0}
            (map-get? consultation-rate-limit {doctor: doctor}))))
        (if (> (- block-height (get last-consultation current-limit)) RATE-LIMIT-PERIOD)
            (begin
                (map-set consultation-rate-limit {doctor: doctor} {last-consultation: block-height, count: u1})
                (ok true)
            )
            (if (< (get count current-limit) MAX-CONSULTATIONS-PER-PERIOD)
                (begin
                    (map-set consultation-rate-limit {doctor: doctor} {last-consultation: (get last-consultation current-limit), count: (+ (get count current-limit) u1)})
                    (ok true)
                )
                (err ERR-RATE-LIMIT)
            )
        )
    )
)

;; Check if prescription is valid (not expired)
(define-private (is-prescription-valid (prescription-id uint))
    (let ((prescription (unwrap! (map-get? prescriptions {prescription-id: prescription-id}) ERR-NOT-FOUND)))
        (asserts! (< (- block-height (get timestamp prescription)) PRESCRIPTION-TIMEOUT) ERR-EXPIRED)
        (ok prescription)
    )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Contract Owner Functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-public (set-token-contract (new-token-contract principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
        (asserts! (is-valid-contract-principal new-token-contract true) ERR-INVALID-INPUT)
        (var-set payment-token-contract new-token-contract)
        (ok true)
    )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Public Functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; User Registration with Public Key for Encryption
(define-public (register (role (string-ascii 10)) (public-key (string-ascii 66)))
    (begin
        ;; Validate role and registration status
        (asserts! (or (is-eq role "patient") (is-eq role "doctor") (is-eq role "pharmacy")) ERR-INVALID-ROLE)
        (asserts! (not (is-user-registered tx-sender)) ERR-ALREADY-EXISTS)
        ;; Check that public-key length is exactly 66
        (asserts! (is-eq (len public-key) u66) ERR-INVALID-INPUT)
        ;; Register user
        (ok (map-set users 
            {user-id: tx-sender}
            {role: role, 
             public-key: public-key}))
    )
)

;; Grant Access to Medical Data
(define-public (grant-access (grantee principal))
    (begin
        (try! (assert-is-patient tx-sender))
        (asserts! (is-user-registered grantee) ERR-NOT-FOUND)
        (let ((existing (map-get? access-control {patient-id: tx-sender, authorized: grantee})))
            (asserts! (not (is-some existing)) ERR-ALREADY-EXISTS)
            (ok (map-set access-control 
                {patient-id: tx-sender, 
                 authorized: grantee}
                {granted: true}))
        )
    )
)

;; Revoke Access to Medical Data
(define-public (revoke-access (grantee principal))
    (begin
        (try! (assert-is-patient tx-sender))
        (asserts! (is-user-registered grantee) ERR-NOT-FOUND) ;; Ensure `grantee` is a registered user
        (let ((existing (map-get? access-control {patient-id: tx-sender, authorized: grantee})))
            (asserts! (is-some existing) ERR-NOT-FOUND)
            (ok (map-delete access-control {patient-id: tx-sender, authorized: grantee}))
        )
    )
)

;; Schedule a Consultation with consistent response type
(define-public (schedule-consultation (doctor principal))
    (let ((rate-limit (unwrap! (check-rate-limit doctor) ERR-RATE-LIMIT)))
        (begin
            (try! (assert-is-patient tx-sender))
            (try! (assert-is-doctor doctor))
            (asserts! (not (is-eq doctor tx-sender)) ERR-INVALID-INPUT)
            ;; Increment consultation ID and record the consultation
            (let ((consultation-id (increment-consultation-id)))
                (map-set consultations 
                    {consultation-id: consultation-id}
                    {patient: tx-sender,
                     doctor: doctor,
                     timestamp: block-height,
                     notes-hash: ""})
                (map-set access-control 
                    {patient-id: tx-sender, 
                     authorized: doctor}
                    {granted: true})
                (ok consultation-id)
            )
        )
    )
)

;; Record Consultation Notes (Off-chain Data Hash)
(define-public (record-consultation-notes (consultation-id uint) (notes-hash (string-ascii 64)))
    (begin
        (try! (assert-is-doctor tx-sender))
        (asserts! (is-valid-hash notes-hash) ERR-INVALID-INPUT)
        ;; Add consultation ID validation
        (asserts! (<= consultation-id (var-get consultation-id-counter)) ERR-INVALID-INPUT)
        ;; Verify that consultation-id exists
        (let ((consultation (unwrap! (map-get? consultations {consultation-id: consultation-id}) ERR-NOT-FOUND)))
            (asserts! (is-eq tx-sender (get doctor consultation)) ERR-NOT-AUTHORIZED)
            (ok (map-set consultations 
                {consultation-id: consultation-id}
                (merge consultation {notes-hash: notes-hash})))
        )
    )
)

;; Issue a Prescription
(define-public (issue-prescription (patient principal) (medication (string-ascii 100)) (quantity uint))
    (begin
        (try! (assert-is-doctor tx-sender))
        (asserts! (is-user-registered patient) ERR-NOT-FOUND) ;; Ensure `patient` is registered
        (asserts! (and (>= quantity MIN-QUANTITY) (<= quantity MAX-QUANTITY)) ERR-INVALID-INPUT)
        (asserts! (> (len medication) u0) ERR-INVALID-INPUT)
        ;; Issue prescription
        (let ((prescription-id (increment-prescription-id)))
            (map-set prescriptions 
                {prescription-id: prescription-id}
                {patient: patient,
                 doctor: tx-sender,
                 pharmacy: none,
                 medication: medication,
                 quantity: quantity,
                 timestamp: block-height,
                 is-dispensed: false})
            (ok prescription-id)
        )
    )
)

;; Patient Selects a Pharmacy
(define-public (select-pharmacy (prescription-id uint) (pharmacy principal))
    (begin
        (try! (assert-is-patient tx-sender))
        ;; Add prescription ID validation
        (asserts! (<= prescription-id (var-get prescription-id-counter)) ERR-INVALID-INPUT)
        ;; Validate pharmacy before assertion
        (asserts! (is-user-registered pharmacy) ERR-NOT-FOUND)
        (try! (assert-is-pharmacy pharmacy))
        ;; Verify that prescription-id exists
        (let ((prescription (unwrap! (map-get? prescriptions {prescription-id: prescription-id}) ERR-NOT-FOUND)))
            (asserts! (is-eq tx-sender (get patient prescription)) ERR-NOT-AUTHORIZED)
            (asserts! (is-none (get pharmacy prescription)) ERR-OPERATION-FAILED)
            ;; Validate the prescription
            (unwrap! (is-prescription-valid prescription-id) ERR-EXPIRED)
            (ok (map-set prescriptions 
                {prescription-id: prescription-id}
                (merge prescription {pharmacy: (some pharmacy)})))
        )
    )
)

;; Pharmacy Dispenses Medication
(define-public (dispense-medication (prescription-id uint))
    (begin
        (try! (assert-is-pharmacy tx-sender))
        ;; Add prescription ID validation
        (asserts! (<= prescription-id (var-get prescription-id-counter)) ERR-INVALID-INPUT)
        ;; Verify that prescription-id exists
        (let ((prescription (unwrap! (map-get? prescriptions {prescription-id: prescription-id}) ERR-NOT-FOUND)))
            (asserts! (is-eq (get pharmacy prescription) (some tx-sender)) ERR-NOT-AUTHORIZED)
            (asserts! (not (get is-dispensed prescription)) ERR-OPERATION-FAILED)
            (print {event: "medication-dispensed",
                    prescription-id: prescription-id,
                    pharmacy: tx-sender,
                    patient: (get patient prescription),
                    timestamp: block-height})
            (ok (map-set prescriptions 
                {prescription-id: prescription-id}
                (merge prescription {is-dispensed: true})))
        )
    )
)

;; Medical Record (Off-chain Data Hash)
(define-public (update-medical-record (data-hash (string-ascii 64)))
    (begin
        (try! (assert-is-patient tx-sender))
        (asserts! (is-valid-hash data-hash) ERR-INVALID-INPUT)
        (ok (map-set medical-records 
            {patient-id: tx-sender}
            {data-hash: data-hash,
             updated-at: block-height}))
    )
)

;; Get Medical Record (Off-chain Data Reference)
(define-read-only (get-medical-record (patient principal))
    (if (or (is-eq tx-sender patient)
            (is-some (map-get? access-control {patient-id: patient, authorized: tx-sender})))
        (ok (map-get? medical-records {patient-id: patient}))
        ERR-PERMISSION-DENIED)
)

;; Payment Handling with SIP-010 Token Contract
(define-public (make-payment (ft <ft-trait>) (amount uint) (recipient principal))
    (begin
        (asserts! (> amount u0) ERR-INVALID-INPUT)
        (asserts! (is-user-registered recipient) ERR-NOT-FOUND) ;; Ensure `recipient` is registered
        (asserts! (is-eq (contract-of ft) (var-get payment-token-contract)) ERR-NOT-AUTHORIZED)
        ;; Payment execution
        (let ((payment-id (increment-payment-id)))
            (try! (contract-call? ft transfer amount tx-sender recipient none))
            (ok (map-set payments 
                {payment-id: payment-id}
                {payer: tx-sender,
                 recipient: recipient,
                 amount: amount,
                 timestamp: block-height}))
        )
    )
)