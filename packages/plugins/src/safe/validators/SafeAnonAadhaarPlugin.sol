// SPDX-License-Identifier: LGPL-3.0-only
pragma solidity >=0.7.0 <0.9.0;
pragma abicoder v2;

import {Safe4337Base, SIG_VALIDATION_FAILED} from "../utils/Safe4337Base.sol";
import {IEntryPoint, PackedUserOperation} from "account-abstraction/interfaces/IEntryPoint.sol";
import {IAnonAadhaar} from "../utils/anonAadhaar/interfaces/IAnonAadhaar.sol";

interface ISafe {
    function enableModule(address module) external;

    function execTransactionFromModule(
        address to,
        uint256 value,
        bytes memory data,
        uint8 operation
    ) external returns (bool success);
}

struct AnonAadhaarOwnerStorage {
    address owner;
    uint256 userDataHash; // the hash of unique and private user data extracted from Aadhaar QR code
}

/*//////////////////////////////////////////////////////////////////////////
    THIS CONTRACT IS STILL IN ACTIVE DEVELOPMENT. NOT FOR PRODUCTION USE        
//////////////////////////////////////////////////////////////////////////*/

contract SafeAnonAadhaarPlugin is Safe4337Base {
    // Should be made possible to enable this if not the last mapping
    // mapping(address => mapping(uint => bool)) public signalNullifiers;
    mapping(address => AnonAadhaarOwnerStorage) public anonAadhaarOwnerStorage;

    address public immutable myAddress; // Module address
    address private immutable _entryPoint;

    address internal constant _SENTINEL_MODULES = address(0x1);

    // external contract managed by Anon Aadhaar with verifyAnonAadhaarProof() method
    // set to immutable to bypass invalid storage access error and make it accessible via delegatecall.
    address public immutable anonAadhaarAddr;

    // nullifier for each signal(userOpHash) to prevent on-chain front-running
    // mapping(uint => bool) public signalNullifiers;

    event OWNER_UPDATED(
        address indexed safe,
        address indexed oldOwner,
        address indexed newOwner
    );

    constructor(
        address entryPointAddress,
        address _anonAadhaarAddr,
        address _safe,
        uint256 _userDataHash
    ) {
        myAddress = address(this);
        _entryPoint = entryPointAddress;
        anonAadhaarAddr = _anonAadhaarAddr;
        anonAadhaarOwnerStorage[_safe].userDataHash = _userDataHash;
    }

    function getOwner(address safe) external view returns (address owner) {
        owner = anonAadhaarOwnerStorage[safe].owner;
    }

    function getUserDataHash(
        address safe
    ) external view returns (uint userDataHash) {
        userDataHash = anonAadhaarOwnerStorage[safe].userDataHash;
    }

    function execTransaction(
        address to,
        uint256 value,
        bytes calldata data
    ) external payable {
        _requireFromEntryPoint();

        bool success = _currentSafe().execTransactionFromModule(
            to,
            value,
            data,
            0
        );

        require(success, "tx failed");
    }

    function enableMyself(address ownerKey, uint256 userDataHash) public {
        // Called during safe setup as a delegatecall. This is why we use `this`
        // to refer to the safe instead of `msg.sender` / _currentSafe().
        ISafe(address(this)).enableModule(myAddress);

        // Enable the safe address with the defined key
        // bytes memory _data = abi.encodePacked(ownerKey, userDataHash);
        bytes memory _data = abi.encode(ownerKey, userDataHash);
        SafeAnonAadhaarPlugin(myAddress).enable(_data);
    }

    function entryPoint() public view override returns (IEntryPoint) {
        return IEntryPoint(_entryPoint);
    }

    function enable(bytes calldata _data) external payable {
        // address newOwner = address(bytes20(_data[0:20]));
        (address newOwner, uint256 userDataHash) = abi.decode(
            _data,
            (address, uint)
        );
        address oldOwner = anonAadhaarOwnerStorage[msg.sender].owner;
        anonAadhaarOwnerStorage[msg.sender].owner = newOwner;
        anonAadhaarOwnerStorage[msg.sender].userDataHash = userDataHash;
        emit OWNER_UPDATED(msg.sender, oldOwner, newOwner);
    }

    /// @dev Check if the timestamp is more recent than (current time - 3 hours)
    /// @param timestamp: msg.sender address.
    /// @return bool
    function isLessThan3HoursAgo(uint timestamp) public view returns (bool) {
        return timestamp > (block.timestamp - 3 * 60 * 60);
    }

    function _validateSignature(
        PackedUserOperation calldata userOp,
        bytes32 userOpHash
    ) internal view override returns (uint256 validationData) {
        // decode proof verification params
        (
            uint256 nullifierSeed,
            uint256 timestamp,
            uint256 signal,
            uint[4] memory revealArray,
            uint[8] memory groth16Proof
        ) = abi.decode(userOp.signature, (uint, uint, uint, uint[4], uint[8]));

        // Check if the signal value has already been nullified
        // require(!signalNullifiers[signal], "DUPLICATED_NULLIFIER");

        // make sure userOpHash == signal
        require(uint(userOpHash) == signal, "INVALID_SIGNAL");

        // see if the proof is fresh enough
        // not called to avoid invalid opcode: the use of block.timestamp.
        // require(isLessThan3HoursAgo(timestamp), "INVALID_TIMESTAMP");

        // verify proof throuugh AnonAadhaar and AnonAadhaarGroth16Verifier contracts
        if (
            !IAnonAadhaar(anonAadhaarAddr).verifyAnonAadhaarProof(
                nullifierSeed,
                anonAadhaarOwnerStorage[userOp.sender].userDataHash,
                timestamp,
                signal,
                revealArray,
                groth16Proof
            )
        ) {
            return SIG_VALIDATION_FAILED;
        }

        // signalNullifiers[userOp.sender][signal] = true; // store nullifier
        return 0;
    }
}
