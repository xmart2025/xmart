// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;
import "@openzeppelin/contracts/token/ERC1155/ERC1155.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

contract XMTNFT is ERC1155, Ownable {
    uint8 public SERIES_COUNT;

    struct SeriesInfo {
        string name;
        string baseURI;
        address creator;
        uint256 startId;
        uint256 endId;
        bool active;
    }

    mapping(uint8 => SeriesInfo) public series;
    mapping(uint256 => uint8) public tokenToSeries;
    mapping(address => uint256[]) private _ownedTokens;
    mapping(uint256 => mapping(address => uint256)) private _ownedTokensIndex;

    constructor() ERC1155("")  {
        SERIES_COUNT = 4;
        _createFixedSeries(1, "Genesis Diamond", "");
        _createFixedSeries(2, "Genesis Gold", "");
        _createFixedSeries(3, "Genesis Silver", "");
        _createFixedSeries(4, "Genesis Bronze", "");
    }

    function createFixedSeries(uint8 id, string memory name, string memory baseURI) external onlyOwner {
        SERIES_COUNT += 1;
        _createFixedSeries(id, name, baseURI);
    }

    function _createFixedSeries(uint8 id, string memory name, string memory baseURI) internal {
        require(id >= 1 && id <= SERIES_COUNT, "invalid series id");
        uint256 start = uint256(id) * 1_000_000;
        series[id] = SeriesInfo({
            name: name,
            baseURI: baseURI,
            creator: msg.sender,
            startId: start,
            endId: start,
            active: true
        });
    }

    function mint(

        uint8 seriesId,
        address to,
        uint256 amount,
        bytes memory data
    ) external onlyOwner {
        SeriesInfo storage s = series[seriesId];
        require(s.active, "series inactive");
        require(msg.sender == s.creator || msg.sender == owner(), "not allowed");
        uint256 tokenId = ++s.endId;
        tokenToSeries[tokenId] = seriesId;
        _mint(to, tokenId, amount, data);
    }

    function _beforeTokenTransfer(

        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override {
        super._beforeTokenTransfer(operator, from, to, ids, amounts, data);
        require(
            from == address(0),
            "This NFT is non-transferable, can only be minted"
        );
    }

    function uri(uint256 tokenId) public view override returns (string memory) {
        uint8 sid = tokenToSeries[tokenId];
        require(sid != 0, "invalid token");
        SeriesInfo storage s = series[sid];
        return string(abi.encodePacked(s.baseURI, _toString(tokenId)));
    }

    function setBaseURI(uint8 seriesId, string calldata baseURI) external {
        SeriesInfo storage s = series[seriesId];
        require(msg.sender == s.creator || msg.sender == owner(), "not allowed");
        s.baseURI = baseURI;
    }

    function setSeriesActive(uint8 seriesId, bool active) external {
        SeriesInfo storage s = series[seriesId];
        require(msg.sender == s.creator || msg.sender == owner(), "not allowed");
        s.active = active;
    }

    function getSeriesInfo(uint8 seriesId)
        external
        view
        returns (string memory name, string memory baseURI, address creator, uint256 startId, uint256 endId, bool active)
    {
        SeriesInfo storage s = series[seriesId];
        return (s.name, s.baseURI, s.creator, s.startId, s.endId, s.active);
    }

    function seriesOf(uint256 tokenId) external view returns (uint8) {
        return tokenToSeries[tokenId];
    }

    function tokensOf(address owner) external view returns (uint256[] memory) {
        return _ownedTokens[owner];
    }

    function _afterTokenTransfer(

        address operator,
        address from,
        address to,
        uint256[] memory ids,
        uint256[] memory amounts,
        bytes memory data
    ) internal override {
        super._afterTokenTransfer(operator, from, to, ids, amounts, data);
        for (uint256 i = 0; i < ids.length; i++) {
            uint256 id = ids[i];
            uint256 amount = amounts[i];
            if (from != address(0)) {
                if (balanceOf(from, id) == 0) {
                    _removeTokenFromOwnerEnumeration(from, id);
                }
            }
            if (to != address(0)) {
                if (amount > 0 && _ownedTokensIndex[id][to] == 0) {
                    _addTokenToOwnerEnumeration(to, id);
                }
            }
        }
    }

    function _addTokenToOwnerEnumeration(address to, uint256 tokenId) private {
        _ownedTokensIndex[tokenId][to] = _ownedTokens[to].length + 1;
        _ownedTokens[to].push(tokenId);
    }

    function _removeTokenFromOwnerEnumeration(address from, uint256 tokenId) private {

        uint256 indexPlusOne = _ownedTokensIndex[tokenId][from];
        if (indexPlusOne == 0) {
            return;
        }

        uint256 lastIndex = _ownedTokens[from].length - 1;
        uint256 removeIndex = indexPlusOne - 1;
        if (removeIndex != lastIndex) {
            uint256 lastTokenId = _ownedTokens[from][lastIndex];
            _ownedTokens[from][removeIndex] = lastTokenId;
            _ownedTokensIndex[lastTokenId][from] = indexPlusOne;
        }
        _ownedTokens[from].pop();
        delete _ownedTokensIndex[tokenId][from];
    }

    function _toString(uint256 value) internal pure returns (string memory) {
        if (value == 0) return "0";
        uint256 temp = value;
        uint256 digits;
        while (temp != 0) {
            digits++;
            temp /= 10;
        }

        bytes memory buffer = new bytes(digits);
        while (value != 0) {
            digits -= 1;
            buffer[digits] = bytes1(uint8(48 + uint256(value % 10)));
            value /= 10;
        }
        return string(buffer);
    }
}