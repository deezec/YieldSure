# YieldSure

## Overview

YieldSure is a parametric crop insurance smart contract that automates agricultural insurance payouts based on predefined weather conditions. Instead of relying on manual claims, payouts are triggered by objective rainfall and temperature data submitted by authorized weather oracles.

## Features

* Automated claim processing based on real-time weather triggers
* On-chain storage of policies, weather data, and oracle details
* Decentralized oracle verification for weather data
* Risk pool management for different crop types
* Support for early policy cancellation with proportional refunds
* Admin-controlled protocol fee system

## Core Components

### Maps

* **coverage-contracts**: Stores individual crop insurance policies and their parameters.
* **climate-data**: Records weather metrics such as rainfall, temperature, and humidity by region and block height.
* **verified-data-sources**: Maintains a registry of approved weather oracle providers.
* **coverage-pools**: Tracks collected fees, distributed claims, and balances for each crop type.

### Data Variables

* `next-contract-id`: Counter for generating unique policy IDs.
* `admin-fee-rate`: Percentage of premiums allocated as administrative fees.
* `admin-wallet`: Address that receives protocol fees.

## Key Functions

### Policy Management

* **create-policy**: Creates a new insurance policy tied to specific crop, region, and weather thresholds.
* **cancel-policy**: Allows policyholders to terminate active coverage and receive a time-based refund.
* **evaluate-policy**: Manually triggers policy evaluation using the latest recorded weather data.
* **get-policy**: Retrieves details of a specific insurance contract.

### Oracle Operations

* **register-oracle**: Registers a new weather data provider.
* **submit-weather-data**: Submits weather metrics and checks for potential trigger events.
* **verify-weather-data**: Confirms accuracy of weather data submitted by other oracles.
* **check-oracle-authorization**: Checks if a given provider is an authorized oracle.

### Claim and Trigger Logic

* **process-weather-triggers**: Automatically evaluates weather data against policy thresholds.
* **check-policy-triggers**: Determines if weather conditions meet payout criteria.
* **execute-policy-payout**: Executes the STX payout to the policyholder and updates pool data.

### Pool Management

* **get-risk-pool**: Returns financial and statistical details about a crop’s risk pool.

### Utility

* **get-weather-data**: Retrieves weather metrics for a specific region and block time.
* **abs**, **abs-uint**: Helper functions for numerical comparisons.

## Workflow

1. **Oracle Registration**: Authorized weather data providers are registered on-chain.
2. **Policy Creation**: Farmers buy coverage by specifying region, crop, thresholds, and duration.
3. **Data Submission**: Oracles submit climate data for relevant regions.
4. **Trigger Evaluation**: If weather data breaches defined thresholds, automatic payouts are executed.
5. **Verification**: Secondary oracles can verify previously submitted weather data for reliability.
6. **Refund Option**: Farmers can cancel policies early and receive a proportional refund.
