// SPDX-License-Identifier: MIT
pragma solidity 0.8.19;

import '../../../base/UntangledBase.sol';
import '../../../base/Factory.sol';
import '../../../interfaces/INoteTokenFactory.sol';
import '../../../libraries/ConfigHelper.sol';
import '../../../libraries/UntangledMath.sol';

contract NoteTokenFactory is UntangledBase, Factory, INoteTokenFactory {
    using ConfigHelper for Registry;

    modifier onlySecuritizationManager() {
        require(
            _msgSender() == address(registry.getSecuritizationManager()),
            'SecuritizationPool: Only SecuritizationManager'
        );
        _;
    }

    function initialize(Registry _registry, address _factoryAdmin) public initializer {
        __UntangledBase__init(_msgSender());
        __Factory__init(_factoryAdmin);

        registry = _registry;
    }

    function setFactoryAdmin(address _factoryAdmin) public onlyRole(DEFAULT_ADMIN_ROLE) {
        _setFactoryAdmin(_factoryAdmin);
    }

    function changeMinterRole(address tokenAddress, address newController) external override onlySecuritizationManager {
        NoteToken token = NoteToken(tokenAddress);
        token.grantRole(token.MINTER_ROLE(), newController);
    }

    function createToken(
        address _poolAddress,
        Configuration.NOTE_TOKEN_TYPE _noteTokenType,
        uint8 _nDecimals,
        string calldata ticker
    ) external override whenNotPaused nonReentrant onlySecuritizationManager returns (address) {
        string memory name;
        string memory symbol;
        if (_noteTokenType == Configuration.NOTE_TOKEN_TYPE.SENIOR) {
            name = 'Senior Obligation Token';
            symbol = string.concat(ticker, '_SOT');
        } else {
            name = 'Junior Obligation Token';
            symbol = string.concat(ticker, '_JOT');
        }

        address noteTokenImplAddress = address(registry.getNoteToken());

        bytes memory _initialData = abi.encodeWithSelector(
            getSelector('initialize(string,string,uint8,address,uint8)'),
            name,
            symbol,
            _nDecimals,
            _poolAddress,
            uint8(_noteTokenType)
        );

        address ntAddress = _deployInstance(noteTokenImplAddress, _initialData);

        NoteToken token = NoteToken(ntAddress);

        tokens.push(token);
        isExistingTokens[address(token)] = true;

        emit TokenCreated(address(token), _poolAddress, _noteTokenType, _nDecimals, ticker);

        return address(token);
    }

    function pauseUnpauseToken(address tokenAddress) external whenNotPaused nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        require(isExistingTokens[tokenAddress], 'NoteTokenFactory: token does not exist');
        NoteToken token = NoteToken(tokenAddress);
        if (token.paused()) {
            token.unpause();
        } else {
            token.pause();
        }
    }

    function pauseAllTokens() external whenNotPaused nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 tokensLength = tokens.length;
        for (uint256 i = 0; i < tokensLength; i = UntangledMath.uncheckedInc(i)) {
            if (!tokens[i].paused()) tokens[i].pause();
        }
    }

    function unPauseAllTokens() external whenNotPaused nonReentrant onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 tokensLength = tokens.length;
        for (uint256 i = 0; i < tokensLength; i = UntangledMath.uncheckedInc(i)) {
            if (tokens[i].paused()) tokens[i].unpause();
        }
    }

    uint256[50] private __gap;
}
