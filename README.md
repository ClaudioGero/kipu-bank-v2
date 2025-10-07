# KipuBankV2 – Multi-Token USD-Capped Vault

## Project Description
**KipuBankV2** is an advanced smart-contract vault that supports **ETH and ERC-20 tokens**, tracks value in **USD** via a Chainlink oracle, enforces a **global USD bank cap**, and exposes **role-based administration** for safer operations.

---

## Main Features

### Core Functionality
- **Multi-Token Vaults:** Users can deposit/withdraw **ETH (native)** and **approved ERC-20** tokens.
- **USD-Aware Limits:** Every deposit/withdrawal is converted to **USD** using **Chainlink ETH/USD** (ERC-20s are treated as ETH-denominated if configured as “ETH-like”, e.g., WETH).
- **Global Bank Cap (USD):** Prevents total vault exposure from exceeding a fixed USD ceiling.
- **Per-User Balances:** Internal ledger tracks each user’s balances for native ETH and each supported ERC-20.

### Operations & Admin
- **Access Control (RBAC):**
  - `DEFAULT_ADMIN_ROLE`: ultimate admin.
  - `ADMIN_ROLE`: maintenance tasks, token listings.
  - `OPERATOR_ROLE`: day-to-day ops (if/when added).
- **Token Registry:** Admins add supported ERC-20s with metadata (decimals, min/max deposit, etc.).
- **Event-Rich Telemetry:** Deposits/withdrawals emit typed events with **USD value** included.

---

## Technical Implementation (V2)

### Architecture Overview
- **Oracles:** Uses **Chainlink ETH/USD** (`IAggregatorV3`) priced with **8 decimals**. Helper functions normalize token amounts to **18 decimals** and then price them as ETH (works for ETH-pegged tokens like WETH; for other tokens you’d extend with per-token feeds).

### Decimals & Scales
- ETH: **18d**, Price: **8d**, USD convention: **6d**.
- `convertToUSD()` computes: `usdValue = (amount_18d * price_8d) / 10^8`.
- Ensure the **bank cap** constant/inputs align with the USD scale you store/compare in code.

### Roles Bootstrap
- Uses **`_grantRole`** inside the constructor to seed `DEFAULT_ADMIN_ROLE`, `ADMIN_ROLE`, and `OPERATOR_ROLE` to the deployer (OpenZeppelin v5 pattern).

### Token Registry
- `supportedTokens[address(0)]` is registered as **native ETH** (18 decimals).
- New ERC-20s can be added (decimals, min/max deposit); only “supported” tokens pass `validToken`.

### Key Data Structures
- `enum TokenType { NATIVE, ERC20 }`
- `struct TokenInfo { TokenType tokenType; uint8 decimals; bool isSupported; uint256 minDeposit; uint256 maxDeposit; }`
- `struct UserBalance { uint256 nativeBalance; mapping(address => uint256) tokenBalances; }`
- Mappings:
  - `mapping(address => UserBalance) userBalances;`
  - `mapping(address => TokenInfo) supportedTokens;`

### Core Flows

#### Deposits
- **ETH:** `depositETH()` → `_processDeposit(address(0), msg.value)`
- **ERC-20:** `depositToken(token, amount)` does `transferFrom()` first, then `_processDeposit(token, amount)`
- `_processDeposit`:
  1. Convert to USD via `convertToUSD(token, amount)`.
  2. Enforce **USD bank cap** (`totalDepositedUSD + usdValue <= MAX_BANK_CAP_USD`).
  3. Update the caller’s balance (native vs token map).
  4. Increment `depositCount`, add to `totalDepositedUSD`.
  5. Emit `MultiTokenDeposit(user, token, amount, usdValue)`.

#### Withdrawals
- **ETH:** `withdrawETH(amount)` → `_processWithdrawal(address(0), amount)`
- **ERC-20:** `withdrawToken(token, amount)` → `_processWithdrawal(token, amount)`
- `_processWithdrawal`:
  1. Convert to USD for accounting symmetry.
  2. Check **user balance** for that asset.
  3. Decrement balances, **transfer out** (native call or ERC-20 `transfer`).
  4. Decrement `totalDepositedUSD`, increment `withdrawalCount`.
  5. Emit `MultiTokenWithdrawal(user, token, amount, usdValue)`.

### Errors & Events (highlights)
- **Errors:** `TokenNotSupported`, `BankCapExceeded`, `InsufficientBalance`, `TransferFailed`, `ZeroAmount`, `UnauthorizedAccess`.
- **Events:** `TokenAdded`, `MultiTokenDeposit`, `MultiTokenWithdrawal` (include token and USD value).

---

## Contract Components

### Immutable/Constant Examples
- **Oracle Address** (network specific).
- **`MAX_BANK_CAP_USD`** (global cap).

### Storage Variables
- `totalDepositedUSD`, `depositCount`, `withdrawalCount`
- `userBalances[user].nativeBalance` and `userBalances[user].tokenBalances[token]`
- `supportedTokens[token]` registry entries

### Public Views
- `getUserBalance(user, token)` — per-asset balances
- `convertToUSD(token, amount)` — pricing helper
- `getCurrentETHPrice()` — raw Chainlink latest price

---

## Prerequisites
- MetaMask (or equivalent)
- Testnet/mainnet ETH to deploy & interact
- Remix IDE (or Foundry/Hardhat if preferred)

---

## Deployment Instructions

### Step 1: Setup
- Open **Remix IDE**
- Create file: `contracts/KipuBankV2.sol`
- Paste the source code

### Step 2: Compilation
- **Solidity compiler**: `0.8.19` (or compatible)
- **Enable Optimization**: ON (Runs 200–999)
- (Optional) **viaIR**: ON to reduce bytecode size
- **OpenZeppelin v5**: use `@openzeppelin/contracts/access/AccessControl.sol` and `@openzeppelin/contracts/utils/ReentrancyGuard.sol`

### Step 3: Deployment
- **Environment**: Injected Provider – MetaMask
- **Network**: your target net (e.g., Sepolia)
- **Constructor params**:
  - If your code version takes the oracle as a constructor param, pass the **ETH/USD feed** for the selected network.
  - If your code hard-codes a Sepolia feed, deploy on **Sepolia**.
- Click **Deploy** and confirm in MetaMask

### Step 4: Verification
- Copy deployed address → open the explorer (e.g., Etherscan)
- **Verify & Publish** → paste source, match compiler settings, enable optimization flags accordingly

---

## How to Interact with the Contract

### Adding a Supported Token (Admin)
1. From an account with **`ADMIN_ROLE`**, call your token-listing function (if included in your version) to add an ERC-20 with its decimals & deposit limits.
2. Verify `supportedTokens[token].isSupported` returns `true`.

### Making a Deposit
- **ETH:** set Remix **VALUE** (e.g., `0.1 ether`) → `depositETH()`
- **ERC-20:** approve the contract in the token first, then call `depositToken(token, amount)`

### Making a Withdrawal
- **ETH:** call `withdrawETH(amount)`
- **ERC-20:** call `withdrawToken(token, amount)`

### Checking Balances
- `getUserBalance(<yourAddress>, <token>)`
  - `token = 0x000…000` for **ETH**

---

## Deployed Contracts
- **KipuBankV2 (latest):** `0x5b718aa6cA0c8F94D5275269A5d38C049B9b1c4D`
