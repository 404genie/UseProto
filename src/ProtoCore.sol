// SPDX-License-Identifier: MIT
pragma solidity ^0.8.26;

import {IProtoCore} from "../interfaces/IProtoCore.sol";

interface IRouterRegistry {
    function registerCurve(address curve, address token, address creator) external;
    function bindModules(address vault, address fees) external;
    function bindV4(address poolManager, address hook) external;
}

interface ITokenBalance {
    function balanceOf(address) external view returns (uint256);
    function maxLiquidBalance() external view returns (uint256);
}

contract ProtoCore is IProtoCore {
    enum Lifecycle {
        NONE,
        ACTIVE_CURVE,
        GRADUATING,
        GRADUATED
    }

    struct TokenInfo {
        address creator;
        address curve;
        uint256 launchPriceUsd8;
        uint256 virtualQuoteReserve;
        uint64 launchedAt;
        Lifecycle lifecycle;
        string metadataURI;
    }

    address public immutable configurator;
    address public factory;
    address public router;
    address public graduationManager;
    bool public v4Bound;
    mapping(address token => bytes32) public poolOf;
    mapping(address token => uint256) public positionOf;
    mapping(address token => TokenInfo) public tokenInfo;
    mapping(address account => bool) public isProtocolSystem;
    mapping(address token => mapping(address account => bool)) private _system;

    error Unauthorized();
    error AlreadyConfigured();
    error InvalidInput();
    error Registered();
    error UnsafeSystemRemoval();
    event ProtocolBound(address indexed factory, address indexed router);
    event TokenRegistered(
        address indexed token,
        address indexed curve,
        address indexed creator,
        uint256 launchPriceUsd8,
        uint256 virtualQuoteReserve
    );
    event SystemAddressSet(address indexed token, address indexed account, bool allowed);
    event ProtocolSystemSet(address indexed account);

    constructor(address configurator_) {
        if (configurator_ == address(0)) revert InvalidInput();
        configurator = configurator_;
    }

    function bindProtocol(
        address factory_,
        address router_,
        address vault_,
        address fees_,
        address graduationManager_,
        address[] calldata additionalSystems
    ) external {
        if (msg.sender != configurator) revert Unauthorized();
        if (factory != address(0)) revert AlreadyConfigured();
        if (
            factory_ == address(0) || router_ == address(0) || vault_ == address(0) || fees_ == address(0)
                || graduationManager_ == address(0)
        ) {
            revert InvalidInput();
        }
        factory = factory_;
        router = router_;
        graduationManager = graduationManager_;
        _setProtocolSystem(factory_);
        _setProtocolSystem(router_);
        _setProtocolSystem(vault_);
        _setProtocolSystem(fees_);
        _setProtocolSystem(graduationManager_);
        for (uint256 i; i < additionalSystems.length; ++i) {
            if (additionalSystems[i] == address(0)) revert InvalidInput();
            _setProtocolSystem(additionalSystems[i]);
        }
        IRouterRegistry(router_).bindModules(vault_, fees_);
        emit ProtocolBound(factory_, router_);
    }

    function beginGraduation(address token) external returns (address curve) {
        if (msg.sender != graduationManager) revert Unauthorized();
        TokenInfo storage info = tokenInfo[token];
        if (info.lifecycle != Lifecycle.ACTIVE_CURVE) revert InvalidInput();
        info.lifecycle = Lifecycle.GRADUATING;
        return info.curve;
    }

    function bindV4(address poolManager, address hook, address positionManager, address adapter, address locker)
        external
    {
        if (msg.sender != configurator) revert Unauthorized();
        if (factory == address(0) || v4Bound) revert AlreadyConfigured();
        if (
            poolManager == address(0) || hook == address(0) || positionManager == address(0) || adapter == address(0)
                || locker == address(0)
        ) revert InvalidInput();
        v4Bound = true;
        _setProtocolSystem(poolManager);
        _setProtocolSystem(hook);
        _setProtocolSystem(positionManager);
        _setProtocolSystem(adapter);
        _setProtocolSystem(locker);
        IRouterRegistry(router).bindV4(poolManager, hook);
    }

    function finalizeGraduation(address token, bytes32 poolId, uint256 positionId) external {
        if (msg.sender != graduationManager) revert Unauthorized();
        TokenInfo storage info = tokenInfo[token];
        if (info.lifecycle != Lifecycle.GRADUATING || poolId == bytes32(0)) revert InvalidInput();
        poolOf[token] = poolId;
        positionOf[token] = positionId;
        info.lifecycle = Lifecycle.GRADUATED;
    }

    function registerLaunch(
        address token,
        address creator,
        address curve,
        uint256 launchPriceUsd8,
        uint256 virtualQuoteReserve,
        string calldata metadataURI
    ) external {
        if (msg.sender != factory) revert Unauthorized();
        if (token == address(0) || creator == address(0) || curve == address(0) || launchPriceUsd8 == 0) {
            revert InvalidInput();
        }
        if (tokenInfo[token].lifecycle != Lifecycle.NONE) revert Registered();
        tokenInfo[token] = TokenInfo(
            creator,
            curve,
            launchPriceUsd8,
            virtualQuoteReserve,
            uint64(block.timestamp),
            Lifecycle.ACTIVE_CURVE,
            metadataURI
        );
        _system[token][factory] = true;
        _system[token][router] = true;
        _system[token][curve] = true;
        IRouterRegistry(router).registerCurve(curve, token, creator);
        emit TokenRegistered(token, curve, creator, launchPriceUsd8, virtualQuoteReserve);
    }

    function setSystemAddress(address token, address account, bool allowed) external {
        if (msg.sender != factory) revert Unauthorized();
        if (!allowed && ITokenBalance(token).balanceOf(account) > ITokenBalance(token).maxLiquidBalance()) {
            revert UnsafeSystemRemoval();
        }
        _system[token][account] = allowed;
        emit SystemAddressSet(token, account, allowed);
    }

    function isSystemAddress(address token, address account) external view returns (bool) {
        return isProtocolSystem[account] || _system[token][account];
    }

    function _setProtocolSystem(address account) private {
        isProtocolSystem[account] = true;
        emit ProtocolSystemSet(account);
    }

    function curveOf(address token) external view returns (address) {
        return tokenInfo[token].curve;
    }

    function creatorOf(address token) external view returns (address) {
        return tokenInfo[token].creator;
    }

    function isGraduated(address token) external view returns (bool) {
        return tokenInfo[token].lifecycle == Lifecycle.GRADUATED;
    }
}
