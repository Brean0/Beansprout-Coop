// SPDX-License-Identifier: GPL-3.0
pragma solidity ^0.8.10;

import "openzeppelin-contracts/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "openzeppelin-contracts/contracts/token/ERC20/IERC20.sol";
import "openzeppelin-contracts/contracts/access/Ownable.sol";
import "openzeppelin-contracts/contracts/utils/math/Math.sol";
import "./Interfaces/IBondNFT.sol";
import "./utils/Base64.sol";

//import "forge-std/console.sol";

contract BondNFT is ERC721Enumerable, Ownable, IBondNFT {

    uint256 public constant CURVE_GAUGE_SLOPES_PRECISION = 1e9; // The minimum slope to get extra weight 1e-9
    uint256 public constant TRANSFER_LOCKOUT_PERIOD = 3600; // 1 hour

    IChickenBondManager public chickenBondManager;

    string[4][16] palette = [
        ["#eca3f5", "#fdbaf9", "#b0efeb", "#edffa9"],
        ["#75cfb8", "#bbdfc8", "#f0e5d8", "#ffc478"],
        ["#ffab73", "#ffd384", "#fff9b0", "#ffaec0"],
        ["#94b4a4", "#d2f5e3", "#e5c5b5", "#f4d9c6"],
        ["#f4f9f9", "#ccf2f4", "#a4ebf3", "#aaaaaa"],
        ["#caf7e3", "#edffec", "#f6dfeb", "#e4bad4"],
        ["#f4f9f9", "#f1d1d0", "#fbaccc", "#f875aa"],
        ["#fdffbc", "#ffeebb", "#ffdcb8", "#ffc1b6"],
        ["#f0e4d7", "#f5c0c0", "#ff7171", "#9fd8df"],
        ["#e4fbff", "#b8b5ff", "#7868e6", "#edeef7"],
        ["#ffcb91", "#ffefa1", "#94ebcd", "#6ddccf"],
        ["#bedcfa", "#98acf8", "#b088f9", "#da9ff9"],
        ["#bce6eb", "#fdcfdf", "#fbbedf", "#fca3cc"],
        ["#ff75a0", "#fce38a", "#eaffd0", "#95e1d3"],
        ["#fbe0c4", "#8ab6d6", "#2978b5", "#0061a8"],
        ["#dddddd", "#f9f3f3", "#f7d9d9", "#f25287"]
    ];

    string[4] _status = [
        "Inactive",
        "Egg",
        "Chicken In",
        "Chicken Out"
    ];

    constructor(string memory name_, string memory symbol_) ERC721(name_, symbol_) { }

    function setAddresses(address _chickenBondManagerAddress) external onlyOwner {
        require(_chickenBondManagerAddress != address(0), "BondNFT: _chickenBondManagerAddress must be non-zero");
        require(address(chickenBondManager) == address(0), "BondNFT: setAddresses() can only be called once");

        chickenBondManager = IChickenBondManager(_chickenBondManagerAddress);
    }

    function mint(address _bonder) external returns (uint256) {
        requireCallerIsChickenBondsManager();

        // We actually increase totalSupply in `ERC721Enumerable._beforeTokenTransfer` when we `_mint`.
        uint256 bondId = totalSupply() + 1;
        super._mint(_bonder, bondId);
        return bondId;
    }

    // Prevent transfers for a period of time after chickening in or out
    function _beforeTokenTransfer(address _from, address _to, uint256 _bondId) internal virtual {
        if (_from != address(0)) {
            IChickenBondManager.BondData memory _tmpBondData = chickenBondManager.getBondData(_bondId);

            require(
                _tmpBondData.status == IChickenBondManager.BondStatus.active ||
                block.timestamp >= _tmpBondData.endTime + TRANSFER_LOCKOUT_PERIOD,
                "BondNFT: cannot transfer during lockout period"
            );
        }

        super._beforeTokenTransfer(_from, _to, _bondId,1);
    }

    function tokenURI(uint256 _bondId) public view virtual override returns (string memory) {
        require(_exists(_bondId), "ERC721Metadata: URI query for nonexistent token");
        string memory name = string(abi.encodePacked(' Beansprout Bond #', toString(_bondId)));
        string memory description = "Beansprout Coop";
        string memory image = generateBase64Image(_bondId);
            
        return string(
            abi.encodePacked(
                'data:application/json;base64,',
                Base64.encode(
                    bytes(
                        abi.encodePacked(
                            '{"name":"', 
                            name,
                            '", "description":"', 
                            description,
                            '", "image": "', 
                            'data:image/svg+xml;base64,', 
                            image,
                            '"}'
                        )
                    )
                )
            )
        );
    }

    function getBondAmount(uint256 _bondId) public view returns (uint256 amount) {
        IChickenBondManager.BondData memory _tmpBondData = chickenBondManager.getBondData(_bondId);
        return _tmpBondData.amount;
    }

    function getBondRootBDV(uint256 _bondId) external view returns (uint256 rootBDV) {
        IChickenBondManager.BondData memory _tmpBondData = chickenBondManager.getBondData(_bondId);
        return _tmpBondData.rootBDV;
    }

    function getBondStartTime(uint256 _bondId) public view returns (uint256 startTime) {
        IChickenBondManager.BondData memory _tmpBondData = chickenBondManager.getBondData(_bondId);
        return _tmpBondData.startTime;
    }

    function getBondStatus(uint256 _bondId) public view returns (IChickenBondManager.BondStatus status) {
        IChickenBondManager.BondData memory _tmpBondData = chickenBondManager.getBondData(_bondId);
        return _tmpBondData.status;
    }

    function getBondEndTime(uint256 _bondId) external view returns (uint256 endTime) {
        IChickenBondManager.BondData memory _tmpBondData = chickenBondManager.getBondData(_bondId);
        return _tmpBondData.endTime;
    }

    function getBondClaimedBRoot(uint256 _bondId) public view returns (uint256 claimedBRoot) {
        IChickenBondManager.BondData memory _tmpBondData = chickenBondManager.getBondData(_bondId);
        return _tmpBondData.claimedBRoot;
    }

    function generateBase64Image(uint256 _bondId) internal view returns (string memory) {
        return Base64.encode(bytes(generateImage(_bondId)));
    }

    function generateImage(uint256 _bondId) internal view returns (string memory) {
        // get the hash as a function of both start time and bondId
        IChickenBondManager.BondData memory _tmpBond;
        _tmpBond = chickenBondManager.getBondData(_bondId);        
        uint256 __bondId = uint(keccak256(abi.encodePacked(_tmpBond.startTime, _bondId)));
        bytes memory hash = abi.encodePacked(bytes32(__bondId));
        uint256 pIndex = toUint8(hash,0)/16; // 16 palettes
        
        /* this is broken into functions to avoid stack too deep errors */
        // im so sorry
        string memory paletteSection = generatePaletteSection(__bondId, pIndex);
        string memory quote = generateQuote();
        string memory status = generateStatus(uint256(_tmpBond.status));
        string memory claimedBRoot = generateclaimedBRoot(_tmpBond.claimedBRoot);
        string memory ID = generateID(_bondId);
        return string(
            abi.encodePacked(
                '<svg class="svgBody" width="270" height="210" viewBox="0 0 270 210" xmlns="http://www.w3.org/2000/svg">',
                paletteSection,
                '<text x="175" y="80" class="small">BEAN SPROUT</text><text x="15" y="100" class="medium">STATUS:</text>',
                ID,
                '<rect x="15" y="105" width="120" height="20" style="fill:white;opacity:0.5"/></text>',
                status,
                '</text><text x="110" y="145" class="small" opacity="0.75">', toString(_tmpBond.amount),
                '</text><text x="15" y="160" class="small">BROOT GAINED:</text><text x="15" y="145" class="small">BONDED ROOTS:</text>',
                claimedBRoot,
                quote
            )
        );
    }
    
    function generateStatus(uint256 status) internal pure returns (string memory) {
       return string(abi.encodePacked('<text x="15" y="120" class="medium">',status, '</text>'));
    }

    function generateID(uint256 bondID) internal pure returns (string memory) {
       return string(abi.encodePacked(
        '<text x="15" y="80" class="medium">ID> ', 
        toString(bondID),
        '</text>'
        ));
    }

    function generateclaimedBRoot(uint256 claimedBRoot) internal pure returns (string memory) {
       return string(abi.encodePacked('<text x="110" y="160" class="small" opacity="0.75">', toString(claimedBRoot), '</text>'));
    }
    
    function requireCallerIsChickenBondsManager() internal view {
        require(msg.sender == address(chickenBondManager), "BondNFT: Caller must be ChickenBondManager");
    }

    function generatePaletteSection(uint256 _tokenIdhash, uint256 pIndex) internal view returns (string memory) {
        return string(abi.encodePacked(
                // Border + sections
                '<rect width="270" height="210" rx="10" style="fill:',palette[pIndex][0],'" />',
                '<rect y="150" width="270" height="60" rx="10" style="fill:',palette[pIndex][3],'" />',
                '<rect y="60" width="270" height="75" style="fill:',palette[pIndex][1],'"/>',
                '<rect y="130" width="270" height="40" style="fill:',palette[pIndex][2],'" />',
                // text
                '<text x="15" y="30" class="medium">COOP BOND:</text>',
                '<text x="17" y="45" class="small" opacity="0.5">',substring(toString(_tokenIdhash),0,24),'</text>',
                //root logo :)
                '<svg viewBox="-1600 215 2000 900">',
                '<path d="M34.9755 2.30389L129.327 57.5039L224.063 2.30389L255.097 20.736L129.327 93.0239L4.32568 20.736L34.9755 2.30389Z" fill="#40845F"/>',
                '<path d="M129.327 93.0237V239.52L160.938 221.28V110.304L255.097 57.5997V20.7357L129.327 93.0237Z" fill="#00F97C"/>',
                '<path d="M129.327 93.0237V239.52L97.7149 221.28V110.304L3.55615 57.5997V20.7357L129.327 93.0237Z" fill="#05301C"/></svg>'
            )
        );
    }

    function generateQuote() internal pure returns (string memory) {
        return string(abi.encodePacked(
                '</text><text x="15" y="180" class="tiny">A national debt, if it is not excessive,</text>',
                '<text x="15" y="190" class="tiny">will be to us a national blessing.</text>',
                '<text x="15" y="200" class="tiny">- Alexander Hamilton, Letter to Robert Morris, April 30, 1781</text>',
                '<style>.svgBody {font-family: "Courier New" } .tiny {font-size:6px; } .small {font-size: 12px;}.medium {font-size: 18px;}</style>',
                '</svg>'
            )
        );
    }
    // GENERIC helpers

    // helper function for generation
    // from: https://github.com/GNSPS/solidity-bytes-utils/blob/master/contracts/BytesLib.sol 
    function toUint8(bytes memory _bytes, uint256 _start) internal pure returns (uint8) {
        require(_start + 1 >= _start, "toUint8_overflow");
        require(_bytes.length >= _start + 1 , "toUint8_outOfBounds");
        uint8 tempUint;

        assembly {
            tempUint := mload(add(add(_bytes, 0x1), _start))
        }
        return tempUint;
    }
    // from: https://raw.githubusercontent.com/OpenZeppelin/openzeppelin-contracts/master/contracts/utils/Strings.sol
    /**
     * @dev Converts a `uint256` to its ASCII `string` decimal representation.
     */
    function toString(uint256 value) internal pure returns (string memory) {
        // Inspired by OraclizeAPI's implementation - MIT licence
        // https://github.com/oraclize/ethereum-api/blob/b42146b063c7d6ee1358846c198246239e9360e8/oraclizeAPI_0.4.25.sol

        if (value == 0) {
            return "0";
        }
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
    // from: https://ethereum.stackexchange.com/questions/31457/substring-in-solidity/31470
    function substring(string memory str, uint startIndex, uint endIndex) internal pure returns (string memory) {
        bytes memory strBytes = bytes(str);
        bytes memory result = new bytes(endIndex-startIndex);
        for(uint i = startIndex; i < endIndex; i++) {
            result[i-startIndex] = strBytes[i];
        }
        return string(result);
    }
}
