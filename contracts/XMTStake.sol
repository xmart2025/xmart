// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/cryptography/ECDSAUpgradeable.sol";
import "./AdminRoleUpgrade.sol";
import "./interfaces/IXMTPool.sol";
import "./libraries/CSTDateTime.sol";
import "./interfaces/IRelation.sol";
import "./interfaces/IXMTpassVesting180Simple.sol";
import "./interfaces/IXMTEntryPoint.sol";
import "./interfaces/IAllowedContracts.sol";
import "./interfaces/IXMTClubTraderManage.sol";

contract XMTStake is AdminRoleUpgrade, Initializable {

    using CSTDateTime for *;
    using ECDSAUpgradeable for bytes32;

    event DailySettlement(
        address indexed user,
        uint256 indexed dayTs,
        uint256 principalReward,
        uint256 selfProfitReward,
        uint256 totalProfitReward,
        uint256 expiredCount,
        uint256 _ownerWeight
    );

    event DirectReferralBonusRecorded(
        address indexed parent,
        address indexed child,
        uint256 indexed dayTs,
        uint256 bonus
    );

    event ParentRewardDistributed(address indexed user, uint256 xmtAmount, uint256 passAmount, uint256 indexed dayTs);
    event ChildRewardDistributed(address indexed user, uint256 xmtAmount, uint256 passAmount, uint256 indexed dayTs);
    event MachineUnlocked(address indexed user, uint256 indexed machineId);
    event AddStake(address _addr, uint256 _machineId, uint256 _nodeId, uint256 _times, uint256 _weight, bool _isReward, uint256 _endPledgeId);

    using SafeMathUpgradeable for uint256;

    mapping(address => uint256) public claimTime;
    mapping(address => mapping(uint256 => uint256)) public unusedTimes;
    mapping(address => mapping(uint256 => uint256)) public pledgeExpireTime;
    mapping(address => uint256[]) public miningIds;
    mapping(address => uint256) public ownerWeight;
    mapping(address => uint256) public endPledgeId;
    mapping(address => mapping(uint256 => uint256)) public pledgeTypeId;
    mapping(address => mapping(uint256 => uint256)) public exchangeTime;
    mapping(address => mapping(uint256 => uint256)) public miningIdToMachineId;
    mapping(address => uint256) public receiveWeight;
    mapping(address => mapping(uint256 => bool)) public isRewardNode;
    mapping(address => mapping(uint256 => uint256)) public incomeRewardByDay;
    mapping(address => mapping(uint256 => uint256)) public childRewardByDay;
    mapping(address => mapping(uint256 => uint256)) public childCountByDay;
    IXMTPool public xmtPool;
    IRelation public relation;
    IXMTEntryPoint public entryPoint;
    mapping(address => address[]) public activeDirects;
    mapping(address => mapping(address => uint256)) public activeDirectIndex;
    mapping(uint256 => uint256) public globalDailyXmtReleased;
    mapping(uint256 => uint256) public globalDailyPassRecorded;
    uint256 public totalUnreleasedOwner;
    uint256 public totalUnreleasedProfit;
    mapping(address => uint256) public nonce;
    address public stakeSigner;
    IAllowedContracts public allowedContracts;
    IXMTClubTraderManage public traderManager;

    function initialize() public initializer {
        _addAdmin(msg.sender);
    }

    function setAboutAddress(address _relationAddr, address _poolAddr, address _entryPointAddr, address _allowedContractsAddr, address _traderManager) external onlyAdmin
    {
        relation = IRelation(_relationAddr);
        xmtPool = IXMTPool(_poolAddr);
        entryPoint = IXMTEntryPoint(_entryPointAddr);
        allowedContracts = IAllowedContracts(_allowedContractsAddr);
        traderManager = IXMTClubTraderManage(_traderManager);
    }

    function setStakeSigner(address _signer) external onlyAdmin {
        require(_signer != address(0), "signer=0");
        stakeSigner = _signer;
    }

    function claimStarRewardWithStarLevel(uint256 starLevel, uint256 signedBlock, bytes calldata signature) external {
        require(allowedContracts.canPoolAndStake(msg.sender), "not pool and stake");
        address addr = msg.sender;
        if (address(traderManager) != address(0)) {
            require(!traderManager.isTrader(addr), "trader banned");
        }
        require(claimTime[addr] < CSTDateTime.today(), "had claim");
        _verifySignature(addr, starLevel, signedBlock, signature);
        updateTypeIdTimes(addr);
        uint256 reward = getStarDailyReward(starLevel);
        if(reward > 0){
            entryPoint.addAmountWithStatus(addr, reward, 2);
        }
        entryPoint.processQueue(100);
        claimTime[addr] = block.timestamp;
        allowedContracts.unbanBlackAddress(addr, starLevel);
    }

    function getMiningIds(address _addr) external view returns(uint256[] memory){
        return miningIds[_addr];
    }

    function getActiveDirects(address user) external view returns (address[] memory) {
        return activeDirects[user];
    }

    function getActiveDirectCount(address user) external view returns (uint256) {
        return activeDirects[user].length;
    }

    function getActiveMiningDetails(address user)
        external
        view
        returns (
            uint256[] memory nodeIds,
            uint256[] memory prices,
            uint256[] memory aprs,
            uint256[] memory totalTimes,
            uint256[] memory remainingTimes,
            bool[] memory rewardFlags,
            uint256[] memory machineIds
        )
    {
        uint256 len = miningIds[user].length;
        nodeIds = new uint256[](len);
        prices = new uint256[](len);
        aprs = new uint256[](len);
        totalTimes = new uint256[](len);
        remainingTimes = new uint256[](len);
        rewardFlags = new bool[](len);
        machineIds = new uint256[](len);
        for (uint256 i = 0; i < len; i++) {
            uint256 miningIndex = miningIds[user][i];
            uint256 nodeId = pledgeTypeId[user][miningIndex];
            ( , uint256 price, uint256 day, uint256 apr) = xmtPool.getNodeDetail(nodeId);
            nodeIds[i] = nodeId;
            prices[i] = price;
            aprs[i] = apr;
            totalTimes[i] = day;
            remainingTimes[i] = unusedTimes[user][miningIndex];
            rewardFlags[i] = isRewardNode[user][miningIndex];
            machineIds[i] = miningIdToMachineId[user][miningIndex];
        }
    }

    function getGiftMachineMiningDetails(address user)
        external
        view
        returns (
            uint256[] memory nodeIds,
            uint256[] memory prices,
            uint256[] memory aprs,
            uint256[] memory totalTimes,
            uint256[] memory remainingTimes,
            bool[] memory rewardFlags,
            uint256[] memory machineIds
        )
    {
        uint256 len = miningIds[user].length;
        uint256 count = 0;
        for (uint256 i = 0; i < len; i++) {
            uint256 miningIndex = miningIds[user][i];
            if (miningIdToMachineId[user][miningIndex] == 10000) {
                count++;
            }
        }
        if (count == 0) {
            nodeIds = new uint256[](1);
            prices = new uint256[](1);
            aprs = new uint256[](1);
            totalTimes = new uint256[](1);
            remainingTimes = new uint256[](1);
            rewardFlags = new bool[](1);
            machineIds = new uint256[](1);
            return (nodeIds, prices, aprs, totalTimes, remainingTimes, rewardFlags, machineIds);
        }
        nodeIds = new uint256[](count);
        prices = new uint256[](count);
        aprs = new uint256[](count);
        totalTimes = new uint256[](count);
        remainingTimes = new uint256[](count);
        rewardFlags = new bool[](count);
        machineIds = new uint256[](count);
        uint256 idx = 0;
        for (uint256 i = 0; i < len; i++) {
            uint256 miningIndex = miningIds[user][i];
            if (miningIdToMachineId[user][miningIndex] != 10000) continue;
            uint256 nodeId = pledgeTypeId[user][miningIndex];
            (, uint256 price, uint256 day, uint256 apr) = xmtPool.getNodeDetail(nodeId);
            nodeIds[idx] = nodeId;
            prices[idx] = price;
            aprs[idx] = apr;
            totalTimes[idx] = day;
            remainingTimes[idx] = unusedTimes[user][miningIndex];
            rewardFlags[idx] = isRewardNode[user][miningIndex];
            machineIds[idx] = 10000;
            idx++;
        }
    }

    function updateTypeIdTimes(address _addr) internal {

        uint256 length = miningIds[_addr].length;
        uint256 expire_count = 0;
        uint256 principalRelease = 0;
        uint256 totalMiningProfit = 0;
        uint256 netMiningProfit = 0;
        uint256 today = CSTDateTime.today();
        uint256 prevOwnerWeight = ownerWeight[_addr];
        for(uint256 i=0; i<length; i++){
            uint256 index = miningIds[_addr][i];
            unusedTimes[_addr][index]--;
            uint256 typeId = pledgeTypeId[_addr][index];
            ( , uint256 price, uint256 day, uint256 apr) = xmtPool.getNodeDetail(typeId);
            uint256 ownerDaily = price.div(day);
            uint256 profitDaily = price.mul(apr).div(10000);
            principalRelease += ownerDaily;
            totalMiningProfit += profitDaily;
            if(!isRewardNode[_addr][index]){
                netMiningProfit += profitDaily;
            }
            if(unusedTimes[_addr][index] == 0){
                uint256 weight = price.div(10);
                expire_count ++;
                if(isRewardNode[_addr][index]){
                    receiveWeight[_addr] -= weight;
                }else {
                    ownerWeight[_addr] -= weight;
                }
                if(miningIdToMachineId[_addr][index] > 0){
                    uint256 mId = miningIdToMachineId[_addr][index];
                    xmtPool.updateMachineIdStatus(_addr, mId);
                    emit MachineUnlocked(_addr, mId);
                }
            }
        }
        if (principalRelease > 0) {
            totalUnreleasedOwner = totalUnreleasedOwner.sub(principalRelease);
        }
        if (totalMiningProfit > 0) {
            totalUnreleasedProfit = totalUnreleasedProfit.sub(totalMiningProfit);
        }

        uint256 payoutAmount = principalRelease.add(totalMiningProfit);
        if (payoutAmount > 0) {
            entryPoint.addAmountWithStatus(_addr, payoutAmount, 4);
            globalDailyXmtReleased[today] = globalDailyXmtReleased[today].add(payoutAmount);
        }
        if(netMiningProfit > 0){
            incomeRewardByDay[_addr][today] = netMiningProfit;
            addParentRewards(_addr, netMiningProfit);
        }
        if(expire_count > 0){
            updateStakeIds(_addr, expire_count);
        }
        if (prevOwnerWeight > 0 && ownerWeight[_addr] == 0) {
            address parent = relation.Inviter(_addr);
            if (parent != address(0)) {
                uint256 idxPlus = activeDirectIndex[parent][_addr];
                if (idxPlus > 0) {
                    uint256 idx = idxPlus - 1;
                    uint256 lastIdx = activeDirects[parent].length - 1;
                    if (idx != lastIdx) {
                        address lastChild = activeDirects[parent][lastIdx];
                        activeDirects[parent][idx] = lastChild;
                        activeDirectIndex[parent][lastChild] = idx + 1;
                    }
                    activeDirects[parent].pop();
                    activeDirectIndex[parent][_addr] = 0;
                }
            }
        }
        emit DailySettlement(_addr, today, principalRelease, netMiningProfit, totalMiningProfit, expire_count, ownerWeight[_addr]);
    }

    function addParentRewards(address sender, uint256 reward) internal{

        address parent = relation.Inviter(sender);
        uint256 parentReward = getIncome(parent);
        uint256 addReward = (reward > parentReward? parentReward:reward);
        addReward = addReward.mul(8).div(100);
        uint256 today = CSTDateTime.today();
        childRewardByDay[parent][today] += addReward;
        childCountByDay[parent][today]++;
        emit DirectReferralBonusRecorded(parent, sender, today, addReward);
    }

    function addStakePackage(address _addr, uint256 machineId, uint256 nodeId, uint256 times, uint256 _weight, bool isReward) external onlyAdmin{

        uint256 endId = endPledgeId[_addr];
        if(isReward){
            isRewardNode[_addr][endId] = true;
            receiveWeight[_addr] += _weight;
        }else{
            uint256 was = ownerWeight[_addr];
            ownerWeight[_addr] += _weight;
            if (was == 0 && ownerWeight[_addr] > 0) {
                address parent = relation.Inviter(_addr);
                if (parent != address(0)) {
                    if (activeDirectIndex[parent][_addr] == 0) {
                        activeDirects[parent].push(_addr);
                        activeDirectIndex[parent][_addr] = activeDirects[parent].length;
                    }
                }
            }
        }
        pledgeTypeId[_addr][endId] = nodeId;
        miningIds[_addr].push(endId);
        unusedTimes[_addr][endId] = times;
        exchangeTime[_addr][endId] = block.timestamp;
        pledgeExpireTime[_addr][endId] = block.timestamp + times.mul(86400);
        miningIdToMachineId[_addr][endId] = machineId;
        endPledgeId[_addr]++;
        ( , uint256 price, , uint256 apr) = xmtPool.getNodeDetail(nodeId);
        if (times > 0) {
            totalUnreleasedOwner = totalUnreleasedOwner.add(price);
            uint256 profitDaily = price.mul(apr).div(10000);
            if (profitDaily > 0) {
                totalUnreleasedProfit = totalUnreleasedProfit.add(profitDaily.mul(times));
            }
        }
        emit AddStake(_addr, machineId, nodeId, times, _weight, isReward, endId);
    }

    function updateStakeIds(address _addr,uint256 _expire_count) internal {

        uint256 length = miningIds[_addr].length;
        uint256[] memory newIds = new uint256[](length - _expire_count);
        uint256 index = 0;
        for(uint256 j=0; j<length; j++){
            uint256 j_index = miningIds[_addr][j];
            if(unusedTimes[_addr][j_index] > 0){
                newIds[index] = j_index;
                ++index;
            }
        }
        miningIds[_addr] = newIds;
    }

    function getIncome(address _addr) public view returns(uint256){
        uint256 length = miningIds[_addr].length;
        uint256 incomeReward =0;
        for(uint256 i=0; i<length; i++){
            uint256 index = miningIds[_addr][i];
            uint256 typeId = pledgeTypeId[_addr][index];
            (,uint256 price,, uint256 apr) = xmtPool.getNodeDetail(typeId);
            if(!isRewardNode[_addr][index]){
                incomeReward += price.mul(apr).div(10000);
            }
        }
        return incomeReward;
    }

    function getUserMiningReward(address _addr) external view returns(
        uint256 principalRelease,
        uint256 totalMiningProfit,
        uint256 netMiningProfit,
        uint256 totalReward
    ) {
        uint256 length = miningIds[_addr].length;
        principalRelease = 0;
        totalMiningProfit = 0;
        netMiningProfit = 0;
        for(uint256 i=0; i<length; i++){
            uint256 index = miningIds[_addr][i];
            if(unusedTimes[_addr][index] == 0){
                continue;
            }

            uint256 typeId = pledgeTypeId[_addr][index];
            ( , uint256 price, uint256 day, uint256 apr) = xmtPool.getNodeDetail(typeId);
            uint256 ownerDaily = price.div(day);
            uint256 profitDaily = price.mul(apr).div(10000);
            principalRelease = principalRelease.add(ownerDaily);
            totalMiningProfit = totalMiningProfit.add(profitDaily);
            if(!isRewardNode[_addr][index]){
                netMiningProfit = netMiningProfit.add(profitDaily);
            }
        }
        totalReward = principalRelease.add(totalMiningProfit);
    }

    function getTodayTimestamp() public view returns (uint256) {
        return CSTDateTime.today();
    }

    function getUserWeight(address[] memory _addrs) public view returns(uint256[] memory){
        uint256[] memory weights = new uint256[](_addrs.length);
        for(uint256 i=0; i<_addrs.length; i++){
            weights[i] = ownerWeight[_addrs[i]];
        }
        return weights;
    }

    function getGlobalTodayRelease() external view returns (uint256 xmtTotal, uint256 passTotal) {
        uint256 todayTs = CSTDateTime.today();
        xmtTotal = globalDailyXmtReleased[todayTs];
        passTotal = globalDailyPassRecorded[todayTs];
    }

    function getGlobalReleasesByDays(uint256[] calldata dayStarts)
        external
        view
        returns (uint256[] memory xmtTotals, uint256[] memory passTotals)
    {
        xmtTotals = new uint256[](dayStarts.length);
        passTotals = new uint256[](dayStarts.length);
        for (uint256 i = 0; i < dayStarts.length; i++) {
            uint256 day = dayStarts[i];
            xmtTotals[i] = globalDailyXmtReleased[day];
            passTotals[i] = globalDailyPassRecorded[day];
        }
    }

    function getTotalUnreleased() external view returns (uint256 ownerOutstanding, uint256 profitOutstanding, uint256 total) {
        ownerOutstanding = totalUnreleasedOwner;
        profitOutstanding = totalUnreleasedProfit;
        total = ownerOutstanding.add(profitOutstanding);
    }

    function getStarDailyReward(uint256 starLevel) public pure returns (uint256) {
        if(starLevel == 0){
            return 0;
        }
        uint256[8] memory rewards = _starDailyRewards();
        return rewards[starLevel - 1];
    }

    function _starDailyRewards() internal pure returns (uint256[8] memory rewards) {
        rewards = [
            uint256(140000000000000000),
            uint256(840000000000000000),
            uint256(3840000000000000000),
            uint256(11340000000000000000),
            uint256(43340000000000000000),
            uint256(128340000000000000000),
            uint256(488340000000000000000),
            uint256(1488340000000000000000)
        ];
    }

     function _verifySignature(address user, uint256 star, uint256 signedBlock, bytes calldata signature) internal {
        require(stakeSigner != address(0), "signer unset");
        require(block.number >= signedBlock, "signature future");
        require(block.number - signedBlock <= 200, "signature expired");
        require(star <= 8, "star invalid");
        require(verifySig(user, star, signedBlock, signature) == stakeSigner, "bad signature");
        nonce[user] = nonce[user].add(1);
    }

    function verifySig(

        address sender,
        uint256 star,
        uint256 blockNumber,
        bytes calldata signature
    ) public view returns(address)  {
        bytes32 messageHash = keccak256(
            abi.encodePacked(sender, star, blockNumber, nonce[sender])
        );
        return (messageHash.toEthSignedMessageHash().recover(signature));
    }

    function clearUserDataBatch(address[] memory users) external onlyAdmin {
        for (uint256 u = 0; u < users.length; u++) {
            address user = users[u];
            uint256[] memory mids = miningIds[user];
            for (uint256 i = 0; i < mids.length; i++) {
                uint256 miningIndex = mids[i];
                if (unusedTimes[user][miningIndex] > 0) {
                    uint256 nodeId = pledgeTypeId[user][miningIndex];
                    ( , uint256 price, , uint256 apr) = xmtPool.getNodeDetail(nodeId);
                    if (price > 0) {
                        totalUnreleasedOwner = totalUnreleasedOwner.sub(price);
                    }

                    uint256 profitDaily = price.mul(apr).div(10000);
                    if (profitDaily > 0 && unusedTimes[user][miningIndex] > 0) {
                        uint256 remainingProfit = profitDaily.mul(unusedTimes[user][miningIndex]);
                        totalUnreleasedProfit = totalUnreleasedProfit.sub(remainingProfit);
                    }
                }
            }

            address parent = relation.Inviter(user);
            if (parent != address(0)) {
                uint256 idxPlus = activeDirectIndex[parent][user];
                if (idxPlus > 0) {
                    uint256 arrLength = activeDirects[parent].length;
                    if (arrLength > 0) {
                        uint256 idx = idxPlus - 1;
                        require(idx < arrLength, "index out of bounds");
                        uint256 lastIdx = arrLength - 1;
                        if (idx != lastIdx) {
                            address lastChild = activeDirects[parent][lastIdx];
                            activeDirects[parent][idx] = lastChild;
                            activeDirectIndex[parent][lastChild] = idx + 1;
                        }
                        activeDirects[parent].pop();
                    }
                    activeDirectIndex[parent][user] = 0;
                }
            }
            delete claimTime[user];
            delete miningIds[user];
            delete ownerWeight[user];
            delete endPledgeId[user];
            delete receiveWeight[user];
            delete nonce[user];
            for (uint256 i = 0; i < mids.length; i++) {
                uint256 miningIndex = mids[i];
                delete unusedTimes[user][miningIndex];
                delete pledgeExpireTime[user][miningIndex];
                delete pledgeTypeId[user][miningIndex];
                delete exchangeTime[user][miningIndex];
                delete miningIdToMachineId[user][miningIndex];
                delete isRewardNode[user][miningIndex];
            }
            delete activeDirects[user];
        }
    }
}