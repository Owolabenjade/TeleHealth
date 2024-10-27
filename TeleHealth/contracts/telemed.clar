;; Smart Contract: Decentralized Telemedicine and Prescription Management Platform
;; Author: [Your Name]
;; Description: A production-ready Clarity smart contract implementing a secure telemedicine platform.

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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Data Structures
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; User roles: "patient", "doctor", "pharmacy"
(define-map users
    ((user-id principal))
    (
        (role (string-ascii 10))
        (public-key (string-ascii 66)) ;; Public key for encryption
    ))

;; Medical records per patient (stored off-chain reference)
(define-map medical-records
    ((patient-id principal))
    (
        (data-hash (string-ascii 64)) ;; Hash of the off-chain data
        (updated-at uint)
    ))

;; Consultations with unique IDs
(define-map consultations
    ((consultation-id uint))
    (
        (patient principal)
        (doctor principal)
        (timestamp uint)
        (notes-hash (string-ascii 64)) ;; Hash of the consultation notes stored off-chain
    ))

;; Prescriptions with unique IDs
(define-map prescriptions
    ((prescription-id uint))
    (
        (patient principal)
        (doctor principal)
        (pharmacy (option principal))
        (medication (string-ascii 100))
        (quantity uint)
        (timestamp uint)
        (is-dispensed bool)
    ))

;; Access control list per patient
(define-map access-control
    ((patient-id principal))
    (
        (authorized-users (list 100 principal))
    ))

;; Consultation and Prescription ID Counters
(define-data-var consultation-id-counter uint u0)
(define-data-var prescription-id-counter uint u0)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Utility Functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

(define-private (is-user-registered (user principal))
    (is-some (map-get? users { user-id: user }))
)

(define-private (get-user-role (user principal))
    (get role (unwrap-panic (map-get users { user-id: user })))
)

(define-private (assert-is-patient (user principal))
    (begin
        (asserts! (is-eq (get-user-role user) "patient") ERR-NOT-PATIENT)
        true
    )
)

(define-private (assert-is-doctor (user principal))
    (begin
        (asserts! (is-eq (get-user-role user) "doctor") ERR-NOT-DOCTOR)
        true
    )
)

(define-private (assert-is-pharmacy (user principal))
    (begin
        (asserts! (is-eq (get-user-role user) "pharmacy") ERR-NOT-PHARMACY)
        true
    )
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

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Public Functions
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; User Registration with Public Key for Encryption
(define-public (register (role (string-ascii 10)) (public-key (string-ascii 66)))
    (begin
        ;; Validate role
        (asserts! (or (is-eq role "patient") (is-eq role "doctor") (is-eq role "pharmacy")) ERR-INVALID-ROLE)
        ;; Check if user is already registered
        (asserts! (not (is-user-registered tx-sender)) ERR-ALREADY-EXISTS)
        ;; Register user
        (map-set users { user-id: tx-sender } { role: role, public-key: public-key })
        ;; For patients, initialize access control list
        (if (is-eq role "patient")
            (map-set access-control { patient-id: tx-sender } { authorized-users: [] })
            none
        )
        (ok true)
    )
)

;; Grant Access to Medical Data
(define-public (grant-access (grantee principal))
    (begin
        (assert-is-patient tx-sender)
        (asserts! (is-user-registered grantee) ERR-NOT-FOUND)
        ;; Update access control list
        (let ((current-list (get authorized-users (unwrap-panic (map-get access-control { patient-id: tx-sender })))))
            (asserts! (not (contains? current-list grantee)) ERR-ALREADY-EXISTS)
            (map-set access-control { patient-id: tx-sender } { authorized-users: (append current-list (list grantee)) })
        )
        (ok true)
    )
)

;; Revoke Access to Medical Data
(define-public (revoke-access (grantee principal))
    (begin
        (assert-is-patient tx-sender)
        ;; Update access control list
        (let ((current-list (get authorized-users (unwrap-panic (map-get access-control { patient-id: tx-sender })))))
            (asserts! (contains? current-list grantee) ERR-NOT-FOUND)
            (map-set access-control { patient-id: tx-sender } { authorized-users: (filter (lambda (x) (not (is-eq x grantee))) current-list) })
        )
        (ok true)
    )
)

;; Schedule a Consultation
(define-public (schedule-consultation (doctor principal))
    (begin
        (assert-is-patient tx-sender)
        (assert-is-doctor doctor)
        ;; Increment consultation ID
        (let ((consultation-id (increment-consultation-id)))
            ;; Create consultation record with off-chain notes reference
            (map-set consultations { consultation-id: consultation-id } {
                patient: tx-sender,
                doctor: doctor,
                timestamp: block-height,
                notes-hash: ""
            })
            ;; Grant doctor access to patient's data
            (begin
                (let ((current-list (get authorized-users (unwrap-panic (map-get access-control { patient-id: tx-sender })))))
                    (if (contains? current-list doctor)
                        true
                        (map-set access-control { patient-id: tx-sender } { authorized-users: (append current-list (list doctor)) })
                    )
                )
            )
            (ok consultation-id)
        )
    )
)

;; Record Consultation Notes (Off-chain Data Hash)
(define-public (record-consultation-notes (consultation-id uint) (notes-hash (string-ascii 64)))
    (begin
        (assert-is-doctor tx-sender)
        (let ((consultation (unwrap! (map-get consultations { consultation-id: consultation-id }) ERR-NOT-FOUND)))
            (asserts! (is-eq tx-sender (get doctor consultation)) ERR-NOT-AUTHORIZED)
            ;; Update consultation with notes hash
            (map-set consultations { consultation-id: consultation-id } (merge consultation { notes-hash: notes-hash }))
            (ok true)
        )
    )
)

;; Issue a Prescription
(define-public (issue-prescription (patient principal) (medication (string-ascii 100)) (quantity uint))
    (begin
        (assert-is-doctor tx-sender)
        (assert-is-patient patient)
        ;; Increment prescription ID
        (let ((prescription-id (increment-prescription-id)))
            ;; Create prescription record
            (map-set prescriptions { prescription-id: prescription-id } {
                patient: patient,
                doctor: tx-sender,
                pharmacy: none,
                medication: medication,
                quantity: quantity,
                timestamp: block-height,
                is-dispensed: false
            })
            (ok prescription-id)
        )
    )
)

;; Patient Selects a Pharmacy
(define-public (select-pharmacy (prescription-id uint) (pharmacy principal))
    (begin
        (assert-is-patient tx-sender)
        (assert-is-pharmacy pharmacy)
        (let ((prescription (unwrap! (map-get prescriptions { prescription-id: prescription-id }) ERR-NOT-FOUND)))
            (asserts! (is-eq tx-sender (get patient prescription)) ERR-NOT-AUTHORIZED)
            (asserts! (is-none (get pharmacy prescription)) ERR-OPERATION-FAILED)
            ;; Update prescription with selected pharmacy
            (map-set prescriptions { prescription-id: prescription-id } (merge prescription { pharmacy: (some pharmacy) }))
            (ok true)
        )
    )
)

;; Pharmacy Dispenses Medication
(define-public (dispense-medication (prescription-id uint))
    (begin
        (assert-is-pharmacy tx-sender)
        (let ((prescription (unwrap! (map-get prescriptions { prescription-id: prescription-id }) ERR-NOT-FOUND)))
            (asserts! (is-eq (some tx-sender) (get pharmacy prescription)) ERR-NOT-AUTHORIZED)
            (asserts! (not (get is-dispensed prescription)) ERR-OPERATION-FAILED)
            ;; Update prescription status
            (map-set prescriptions { prescription-id: prescription-id } (merge prescription { is-dispensed: true }))
            (ok true)
        )
    )
)

;; Update Medical Record (Off-chain Data Hash)
(define-public (update-medical-record (data-hash (string-ascii 64)))
    (begin
        (assert-is-patient tx-sender)
        ;; Update medical record with new data hash
        (map-set medical-records { patient-id: tx-sender } {
            data-hash: data-hash,
            updated-at: block-height
        })
        (ok true)
    )
)

;; Get Medical Record (Off-chain Data Reference)
(define-read-only (get-medical-record (patient principal))
    (begin
        (let ((access-list (get authorized-users (unwrap-panic (map-get access-control { patient-id: patient })))))
            (if (or (is-eq tx-sender patient) (contains? access-list tx-sender))
                (ok (map-get medical-records { patient-id: patient }))
                ERR-PERMISSION-DENIED
            )
        )
    )
)

;; Payment Handling (Using SIP-010 Token Standard)
;; Assuming a token contract exists at .token-contract with a function transfer(amount, sender, recipient)
(define-public (make-payment (amount uint, recipient principal))
    (begin
        (asserts! (> amount u0) ERR-INVALID-INPUT)
        ;; Call the token contract to transfer tokens
        (let ((response (as-contract (contract-call? .token-contract transfer amount tx-sender recipient))))
            (if (is-ok response)
                (ok true)
                ERR-OPERATION-FAILED
            )
        )
    )
)

;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;
;; Compliance and Security Enhancements
;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;;

;; Event Logging for Auditability
(begin
    (print { event: "Contract Initialized", timestamp: block-height })
)