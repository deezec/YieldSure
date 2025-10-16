;; Parametric Crop Insurance
;; Automatic payouts based on predefined weather triggers without requiring claims

;; Insurance policies
(define-map insurance-policies
  { policy-id: uint }
  {
    policyholder: principal,
    location-id: (string-ascii 64),      ;; Geographic identifier
    crop-type: (string-ascii 32),        ;; Type of crop insured
    coverage-amount: uint,               ;; Maximum payout amount
    premium-amount: uint,                ;; Premium paid
    start-block: uint,                   ;; Block height when coverage begins
    end-block: uint,                     ;; Block height when coverage ends
    is-active: bool,                     ;; Whether policy is currently active
    drought-threshold: int,              ;; Rainfall threshold in mm below which payout triggers
    flood-threshold: int,                ;; Rainfall threshold in mm above which payout triggers
    frost-threshold: int,                ;; Temperature threshold in Celsius below which payout triggers
    payout-executed: bool,               ;; Whether a payout has been executed
    oracle-provider: principal           ;; Weather data oracle
  }
)

;; Weather data records
(define-map weather-records
  { location-id: (string-ascii 64), recorded-block: uint }
  {
    rainfall-mm: int,            ;; Rainfall in millimeters
    temperature-celsius: int,    ;; Temperature in Celsius
    humidity-percent: uint,      ;; Humidity percentage
    recorded-by: principal,      ;; Oracle that recorded data
    is-verified: bool            ;; Whether data is verified by multiple oracles
  }
)

;; Authorized weather oracles
(define-map authorized-oracles
  { oracle: principal }
  {
    oracle-name: (string-utf8 128),
    registered-at: uint,
    authorized-by: principal,
    is-active: bool
  }
)

;; Risk pools for each crop type
(define-map risk-pools
  { crop-type: (string-ascii 32) }
  {
    total-premiums: uint,        ;; Total premiums collected for this crop
    total-payouts: uint,         ;; Total payouts made
    active-policies: uint,       ;; Number of active policies
    reserve-ratio: uint,         ;; Target reserve ratio (out of 10000)
    available-funds: uint        ;; Current STX balance in the pool
  }
)

;; Next available policy ID
(define-data-var next-policy-id uint u0)

;; Protocol fees
(define-data-var protocol-fee-rate uint u500)  ;; 5% of premiums
(define-data-var protocol-treasury principal tx-sender)

;; Register an oracle provider
(define-public (authorize-oracle (oracle-name (string-utf8 128)))
  (begin
    ;; In a real implementation, this would require governance approval
    ;; Simplified for this example
    
    (map-set authorized-oracles
      { oracle: tx-sender }
      {
        oracle-name: oracle-name,
        registered-at: block-height,
        authorized-by: tx-sender,
        is-active: true
      }
    )
    
    (ok true)
  )
)

;; Check if sender is an authorized oracle
(define-private (is-authorized-oracle (oracle principal))
  (default-to 
    false 
    (get is-active (map-get? authorized-oracles { oracle: oracle }))
  )
)

;; Create a new insurance policy
(define-public (purchase-insurance
                (location-id (string-ascii 64))
                (crop-type (string-ascii 32))
                (coverage-amount uint)
                (premium-amount uint)
                (policy-duration uint)
                (drought-threshold int)
                (flood-threshold int)
                (frost-threshold int)
                (oracle-provider principal))
  (let
    ((policy-id (var-get next-policy-id))
     (start-height block-height)
     (end-height (+ block-height policy-duration))
     (protocol-fee (/ (* premium-amount (var-get protocol-fee-rate)) u10000))
     (pool-contribution (- premium-amount protocol-fee)))
    
    ;; Validate parameters
    (asserts! (> coverage-amount u0) (err u"Coverage amount must be positive"))
    (asserts! (> premium-amount u0) (err u"Premium amount must be positive"))
    (asserts! (>= policy-duration u1000) (err u"Coverage duration too short"))
    (asserts! (> drought-threshold (to-int u0)) (err u"Invalid drought threshold"))
    (asserts! (> flood-threshold drought-threshold) (err u"Invalid excess rain threshold"))
    (asserts! (< frost-threshold (to-int u30)) (err u"Invalid frost threshold"))
    (asserts! (is-authorized-oracle oracle-provider) (err u"Oracle provider not authorized"))
    
    ;; Transfer premium payment
    (asserts! (is-ok (stx-transfer? premium-amount tx-sender (as-contract tx-sender))) 
             (err u"Failed to transfer premium payment"))
    
    ;; Transfer protocol fee
    (asserts! (is-ok (as-contract (stx-transfer? protocol-fee tx-sender (var-get protocol-treasury))))
             (err u"Failed to transfer protocol fee"))
    
    ;; Create the policy
    (map-set insurance-policies
      { policy-id: policy-id }
      {
        policyholder: tx-sender,
        location-id: location-id,
        crop-type: crop-type,
        coverage-amount: coverage-amount,
        premium-amount: premium-amount,
        start-block: start-height,
        end-block: end-height,
        is-active: true,
        drought-threshold: drought-threshold,
        flood-threshold: flood-threshold,
        frost-threshold: frost-threshold,
        payout-executed: false,
        oracle-provider: oracle-provider
      }
    )
    
    ;; Set next policy ID now to avoid any race conditions
    (var-set next-policy-id (+ policy-id u1))
    
    ;; Update risk pool
    (match (map-get? risk-pools { crop-type: crop-type })
      existing-pool (map-set risk-pools
                      { crop-type: crop-type }
                      {
                        total-premiums: (+ (get total-premiums existing-pool) pool-contribution),
                        total-payouts: (get total-payouts existing-pool),
                        active-policies: (+ (get active-policies existing-pool) u1),
                        reserve-ratio: (get reserve-ratio existing-pool),
                        available-funds: (+ (get available-funds existing-pool) pool-contribution)
                      }
                    )
      ;; Create new pool if it doesn't exist
      (map-set risk-pools
        { crop-type: crop-type }
        {
          total-premiums: pool-contribution,
          total-payouts: u0,
          active-policies: u1,
          reserve-ratio: u7000,  ;; Default 70% reserve ratio
          available-funds: pool-contribution
        }
      )
    )
    
    ;; Policy ID counter increment was moved above to avoid race conditions
    
    (ok policy-id)
  )
)

;; Submit weather data (oracle only)
(define-public (record-weather-data
                (location-id (string-ascii 64))
                (rainfall-mm int)
                (temperature-celsius int)
                (humidity-percent uint))
  (begin
    ;; Validate oracle authorization
    (asserts! (is-authorized-oracle tx-sender) (err u"Not authorized as oracle"))
    
    ;; Record weather data
    (map-set weather-records
      { location-id: location-id, recorded-block: block-height }
      {
        rainfall-mm: rainfall-mm,
        temperature-celsius: temperature-celsius,
        humidity-percent: humidity-percent,
        recorded-by: tx-sender,
        is-verified: false  ;; Would need verification from multiple oracles in production
      }
    )
    
    ;; Process any policies that might be triggered by this data
    (try! (check-policy-triggers location-id))
    
    (ok true)
  )
)

;; Process weather triggers for policies
(define-private (check-policy-triggers (location-id (string-ascii 64)))
  (begin
    ;; In a real implementation, this would iterate through all policies for the location
    ;; and check trigger conditions. Simplified for this example.
    
    ;; Return early if no policies match, to avoid any future issues
    
    ;; For demonstration, we'll process a dummy policy ID 0
    (let ((policy-data (map-get? insurance-policies { policy-id: u0 })))
      (if (is-some policy-data)
        (let ((policy (unwrap-panic policy-data)))
          (if (and (is-eq (get location-id policy) location-id)
                 (get is-active policy)
                 (not (get payout-executed policy))
                 (<= (get start-block policy) block-height)
                 (>= (get end-block policy) block-height))
            ;; Policy matches criteria, check triggers
            (let ((trigger-result (evaluate-trigger-conditions u0 policy)))
              (if (is-ok trigger-result)
                (ok true)
                trigger-result))
            ;; Policy doesn't match criteria
            (ok true)))
        ;; No policy found
        (ok true)))
  )
)

;; Check if policy triggers are met
(define-private (evaluate-trigger-conditions (policy-id uint) (policy (tuple 
                                         (policyholder principal)
                                         (location-id (string-ascii 64))
                                         (crop-type (string-ascii 32))
                                         (coverage-amount uint)
                                         (premium-amount uint)
                                         (start-block uint)
                                         (end-block uint)
                                         (is-active bool)
                                         (drought-threshold int)
                                         (flood-threshold int)
                                         (frost-threshold int)
                                         (payout-executed bool)
                                         (oracle-provider principal))))
  (let
    ((weather (unwrap! (map-get? weather-records 
                       { location-id: (get location-id policy), recorded-block: block-height })
                      (err u"Weather data not found"))))
    
    ;; Check if any trigger conditions are met
    (if (or (< (get rainfall-mm weather) (get drought-threshold policy))
            (> (get rainfall-mm weather) (get flood-threshold policy))
            (< (get temperature-celsius weather) (get frost-threshold policy)))
        ;; Trigger conditions met, execute payout
        (process-claim-payout policy-id)
        (ok false)
    )
  )
)

;; Execute policy payout
(define-private (process-claim-payout (policy-id uint))
  (let
    ((policy-data (map-get? insurance-policies { policy-id: policy-id })))
    
    ;; Check if policy exists
    (asserts! (is-some policy-data) (err u"Policy not found"))
    (let ((policy (unwrap-panic policy-data)))
      
      ;; Validate policy is active and payout not already executed
      (asserts! (get is-active policy) (err u"Policy not active"))
      (asserts! (not (get payout-executed policy)) (err u"Payout already executed"))
      
      ;; Update policy status
      (map-set insurance-policies
        { policy-id: policy-id }
        (merge policy { payout-executed: true, is-active: false })
      )
      
      ;; Update risk pool
      (let ((pool-data (map-get? risk-pools { crop-type: (get crop-type policy) })))
        (asserts! (is-some pool-data) (err u"Risk pool not found"))
        
        (let ((pool (unwrap-panic pool-data)))
          (map-set risk-pools
            { crop-type: (get crop-type policy) }
            {
              total-premiums: (get total-premiums pool),
              total-payouts: (+ (get total-payouts pool) (get coverage-amount policy)),
              active-policies: (- (get active-policies pool) u1),
              reserve-ratio: (get reserve-ratio pool),
              available-funds: (- (get available-funds pool) (get coverage-amount policy))
            }
          )
        )
      )
      
      ;; Transfer payout to policyholder
      (asserts! (is-ok (as-contract (stx-transfer? (get coverage-amount policy) tx-sender (get policyholder policy))))
                (err u"Failed to transfer payout"))
      
      (ok true)
    )
  )
)

;; Allow a user to cancel policy before end date (partial refund)
(define-public (terminate-policy (policy-id uint))
  (let
    ((policy-data (map-get? insurance-policies { policy-id: policy-id })))
    
    ;; Validate policy exists
    (asserts! (is-some policy-data) (err u"Policy not found"))
    (let ((policy (unwrap-panic policy-data)))
      
      ;; Validate
      (asserts! (is-eq tx-sender (get policyholder policy)) (err u"Not the policyholder"))
      (asserts! (get is-active policy) (err u"Policy not active"))
      (asserts! (not (get payout-executed policy)) (err u"Payout already executed"))
      
      ;; Calculate refund based on time remaining
      (let
        ((total-duration (- (get end-block policy) (get start-block policy)))
         (elapsed-duration (- block-height (get start-block policy)))
         (remaining-duration (- total-duration elapsed-duration))
         (refund-percentage (/ (* remaining-duration u10000) total-duration))
         (refund-amount (/ (* (get premium-amount policy) refund-percentage) u10000)))
        
        ;; Update policy status
        (map-set insurance-policies
          { policy-id: policy-id }
          (merge policy { is-active: false })
        )
        
        ;; Update risk pool
        (let ((pool-data (map-get? risk-pools { crop-type: (get crop-type policy) })))
          (asserts! (is-some pool-data) (err u"Risk pool not found"))
          
          (let ((pool (unwrap-panic pool-data)))
            (map-set risk-pools
              { crop-type: (get crop-type policy) }
              {
                total-premiums: (get total-premiums pool),
                total-payouts: (get total-payouts pool),
                active-policies: (- (get active-policies pool) u1),
                reserve-ratio: (get reserve-ratio pool),
                available-funds: (- (get available-funds pool) refund-amount)
              }
            )
          )
        )
        
        ;; Transfer refund to policyholder
        (asserts! (is-ok (as-contract (stx-transfer? refund-amount tx-sender (get policyholder policy))))
                  (err u"Failed to transfer refund"))
        
        (ok refund-amount)
      )
    )
  )
)

;; Verify weather data (multiple oracles required)
(define-public (confirm-weather-data
                (location-id (string-ascii 64))
                (recorded-block uint)
                (rainfall-mm int)
                (temperature-celsius int)
                (humidity-percent uint))
  (let
    ((weather-entry (unwrap! (map-get? weather-records 
                              { location-id: location-id, recorded-block: recorded-block })
                             (err u"Weather data not found"))))
    
    ;; Validate oracle authorization
    (asserts! (is-authorized-oracle tx-sender) (err u"Not authorized as oracle"))
    (asserts! (not (is-eq tx-sender (get recorded-by weather-entry))) 
              (err u"Cannot verify own data"))
    
    ;; Check if data matches within acceptable margin of error
    (asserts! (< (abs (- rainfall-mm (get rainfall-mm weather-entry))) (to-int u5)) 
              (err u"Rainfall data differs too much"))
    (asserts! (< (abs (- temperature-celsius (get temperature-celsius weather-entry))) (to-int u2)) 
              (err u"Temperature data differs too much"))
    (asserts! (< (abs-uint humidity-percent (get humidity-percent weather-entry)) u5) 
              (err u"Humidity data differs too much"))
    
    ;; Mark data as verified
    (map-set weather-records
      { location-id: location-id, recorded-block: recorded-block }
      (merge weather-entry { is-verified: true })
    )
    
    (ok true)
  )
)

;; Manually trigger policy evaluation (for testing or backup)
(define-public (trigger-policy-evaluation (policy-id uint))
  (let
    ((policy (unwrap! (map-get? insurance-policies { policy-id: policy-id }) 
                     (err u"Policy not found")))
     (recent-weather (fetch-recent-weather (get location-id policy))))
    
    ;; Validate
    (asserts! (or (is-eq tx-sender (get policyholder policy))
                 (is-eq tx-sender (get oracle-provider policy)))
              (err u"Not authorized"))
    (asserts! (get is-active policy) (err u"Policy not active"))
    (asserts! (not (get payout-executed policy)) (err u"Payout already executed"))
    (asserts! (is-some recent-weather) (err u"No weather data available"))
    
    ;; Check if any trigger conditions are met
    (let ((weather (unwrap-panic recent-weather)))
      (if (or (< (get rainfall-mm weather) (get drought-threshold policy))
              (> (get rainfall-mm weather) (get flood-threshold policy))
              (< (get temperature-celsius weather) (get frost-threshold policy)))
          ;; Trigger conditions met, execute payout
          (process-claim-payout policy-id)
          (ok false)
      )
    )
  )
)

;; Get latest weather data for a location
(define-private (fetch-recent-weather (location-id (string-ascii 64)))
  ;; In a real implementation, this would search for the most recent data
  ;; Simplified for this example
  (map-get? weather-records { location-id: location-id, recorded-block: block-height })
)

;; Utility function for absolute value (int)
(define-private (abs (x int))
  (if (< x (to-int u0)) (to-int (- u0 (to-uint x))) x)
)

;; Utility function for absolute value (uint)
(define-private (abs-uint (x uint) (y uint))
  (if (> x y) (- x y) (- y x))
)

;; Read-only functions

;; Get policy details
(define-read-only (get-policy (policy-id uint))
  (ok (unwrap! (map-get? insurance-policies { policy-id: policy-id }) (err u"Policy not found")))
)

;; Get weather data
(define-read-only (get-weather-data (location-id (string-ascii 64)) (recorded-block uint))
  (ok (unwrap! (map-get? weather-records { location-id: location-id, recorded-block: recorded-block })
              (err u"Weather data not found")))
)

;; Get risk pool information
(define-read-only (get-risk-pool (crop-type (string-ascii 32)))
  (ok (unwrap! (map-get? risk-pools { crop-type: crop-type }) (err u"Risk pool not found")))
)

;; Check if oracle is authorized
(define-read-only (check-oracle-authorization (oracle principal))
  (ok (is-authorized-oracle oracle))
)