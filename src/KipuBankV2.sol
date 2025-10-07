
// SPDX-License-Identifier: MIT
pragma solidity ^0.8.19;

// OpenZeppelin imports
import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";

// ============= INTERFACES =============

/**
 * @title IAggregatorV3
 * @dev Chainlink Price Feed Interface
 * @notice Interface for Chainlink ETH/USD price feeds
 */
interface IAggregatorV3 {
    function decimals() external view returns (uint8);
    
    function description() external view returns (string memory);
    
    function version() external view returns (uint256);
    
    function getRoundData(uint80 _roundId)
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
    
    function latestRoundData()
        external
        view
        returns (
            uint80 roundId,
            int256 answer,
            uint256 startedAt,
            uint256 updatedAt,
            uint80 answeredInRound
        );
}

interface IERC20 {
    function totalSupply() external view returns (uint256);
    
    function balanceOf(address account) external view returns (uint256);
    
    function transfer(address to, uint256 amount) external returns (bool);
    
    function allowance(address owner, address spender) external view returns (uint256);
    
    function approve(address spender, uint256 amount) external returns (bool);
    
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    
    event Transfer(address indexed from, address indexed to, uint256 value);
    
    event Approval(address indexed owner, address indexed spender, uint256 value);
}

// ============= MAIN CONTRACT =============

/**
 * @title KipuBankV2
 * @dev Advanced multi-token vault system with USD limits and admin recovery
 * @notice Enhanced version of KipuBank with Chainlink oracle integration
 * @author Senior Solidity Engineer
 */
contract KipuBankV2 is AccessControl, ReentrancyGuard {
    
    // ============= TYPES =============
    
    /// @notice Enum for token types supported by the vault
    enum TokenType {
        NATIVE,  // ETH
        ERC20    // ERC-20 tokens
    }
    
    /// @notice Struct containing token information
    struct TokenInfo {
        TokenType tokenType;    // Type of token
        uint8 decimals;        // Token decimals
        bool isSupported;      // Whether token is supported
        uint256 minDeposit;    // Minimum deposit amount
        uint256 maxDeposit;    // Maximum deposit amount
    }
    
    /// @notice Struct for user balance information
    struct UserBalance {
        uint256 nativeBalance;                    // ETH balance
        mapping(address => uint256) tokenBalances; // ERC-20 token balances
    }
    
    // ============= CONSTANTS =============
    
    /// @notice Chainlink price feed decimals (always 8)
    uint8 public constant PRICE_FEED_DECIMALS = 8;
    
    /// @notice ETH decimals (always 18)
    uint8 public constant ETH_DECIMALS = 18;
    
    /// @notice USD decimals (6 for USDC standard)
    uint8 public constant USD_DECIMALS = 6;
    
    /// @notice Scale factors for calculations
    uint256 public constant ETH_SCALE = 10**ETH_DECIMALS;
    uint256 public constant USD_SCALE = 10**USD_DECIMALS;
    uint256 public constant PRICE_SCALE = 10**PRICE_FEED_DECIMALS;
    
    /// @notice Chainlink ETH/USD Price Feed (Sepolia)
    address public constant ETH_USD_PRICE_FEED = 0x694AA1769357215DE4FAC081bf1f309aDC325306;
    
    // ============= ROLES =============
    
    /// @notice Admin role for contract management
    bytes32 public constant ADMIN_ROLE = keccak256("ADMIN_ROLE");
    
    /// @notice Operator role for daily operations
    bytes32 public constant OPERATOR_ROLE = keccak256("OPERATOR_ROLE");
    
    // ============= STATE VARIABLES =============
    
    /// @notice Chainlink ETH/USD price feed
    /// @dev Set at deployment, immutable for security
    IAggregatorV3 public immutable ethUsdPriceFeed;
    
    /// @notice Maximum bank capacity in USD
    /// @dev Set at deployment, prevents unlimited deposits
    uint256 public maxBankCapUSD;
    
    /// @notice Maximum withdrawal limit in USD
    /// @dev Set at deployment, prevents large withdrawals
    uint256 public maxWithdrawalUSD;
    
    /// @notice Current total deposits in USD
    /// @dev Increases on deposits, decreases on withdrawals
    uint256 public totalDepositedUSD;
    
    /// @notice Total number of deposits made
    /// @dev Incremented on each successful deposit
    uint256 public depositCount;
    
    /// @notice Total number of withdrawals made
    /// @dev Incremented on each successful withdrawal
    uint256 public withdrawalCount;
    
    // ============= MAPPINGS =============
    
    /// @notice Maps user address to their balance information
    /// @dev Contains both native ETH and ERC-20 token balances
    mapping(address => UserBalance) public userBalances;
    
    /// @notice Maps token address to token information
    /// @dev Used to track supported tokens and their properties
    mapping(address => TokenInfo) public supportedTokens;
    
    
    // ============= CUSTOM ERRORS =============
    
    error InsufficientBalance();
    error ExceedsWithdrawalLimit();
    error BankCapExceeded();
    error TransferFailed();
    error DepositTooSmall();
    error ZeroAmount();
    error TokenNotSupported(address token);
    error UnauthorizedAccess();
    
    // ============= EVENTS =============
    
    event DepositMade(address indexed user, uint256 amount, uint256 newBalance);
    event WithdrawalMade(address indexed user, uint256 amount, uint256 newBalance);
    event TokenAdded(address indexed token, TokenInfo info);
    event MultiTokenDeposit(address indexed user, address indexed token, uint256 amount, uint256 usdValue);
    event MultiTokenWithdrawal(address indexed user, address indexed token, uint256 amount, uint256 usdValue);
    
    // ============= MODIFIERS =============
    
    modifier onlyAdmin() {
        if (!hasRole(ADMIN_ROLE, msg.sender)) revert UnauthorizedAccess();
        _;
    }
    
    modifier onlyOperator() {
        if (!hasRole(OPERATOR_ROLE, msg.sender) && !hasRole(ADMIN_ROLE, msg.sender)) {
            revert UnauthorizedAccess();
        }
        _;
    }
    
    modifier validToken(address token) {
        if (!supportedTokens[token].isSupported) revert TokenNotSupported(token);
        _;
    }
    
    modifier validAmount(uint256 amount) {
        if (amount == 0) revert ZeroAmount();
        _;
    }
    
    // ============= CONSTRUCTOR =============
    
    /// @notice Constructor with bank cap and withdrawal limit
    constructor(
        uint256 _maxBankCapUSD,
        uint256 _maxWithdrawalUSD
    ) {
        ethUsdPriceFeed = IAggregatorV3(ETH_USD_PRICE_FEED);
        
        // Set user-provided values
        maxBankCapUSD = _maxBankCapUSD;
        maxWithdrawalUSD = _maxWithdrawalUSD;
        
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        _grantRole(ADMIN_ROLE, msg.sender);
        _grantRole(OPERATOR_ROLE, msg.sender);
        
        supportedTokens[address(0)] = TokenInfo({
            tokenType: TokenType.NATIVE,
            decimals: ETH_DECIMALS,
            isSupported: true,
            minDeposit: 0,
            maxDeposit: type(uint256).max
        });
        
        emit TokenAdded(address(0), supportedTokens[address(0)]);
    }
    
    // ============= INTERNAL FUNCTIONS =============
    
    /// @notice Validates if ERC-20 token is supported
    function _validateERC20Token(address token) internal view {
        if (token == address(0)) revert TokenNotSupported(token);
        if (!supportedTokens[token].isSupported) revert TokenNotSupported(token);
    }
    
    // ============= CONVERSION FUNCTIONS =============
    
    /// @notice Converts ETH amount to USD using Chainlink price feed
    function _convertETHToUSD(uint256 ethAmount) internal view returns (uint256) {
        uint256 ethPrice = getCurrentETHPrice();
        return (ethAmount * ethPrice) / PRICE_SCALE;
    }
    
    /// @notice Converts ERC-20 token amount to USD via ETH conversion
    function _convertERC20ToUSD(address token, uint256 tokenAmount) internal view returns (uint256) {
        TokenInfo memory tokenInfo = supportedTokens[token];
        uint256 normalizedAmount = normalizeDecimals(tokenAmount, tokenInfo.decimals, ETH_DECIMALS);
        return _convertETHToUSD(normalizedAmount);
    }
    
    /// @notice Normalizes token amounts between different decimal places
    function normalizeDecimals(uint256 amount, uint8 fromDecimals, uint8 toDecimals) public pure returns (uint256) {
        if (fromDecimals == toDecimals) {
            return amount;
        } else if (fromDecimals < toDecimals) {
            return amount * (10 ** (toDecimals - fromDecimals));
        } else {
            return amount / (10 ** (fromDecimals - toDecimals));
        }
    }
    
    // ============= DEPOSIT FUNCTIONS =============
    
    /// @notice Deposits native ETH into user's vault
    function depositETH() external payable nonReentrant validAmount(msg.value) {
        _processDeposit(address(0), msg.value);
    }
    
    /// @notice Deposits ERC-20 tokens into user's vault
    function depositToken(address token, uint256 amount) external nonReentrant validToken(token) validAmount(amount) {
        _validateERC20Token(token);
        
        IERC20(token).transferFrom(msg.sender, address(this), amount);
        _processDeposit(token, amount);
    }
    
    /// @notice Internal function to process deposits and update balances
    function _processDeposit(address token, uint256 amount) internal {
        uint256 usdValue = convertToUSD(token, amount);
        
        if (totalDepositedUSD + usdValue > maxBankCapUSD) {
            revert BankCapExceeded();
        }
        
        if (token == address(0)) {
            userBalances[msg.sender].nativeBalance += amount;
        } else {
            userBalances[msg.sender].tokenBalances[token] += amount;
        }
        
        totalDepositedUSD += usdValue;
        depositCount++;
        
        emit MultiTokenDeposit(msg.sender, token, amount, usdValue);
    }
    
    // ============= WITHDRAWAL FUNCTIONS =============
    
    /// @notice Withdraws native ETH from user's vault
    function withdrawETH(uint256 amount) external nonReentrant validAmount(amount) {
        _processWithdrawal(address(0), amount);
    }
    
    /// @notice Withdraws ERC-20 tokens from user's vault
    function withdrawToken(address token, uint256 amount) external nonReentrant validToken(token) validAmount(amount) {
        _validateERC20Token(token);
        _processWithdrawal(token, amount);
    }
    
    /// @notice Internal function to process withdrawals and update balances
    function _processWithdrawal(address token, uint256 amount) internal {
        uint256 usdValue = convertToUSD(token, amount);
        
        if (usdValue > maxWithdrawalUSD) {
            revert ExceedsWithdrawalLimit();
        }
        
        if (token == address(0)) {
            if (amount > userBalances[msg.sender].nativeBalance) {
                revert InsufficientBalance();
            }
            userBalances[msg.sender].nativeBalance -= amount;
            
            (bool success, ) = payable(msg.sender).call{value: amount}("");
            if (!success) revert TransferFailed();
        } else {
            if (amount > userBalances[msg.sender].tokenBalances[token]) {
                revert InsufficientBalance();
            }
            userBalances[msg.sender].tokenBalances[token] -= amount;
            
            IERC20(token).transfer(msg.sender, amount);
        }
        
        totalDepositedUSD -= usdValue;
        withdrawalCount++;
        
        emit MultiTokenWithdrawal(msg.sender, token, amount, usdValue);
    }
    
    // ============= VIEW FUNCTIONS =============
    
    /// @notice Gets user's balance for a specific token
    function getUserBalance(address user, address token) external view returns (uint256) {
        if (token == address(0)) {
            return userBalances[user].nativeBalance;
        } else {
            return userBalances[user].tokenBalances[token];
        }
    }
    
    /// @notice Gets current ETH/USD price from Chainlink oracle
    function getCurrentETHPrice() public view returns (uint256) {
        (, int256 price, , , ) = ethUsdPriceFeed.latestRoundData();
        if (price <= 0) revert TransferFailed();
        return uint256(price);
    }
    
    /// @notice Converts any token amount to USD equivalent
    function convertToUSD(address token, uint256 amount) public view returns (uint256) {
        if (token == address(0)) {
            return _convertETHToUSD(amount);
        } else {
            return _convertERC20ToUSD(token, amount);
        }
    }
    
    // ============= RECEIVE/FALLBACK =============
    
    /// @notice Prevents direct ETH transfers to contract
    receive() external payable {
        revert ZeroAmount();
    }
    
    /// @notice Prevents calls to non-existent functions
    fallback() external payable {
        revert ZeroAmount();
    }
    
}
