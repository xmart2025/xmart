// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/token/ERC20/IERC20Upgradeable.sol";
import "@openzeppelin/contracts-upgradeable/utils/math/SafeMathUpgradeable.sol";
import "./XMTNFT.sol";
import "./XMTRelation.sol";
import "./AdminRoleUpgrade.sol";

interface IXMTpassAirdrop {

    function setAllocation(address user, uint256 allocation) external;
}

contract XMTNFTSale is AdminRoleUpgrade, Initializable {

    using SafeMathUpgradeable for uint256;

    struct NFTPrice {
        uint256 diamond;
        uint256 gold;
        uint256 silver;
        uint256 bronze;
    }

    XMTNFT public xmtNFT;
    XMTRelation public xmtRelation;
    IERC20Upgradeable public usdtToken;
    IXMTpassAirdrop public xmtpassAirdrop;
    NFTPrice public prices;
    uint256 public constant REFERRAL_REWARD_RATIO = 5;
    mapping(address => uint256) public referralRewards;
    mapping(address => uint256) public totalClaimedRewards;
    mapping(address => bool) public hasPurchased;
    uint256 public constant TOTAL_SALE_CAP = 2_000_000 * 10**18;
    uint256 public totalSoldAmount;
    mapping(uint8 => uint256) public seriesPurchaseCount;

    struct PurchaseInfo {
        uint8 seriesId;
        uint256 timestamp;
        uint256 price;
        uint256 allocation;
        uint256 tokenId;
    }

    mapping(address => PurchaseInfo) public purchases;
   mapping(address => uint256[]) public userPurchasedSeriesIds;

    event NFTBought(
        address indexed buyer,
        address indexed referrer,
        uint8 seriesId,
        uint256 amount,
        uint256 price
    );

    event ReferralRewardPaid(
        address indexed referrer,
        address indexed buyer,
        uint256 amount
    );

    function setAboutAddress(address _xmtNFT, address _xmtRelation, address _usdtToken, address _airdrop) external onlyAdmin {
        require(_xmtNFT != address(0) && _xmtRelation != address(0) && _usdtToken != address(0) && _airdrop != address(0), "Invalid address");
        xmtNFT = XMTNFT(_xmtNFT);
        xmtRelation = XMTRelation(_xmtRelation);
        usdtToken = IERC20Upgradeable(_usdtToken);
        xmtpassAirdrop = IXMTpassAirdrop(_airdrop);
    }

    function initialize() public initializer {
        _addAdmin(msg.sender);
        prices = NFTPrice({
            diamond: 1000 * 10**18,
            gold: 500 * 10**18,
            silver: 100 * 10**18,
            bronze: 10 * 10**18
        });
    }

    function buyNFT(

        uint8 seriesId
    ) external {
        require(seriesId >= 1 && seriesId <= 4, "Invalid series ID");
        require(!hasPurchased[msg.sender], "Each address can only purchase one NFT");
        uint256 price = getPriceBySeries(seriesId);
        require(totalSoldAmount.add(price) <= TOTAL_SALE_CAP, "Sale cap exceeded");
        address referrer = xmtRelation.Inviter(msg.sender);
        require(
            usdtToken.transferFrom(msg.sender, address(this), price),
            "USDT transfer failed"
        );
        totalSoldAmount = totalSoldAmount.add(price);
        seriesPurchaseCount[seriesId] = seriesPurchaseCount[seriesId].add(1);
        if (referrer != address(0)) {
            uint256 referralReward = price.mul(REFERRAL_REWARD_RATIO).div(100);
            if (referralReward > 0) {
                referralRewards[referrer] = referralRewards[referrer].add(referralReward);
                emit ReferralRewardPaid(referrer, msg.sender, referralReward);
            }
        }
        xmtNFT.mint(seriesId, msg.sender, 1, "");
        uint256 allocation = _setAirdropAllocation(msg.sender, seriesId);
        uint256[] memory tokens = xmtNFT.tokensOf(msg.sender);
        uint256 mintedTokenId = tokens.length > 0 ? tokens[0] : 0;
        purchases[msg.sender] = PurchaseInfo({
            seriesId: seriesId,
            timestamp: block.timestamp,
            price: price,
            allocation: allocation,
            tokenId: mintedTokenId
        });
        userPurchasedSeriesIds[msg.sender].push(uint256(seriesId));
        hasPurchased[msg.sender] = true;
        emit NFTBought(msg.sender, referrer, seriesId, 1, price);
    }

   function getXmtpassAmount() external view returns (uint256) {
        return totalSoldAmount.mul(4);
   }

    function getPriceBySeries(uint8 seriesId) public view returns (uint256) {
        if (seriesId == 1) return prices.diamond;
        if (seriesId == 2) return prices.gold;
        if (seriesId == 3) return prices.silver;
        if (seriesId == 4) return prices.bronze;
        revert("Invalid series ID");
    }

    function setPrices(

        uint256 _diamond,
        uint256 _gold,
        uint256 _silver,
        uint256 _bronze
    ) external onlyAdmin {
        prices.diamond = _diamond;
        prices.gold = _gold;
        prices.silver = _silver;
        prices.bronze = _bronze;
    }

    function withdrawUSDT(address to, uint256 amount) external onlyAdmin {
        require(
            usdtToken.transfer(to, amount),
            "Withdrawal failed"
        );
    }

    function claimReferralReward() external {

        uint256 reward = referralRewards[msg.sender];
        require(reward > 0, "No referral reward to claim");
        referralRewards[msg.sender] = 0;
        totalClaimedRewards[msg.sender] = totalClaimedRewards[msg.sender].add(reward);
        require(
            usdtToken.transfer(msg.sender, reward),
            "Referral reward transfer failed"
        );
        emit ReferralRewardPaid(msg.sender, address(0), reward);
    }

    function getClaimableReward(address referrer) external view returns (uint256) {
        return referralRewards[referrer];
    }

    function getClaimedReward(address referrer) external view returns (uint256) {
        return totalClaimedRewards[referrer];
    }

    function _setAirdropAllocation(address user, uint8 seriesId) internal returns (uint256) {
        uint256 allocation;
        if (seriesId == 1) {
            allocation = 4000 * 10**18;
        } else if (seriesId == 2) {
            allocation = 2000 * 10**18;
        } else if (seriesId == 3) {
            allocation = 400 * 10**18;
        } else if (seriesId == 4) {
            allocation = 40 * 10**18;
        } else {
            return 0;
        }
        xmtpassAirdrop.setAllocation(user, allocation);
        return allocation;
    }

    function getUserPurchase(address user) external view returns (
        uint8 seriesId,
        uint256 timestamp,
        uint256 price,
        uint256 allocation,
        uint256 tokenId
    ) {
        PurchaseInfo storage p = purchases[user];
        return (p.seriesId, p.timestamp, p.price, p.allocation, p.tokenId);
    }

    function getseriesPurchaseCounts() external view returns (uint256[] memory) {
        uint256[] memory counts = new uint256[](4);
        for (uint8 i = 1; i <= 4; i++) {
            counts[i - 1] = seriesPurchaseCount[i];
        }
        return counts;
    }
}