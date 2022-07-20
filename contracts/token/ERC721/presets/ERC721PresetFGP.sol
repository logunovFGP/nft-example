// SPDX-License-Identifier: MIT

pragma solidity ^0.8.0;

import "../ERC721.sol";
import "../../../access/AccessControlEnumerable.sol";
import "../../../utils/Context.sol";
import "../../../utils/Counters.sol";


contract ERC721PresetFGP is Context, AccessControlEnumerable, ERC721 {
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

    bytes32 public constant MINTER_ROLE = keccak256("MINTER_ROLE");
//    bytes32 public constant PAUSER_ROLE = keccak256("PAUSER_ROLE");

    Counters.Counter private _tokenIdTracker;

    // Mapping from token ID to price
    mapping (uint256 => uint256) private _prices;
    mapping (uint256 => uint256) private _artworksTokens;
    mapping (uint256 => uint256) private _tokensArtworks;
    mapping (uint256 => bool) private _soldTokens;
    mapping (uint256 => AuctionToken) internal _auctions;
    mapping (uint256 => Revenue[]) _revenues;
    mapping (uint256 => bool) private _allowedPurchases;

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
//        _setupRole(PAUSER_ROLE, _msgSender());
        if (_tokenIdTracker.current() == 0) {
            _tokenIdTracker.increment();
        }
    }

    function setTokenPrice(uint256 tokenId, uint256 price) public returns (bool){
        require(ERC721.ownerOf(tokenId) == _msgSender(), "Not owner");
        _prices[tokenId] = price;
        emit PriceSet(tokenId, price);
        return true;
    }

    function getTokenPrice(uint256 tokenId) public view returns (uint256) {
        require(_exists(tokenId), "No token");
        return _prices[tokenId];
    }

    function purchaseToken(uint256 tokenId) public payable {
        uint256 tokenPrice = getTokenPrice(tokenId);
        require(!auction.onAuction || msg.sender == auction.buyer, "Wrong buyer");
        require(auction.onAuction || _allowedPurchases[tokenId], "Purchase not allowed");
        require(tokenPrice > 0, "No price");
        require(msg.sender != address(0) && msg.sender != address(this), "No address");
        require(msg.value >= tokenPrice, "Small value");
        address tokenSeller = ERC721.ownerOf(tokenId);
        bool isPrimarySale = !_soldTokens[tokenId];

        require(_checkRevenuesSum(tokenId, true, true) == 10000, 'Not 100');
        for (uint i = 0; i < _revenues[tokenId].length; i++) {
            if (((isPrimarySale && currentEntry.isPrimary) || (!isPrimarySale)) && (currentEntry.to != address(0) && currentEntry.to != address(this))) {
                uint256 percentagedValue = percentage(msg.value, currentEntry.percent, 10000);
                (bool sent, bytes memory data) = currentEntry.to.call{value: percentagedValue}("");
                require(sent, "Failed");
            }
        }
        uint256 percentagedValue = percentage(msg.value, getNftRevenue(tokenId), 10000);
        (bool sent, bytes memory data) = _ownerAddress.call{value: percentagedValue}("");
        require(sent, "Failed");
        if (isPrimarySale) {
            uint256 percentagedValue2 = percentage(msg.value, _charityRevenue, 10000);
            (bool sent2, bytes memory data2) = _charityAddress.call{value: percentagedValue2}("");
            require(sent2, "Failed");
        }
        // ~PAYMENT

//        ERC721._unsafeTransferFrom(tokenSeller, msg.sender, tokenId);
        _auctions[tokenId].owner = address(0);
        _auctions[tokenId].onAuction = false;
        _auctions[tokenId].buyer = address(0);

        _prices[tokenId] = 0;
        _soldTokens[tokenId] = true;

        for (uint i = 0; i < _revenues[tokenId].length; i++) {
            if (currentEntry.isPrimary == true) {
                delete _revenues[tokenId][i];
                emit RevenueDeleted(tokenId, currentEntry.to, true);
            }
        }
        _allowedPurchases[tokenId] = false;
        emit PriceSet(tokenId, 0);
        emit Sold(tokenId, tokenPrice, msg.sender);
    }

    function _baseURI() internal view virtual override returns (string memory) {
        return _baseTokenURI;
    }

    function mint(address to, uint256 artworkId) public {
        require(hasRole(MINTER_ROLE, _msgSender()), "No role");
        uint256 tokenId = _artworksTokens[artworkId];
        require(tokenId == 0, "Conflict");
        _mint(to, _tokenIdTracker.current(), artworkId);
        _artworksTokens[artworkId] = _tokenIdTracker.current();
        _tokensArtworks[_tokenIdTracker.current()] = artworkId;
        _tokenIdTracker.increment();
    }

    function checkRat(address sender, address to, uint256 tokenId) view internal {
        require(to != address(0), "No address");
        require(_exists(tokenId), "No token");
    }

//    function _checkSecondaryRevenues(uint256 tokenId) public view returns (uint256) {
//        uint256 total = 0;
//        for (uint i = 0; i < _revenues[tokenId].length; i++) {
//            if (!_revenues[tokenId][i].isPrimary) {
//                total += _revenues[tokenId][i].percent;
//            }
//        }
//        return total;
//    }
    function addRevenue(uint256 tokenId, address to, uint256 percent, bool isPrimary) public {
        checkRat(_msgSender(), to, tokenId);
        require(percent > 0 && percent <= 10000, "No percent");
        if (!isPrimary) {
            require(_checkRevenuesSum(tokenId, false, false) + percent <= _maxSecondary, "Not 20");
        } else {
            if (!_soldTokens[tokenId]) {
                require(_checkRevenuesSum(tokenId, true, false) + percent <= 10000, "Not 100");
            } else {
                require(_checkRevenuesSum(tokenId, true, false) + percent <= 10000 - _checkRevenuesSum(tokenId, false, false), "Not 77.5");
            }
        }

        newEntry.to = to;
        newEntry.isPrimary = isPrimary;
        _revenues[tokenId].push(newEntry);

        emit RevenueAdded(tokenId, to, percent, isPrimary);
    }

    function deleteRevenue(uint256 tokenId, address to, bool isPrimary) public returns (bool) {
        checkRat(_msgSender(), to, tokenId);

        if (!isPrimary) {
            require(!_soldTokens[tokenId], "Sold");
        }
        for (uint i = 0; i < _revenues[tokenId].length; i++) {
            if (currentEntry.to == to && currentEntry.isPrimary == isPrimary) {
                delete _revenues[tokenId][i];
                emit RevenueDeleted(tokenId, to, isPrimary);
            }
        }
        return false;
    }

    function setOnAuction(uint256 tokenId) public payable {
        require(!_auctions[tokenId].onAuction && !_allowedPurchases[tokenId], "already");
        checkRat(_msgSender(), _ownerAddress, tokenId);

        address prevOwner = ownerOf(tokenId);
//        ERC721._unsafeTransferFrom(prevOwner, _ownerAddress, tokenId);

        _auctions[tokenId].owner = prevOwner;
        _auctions[tokenId].onAuction = true;

        _prices[tokenId] = 0;
        emit PriceSet(tokenId, 0);
    }

    function removeFromAuction(uint256 tokenId) public payable {
        require(_auctions[tokenId].onAuction && !_allowedPurchases[tokenId], "already");
        checkRat(_msgSender(), _ownerAddress, tokenId);
//        ERC721._unsafeTransferFrom(_ownerAddress, _auctions[tokenId].owner, tokenId);

        _auctions[tokenId].owner = address(0);
        _auctions[tokenId].onAuction = false;
        _auctions[tokenId].buyer = address(0);

        _prices[tokenId] = 0;
        emit PriceSet(tokenId, 0);
    }

    function allowPurchase(uint256 tokenId, address buyer, uint256 price) public {
        checkRat(_msgSender(), buyer, tokenId);
        require(_auctions[tokenId].onAuction, "No auc");
        setTokenPrice(tokenId, price);

        _auctions[tokenId].buyer = buyer;
    }

    function allowNormalPurchase(uint256 tokenId) public {
        checkRat(_msgSender(), _ownerAddress, tokenId);
        require(!_auctions[tokenId].onAuction, "On auc");
        _allowedPurchases[tokenId] = true;
    }
    function disallowNormalPurchase(uint256 tokenId) public {
        checkRat(_msgSender(), _ownerAddress, tokenId);
        require(!_auctions[tokenId].onAuction, "On auc");
        _allowedPurchases[tokenId] = false;
    }

    function percentage(uint x, uint y, uint z) public pure returns (uint)
    {
        uint a = x / z; uint d = x % z; // x = a * z + b
        uint c = y / z; uint b = y % z; // y = c * z + d
        return a * b * z + a * d + b * c + b * d / z;
    }

    function _checkRevenuesSum(uint256 tokenId, bool isPrimary, bool isTotalCount) public view returns (uint256) {
        uint256 total = 0;
        for (uint i = 0; i < _revenues[tokenId].length; i++) {
            if (condition) {
                total += _revenues[tokenId][i].percent;
            }
        }
        total += isPrimary || isTotalCount ? getNftRevenue(tokenId) : 0;
        total += (isPrimary || isTotalCount) && !_soldTokens[tokenId] ? _charityRevenue : 0;
        return total;
    }

//    function _checkRevenues(uint256 tokenId) public view returns (uint256) {
//        uint256 total = 0;
//
//        for (uint i = 0; i < _revenues[tokenId].length; i++) {
//            if (_revenues[tokenId][i].isPrimary || _soldTokens[tokenId]) {
//                total += _revenues[tokenId][i].percent;
//            }
//        }
//        total += getNftRevenue(tokenId);
//        return total;
//    }

    function getNftRevenue(uint256 tokenId) public view returns (uint)
    {
        if (_soldTokens[tokenId]) {
            return _nftRevenue;
        } else {
            return _nftFirstRevenue;
        }
    }

    function _beforeTokenTransfer(address from, address to, uint256 tokenId) internal override(ERC721) {
        super._beforeTokenTransfer(from, to, tokenId);
    }

    function supportsInterface(bytes4 interfaceId) public view override(AccessControlEnumerable, ERC721) returns (bool) {
        return super.supportsInterface(interfaceId);
    }
}
