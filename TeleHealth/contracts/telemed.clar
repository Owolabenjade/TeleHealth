;; Smart Contract: Decentralized Telemedicine and Prescription Management Platform
;; Description: A secure telemedicine platform with token payment support

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
        ;; Get the token symbol
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

;; Consultation and Prescription ID Counters
(define-data-var consultation-id-counter uint u0)
(define-data-var prescription-id-counter uint u0)
(define-data-var payment-id-counter uint u0)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Utility Functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Contract Owner Functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-public (set-token-contract (new-token-contract principal))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
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
        (asserts! (or (is-eq role "patient") (is-eq role "doctor") (is-eq role "pharmacy")) ERR-INVALID-ROLE)
        (asserts! (not (is-user-registered tx-sender)) ERR-ALREADY-EXISTS)
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
        (let ((existing (map-get? access-control {patient-id: tx-sender, authorized: grantee})))
            (asserts! (is-some existing) ERR-NOT-FOUND)
            (ok (map-delete access-control {patient-id: tx-sender, authorized: grantee}))
        )
    )
)

;; Schedule a Consultation
(define-public (schedule-consultation (doctor principal))
    (begin
        (try! (assert-is-patient tx-sender))
        (try! (assert-is-doctor doctor))
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

;; Record Consultation Notes (Off-chain Data Hash)
(define-public (record-consultation-notes (consultation-id uint) (notes-hash (string-ascii 64)))
    (begin
        (try! (assert-is-doctor tx-sender))
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
        (try! (assert-is-patient patient))
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
        (try! (assert-is-pharmacy pharmacy))
        (let ((prescription (unwrap! (map-get? prescriptions {prescription-id: prescription-id}) ERR-NOT-FOUND)))
            (asserts! (is-eq tx-sender (get patient prescription)) ERR-NOT-AUTHORIZED)
            (asserts! (is-none (get pharmacy prescription)) ERR-OPERATION-FAILED)
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
        (let ((prescription (unwrap! (map-get? prescriptions {prescription-id: prescription-id}) ERR-NOT-FOUND)))
            (asserts! (is-eq (get pharmacy prescription) (some tx-sender)) ERR-NOT-AUTHORIZED)
            (asserts! (not (get is-dispensed prescription)) ERR-OPERATION-FAILED)
            (ok (map-set prescriptions 
                {prescription-id: prescription-id}
                (merge prescription {is-dispensed: true})))
        )
    )
)

;; Update Medical Record (Off-chain Data Hash)
(define-public (update-medical-record (data-hash (string-ascii 64)))
    (begin
        (try! (assert-is-patient tx-sender))
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
        (asserts! (is-eq (contract-of ft) (var-get payment-token-contract)) ERR-NOT-AUTHORIZED)
        (let 
            ((payment-id (increment-payment-id)))
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