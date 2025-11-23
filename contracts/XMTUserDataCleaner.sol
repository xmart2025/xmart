// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "./AdminRoleUpgrade.sol";
import "./interfaces/IXMTEntryPoint.sol";
import "./interfaces/IXMTpassAirdrop.sol";
import "./interfaces/IXMTpassPointsPool.sol";
import "./interfaces/IXMTStake.sol";
import "./interfaces/IXMTPool.sol";

contract XMTUserDataCleaner is AdminRoleUpgrade, Initializable {
    
    IXMTEntryPoint public entryPoint;
    IXMTpassAirdrop public airdrop;
    IXMTpassPointsPool public pointsPool;
    IXMTStake public stake;
    IXMTPool public pool;

    event UserDataClearedBatch(address[] users);

    function initialize() public initializer {
        _addAdmin(msg.sender);
    }

    function setContracts(

        address _entryPoint,
        address _airdrop,
        address _pointsPool,
        address _stake,
        address _pool
    ) external onlyAdmin {
        entryPoint = IXMTEntryPoint(_entryPoint);
        airdrop = IXMTpassAirdrop(_airdrop);
        pointsPool = IXMTpassPointsPool(_pointsPool);
        stake = IXMTStake(_stake);
        pool = IXMTPool(_pool);
    }

    function clearUserDataBatch(address[] memory users) external onlyAdmin {
        require(users.length > 0, "empty users array");
        require(address(entryPoint) != address(0), "entryPoint not set");
        require(address(airdrop) != address(0), "airdrop not set");
        require(address(pointsPool) != address(0), "pointsPool not set");
        require(address(stake) != address(0), "stake not set");
        require(address(pool) != address(0), "pool not set");
        entryPoint.clearUserDataBatch(users);
        airdrop.clearUserDataBatch(users);
        pointsPool.clearUserDataBatch(users);
        stake.clearUserDataBatch(users);
        pool.clearUserDataBatch(users);
        emit UserDataClearedBatch(users);
    }
}