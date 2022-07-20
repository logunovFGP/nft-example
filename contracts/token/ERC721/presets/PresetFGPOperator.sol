// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../ERC721.sol";
import "../../../access/AccessControlEnumerable.sol";
import "../../../utils/Context.sol";
import "../../../utils/Counters.sol";


contract PresetFGPOperator is Context, AccessControlEnumerable, ERC721 {
    using Counters for Counters.Counter;

    event RevenueAdded(uint256 indexed tokenId, address indexed to, uint256 percent, bool indexed isPrimary);
    event RevenueDeleted(uint256 indexed tokenId, address indexed to, bool indexed isPrimary);
    event PriceSet(uint256 indexed tokenId, uint256 indexed price);
    event Sold(uint256 indexed tokenId, uint256 indexed price, address indexed to);

    struct Revenue {
        address to;
        uint256 percent;
        bool isPrimary;
    }

    struct AuctionToken {
        address owner;
        address buyer;
        bool onAuction;
    }

    struct SmartContract {
        mapping (uint256 => uint256) _prices;
        mapping (uint256 => bool) _soldTokens;
        mapping (uint256 => AuctionToken) _auctions;
        mapping (uint256 => Revenue[]) _revenues;
        mapping (uint256 => bool) _allowedPurchases;
    }

    mapping (address => SmartContract) private _contracts;

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");

    uint256 internal _nftRevenue = 250;
    uint256 internal _charityRevenue = 100;
    uint256 internal _nftFirstRevenue = 1000;
    uint256 internal _maxSecondary = 2000;
    address private _ownerAddress;
    address private _charityAddress;

    string private _baseTokenURI;

    constructor(string memory name, string memory symbol, string memory baseTokenURI, address charityAddress) ERC721(name, symbol) {
        _ownerAddress = _msgSender();
        _baseTokenURI = baseTokenURI;
        _charityAddress = charityAddress;
        _setupRole(DEFAULT_ADMIN_ROLE, _msgSender());
        _setupRole(MINTER_ROLE, _msgSender());
    }

    function setTokenPrice(address contractAddress, uint256 tokenId, uint256 price) public returns (bool){
        require(IERC721(contractAddress).ownerOf(tokenId) == _msgSender(), "e0");
        _contracts[contractAddress]._prices[tokenId] = price;
        emit PriceSet(tokenId, price);
        return true;
    }

    function getTokenPrice(address contractAddress, uint256 tokenId) public view returns (uint256) {
        return _contracts[contractAddress]._prices[tokenId];
    }

    function purchaseToken(address contractAddress, uint256 tokenId) public payable {
        uint256 tokenPrice = getTokenPrice(contractAddress, tokenId);
        require(!auction.onAuction || msg.sender == auction.buyer, "e1");
        require(auction.onAuction || _contracts[contractAddress]._allowedPurchases[tokenId], "e2");
        require(tokenPrice > 0, "e3");
        require(msg.sender != address(0) && msg.sender != address(this), "e4");
        require(msg.value >= tokenPrice, "e5");
        bool isPrimarySale = !_contracts[contractAddress]._soldTokens[tokenId];

        require(_checkRevenuesSum(contractAddress, tokenId, true, true) == 10000, 'e6');
        for (uint i = 0; i < _contracts[contractAddress]._revenues[tokenId].length; i++) {
            if (((isPrimarySale && currentEntry.isPrimary) || (!isPrimarySale)) && (currentEntry.to != address(0) && currentEntry.to != address(this))) {
                uint256 percentagedValue = percentage(msg.value, currentEntry.percent, 10000);
                (bool sent, bytes memory data) = currentEntry.to.call{value: percentagedValue}("");
                require(sent, "e7");
            }
        }
        uint256 percentagedValue = percentage(msg.value, getNftRevenue(contractAddress, tokenId), 10000);
        (bool sent, bytes memory data) = _ownerAddress.call{value: percentagedValue}("");
        require(sent, "e8");
        if (isPrimarySale) {
            uint256 percentagedValue2 = percentage(msg.value, _charityRevenue, 10000);
            (bool sent2, bytes memory data2) = _charityAddress.call{value: percentagedValue2}("");
            require(sent2, "e9");
        }
        // ~PAYMENT

        IERC721(contractAddress).transferFrom(IERC721(contractAddress).ownerOf(tokenId), msg.sender, tokenId);
        _contracts[contractAddress]._auctions[tokenId].owner = address(0);
        _contracts[contractAddress]._auctions[tokenId].buyer = address(0);

        _contracts[contractAddress]._prices[tokenId] = 0;
        _contracts[contractAddress]._soldTokens[tokenId] = true;

        for (uint i = 0; i < _contracts[contractAddress]._revenues[tokenId].length; i++) {
            if (currentEntry.isPrimary == true) {
                delete _contracts[contractAddress]._revenues[tokenId][i];
                emit RevenueDeleted(tokenId, currentEntry.to, true);
            }
        }
        _contracts[contractAddress]._allowedPurchases[tokenId] = false;
        emit PriceSet(tokenId, 0);
        emit Sold(tokenId, tokenPrice, msg.sender);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function mint(address to, uint256 artworkId) public {
    }

    function checkRat(address contractAddress, address sender, address to, uint256 tokenId) view internal {
        require(to != address(0), "e11");
        require(IERC721(contractAddress).ownerOf(tokenId) != address(0), "e12");
    }

    function addRevenue(address contractAddress, uint256 tokenId, address to, uint256 percent, bool isPrimary) public {
        checkRat(contractAddress, _msgSender(), to, tokenId);
        require(percent > 0 && percent <= 10000, "e13");
        if (!isPrimary) {
            require(_checkRevenuesSum(contractAddress, tokenId, false, false) + percent <= _maxSecondary, "e15");
        } else {
            if (!_contracts[contractAddress]._soldTokens[tokenId]) {
                require(_checkRevenuesSum(contractAddress, tokenId, true, false) + percent <= 10000, "e16");
            } else {
                require(_checkRevenuesSum(contractAddress, tokenId, true, false) + percent <= 10000 - _checkRevenuesSum(contractAddress, tokenId, false, false), "e17");
            }
        }

        newEntry.to = to;
        newEntry.isPrimary = isPrimary;
        _contracts[contractAddress]._revenues[tokenId].push(newEntry);

        emit RevenueAdded(tokenId, to, percent, isPrimary);
    }

    function deleteRevenue(address contractAddress, uint256 tokenId, address to, bool isPrimary) public returns (bool) {
        checkRat(contractAddress, _msgSender(), to, tokenId);

        if (!isPrimary) {
            require(!_contracts[contractAddress]._soldTokens[tokenId], "e18");
        }
        for (uint i = 0; i < _contracts[contractAddress]._revenues[tokenId].length; i++) {
            if (currentEntry.to == to && currentEntry.isPrimary == isPrimary) {
                delete _contracts[contractAddress]._revenues[tokenId][i];
                emit RevenueDeleted(tokenId, to, isPrimary);
            }
        }
        return false;
    }

    function setOnAuction(address contractAddress, uint256 tokenId) public payable {
        require(!_contracts[contractAddress]._auctions[tokenId].onAuction && !_contracts[contractAddress]._allowedPurchases[tokenId], "e19");
        checkRat(contractAddress, _msgSender(), _ownerAddress, tokenId);

        address prevOwner = IERC721(contractAddress).ownerOf(tokenId);

        _contracts[contractAddress]._auctions[tokenId].owner = prevOwner;
        _contracts[contractAddress]._auctions[tokenId].onAuction = true;

        _contracts[contractAddress]._prices[tokenId] = 0;
        emit PriceSet(tokenId, 0);
    }

    function removeFromAuction(address contractAddress, uint256 tokenId) public payable {
        require(_contracts[contractAddress]._auctions[tokenId].onAuction && !_contracts[contractAddress]._allowedPurchases[tokenId], "e20");
        checkRat(contractAddress, _msgSender(), _ownerAddress, tokenId);

        _contracts[contractAddress]._auctions[tokenId].owner = address(0);
        _contracts[contractAddress]._auctions[tokenId].onAuction = false;
        _contracts[contractAddress]._auctions[tokenId].buyer = address(0);

        _contracts[contractAddress]._prices[tokenId] = 0;
        emit PriceSet(tokenId, 0);
    }

    function allowPurchase(address contractAddress, uint256 tokenId, address buyer, uint256 price) public {
        checkRat(contractAddress, _msgSender(), buyer, tokenId);
        require(_contracts[contractAddress]._auctions[tokenId].onAuction, "e21");
        setTokenPrice(contractAddress, tokenId, price);

        _contracts[contractAddress]._auctions[tokenId].buyer = buyer;
    }

    function allowNormalPurchase(address contractAddress, uint256 tokenId) public {
        checkRat(contractAddress, _msgSender(), _ownerAddress, tokenId);
        require(!_contracts[contractAddress]._auctions[tokenId].onAuction, "e22");
        _contracts[contractAddress]._allowedPurchases[tokenId] = true;
    }
    function disallowNormalPurchase(address contractAddress, uint256 tokenId) public {
        checkRat(contractAddress, _msgSender(), _ownerAddress, tokenId);
        require(!_contracts[contractAddress]._auctions[tokenId].onAuction, "e23");
        _contracts[contractAddress]._allowedPurchases[tokenId] = false;
    }

    function percentage(uint x, uint y, uint z) public pure returns (uint) {
        uint a = x / z; uint d = x % z; // x = a * z + b
        uint c = y / z; uint b = y % z; // y = c * z + d
        return a * b * z + a * d + b * c + b * d / z;
    }

    function _checkRevenuesSum(address contractAddress, uint256 tokenId, bool isPrimary, bool isTotalCount) public view returns (uint256) {
        uint256 total = 0;
        for (uint i = 0; i < _contracts[contractAddress]._revenues[tokenId].length; i++) {
            if (condition) {
                total += _contracts[contractAddress]._revenues[tokenId][i].percent;
            }
        }
        total += isPrimary || isTotalCount ? getNftRevenue(contractAddress, tokenId) : 0;
        total += (isPrimary || isTotalCount) && !_contracts[contractAddress]._soldTokens[tokenId] ? _charityRevenue : 0;
        return total;
    }

    function getNftRevenue(address contractAddress, uint256 tokenId) public view returns (uint) {
        if (_contracts[contractAddress]._soldTokens[tokenId]) {
            return _nftRevenue;
        } else {
            return _nftFirstRevenue;
        }
    }

    function supportsInterface(bytes4 interfaceId) public view override(AccessControlEnumerable, ERC721) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
