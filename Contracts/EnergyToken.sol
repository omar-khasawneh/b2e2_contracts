pragma solidity ^0.5.0;

import "./IdentityContractFactory.sol";
import "./IdentityContract.sol";
import "./ClaimCommons.sol";
import "./erc-1155/contracts/ERC1155.sol";

contract EnergyToken is ERC1155, ClaimCommons {
    using SafeMath for uint256;
    using Address for address;
    
    enum TokenKind {AbsoluteForward, GenerationBasedForward, ConsumptionBasedForward, Certificate}
    
    struct EnergyDocumentation {
        uint256 value;
        string signature;
        bool corrected;
        bool generated;
    }
    
    IdentityContractFactory identityContractFactory; // TODO: Set value.
    IdentityContract marketAuthority; // TODO: Set value.
    mapping(address => bool) meteringAuthorityExistenceLookup;
    mapping(address => mapping(uint64 => EnergyDocumentation)) energyDocumentations; // TODO: powerConsumption or energyConsumption? Document talks about energy and uses units of energy but uses the word "power".

    function mint(uint256 _id, address[] memory _to, uint256[] memory _quantities) onlyCreators public returns(uint256 __id) {
        for(uint32 i=0; i < _to.length; i++) {
            require(identityContractFactory.isValidPlant(_to[i]));
            balances[_id][_to[i]]   = _quantities[i].add(balances[_id][_to[i]]);
        }
        
        __id = _id;
    }
    
    modifier onlyCreators {
        // TODO: Implement
        _;
    }
    
    modifier onlyMeteringAuthorities {
        require(isSecondLevelAuthority(msg.sender, ClaimType.IsMeteringAuthority));
        _;
    }
    
    function isSecondLevelAuthority(address payable _secondLevelAuthority, ClaimType _authorityClaimKind) internal view returns(bool) {
        // Make sure the given claim actually is about _secondLevelAuthority being a second level authority.
        require(_authorityClaimKind == ClaimType.IsBalanceAuthority || _authorityClaimKind == ClaimType.IsMeteringAuthority || _authorityClaimKind == ClaimType.IsPhysicalAssetAuthority);
        
        uint256 topic = claimType2Topic(_authorityClaimKind);
        bytes32[] memory claimIds = IdentityContract(_secondLevelAuthority).getClaimIdsByType(topic);
        
        for(uint64 i = 0; i < claimIds.length; i++) {
            (uint256 cTopic, uint256 cScheme, address cIssuer, bytes memory cSignature, bytes memory cData, string memory cUri) = IdentityContract(_secondLevelAuthority).getClaim(claimIds[i]);
            
            if(cTopic != topic)
                continue;
                
            if(cIssuer != address(identityContractFactory))
                continue;
            
            bool correct = marketAuthority.verifySignature(cTopic, cScheme, cIssuer, cSignature, cData);
            if(correct)
                return true;
        }
        
        return false;
    }
    
    function isGenerationPlant(address payable _generationPlant) internal view returns(bool) {
        uint256 topic = claimType2Topic(ClaimType.ExistenceClaim);
        bytes32[] memory claimIds = IdentityContract(_generationPlant).getClaimIdsByType(topic);
        
        for(uint64 i = 0; i < claimIds.length; i++) {
            (uint256 cTopic, uint256 cScheme, address cIssuer, bytes memory cSignature, bytes memory cData, string memory cUri) = IdentityContract(_generationPlant).getClaim(claimIds[i]);
            
            if(cTopic != topic)
                continue;
                
            address physicalAssetAuthority = cIssuer;
            bool correctAccordingToPhysicalAssetAuthority = IdentityContract(address(uint160(physicalAssetAuthority))).verifySignature(cTopic, cScheme, cIssuer, cSignature, cData);
            
            if(correctAccordingToPhysicalAssetAuthority && isSecondLevelAuthority(address(uint160(physicalAssetAuthority)), ClaimType.IsPhysicalAssetAuthority)) {
                return true;
            }
        }
        
        return false;
    }
    
    modifier onlyGenerationPlants {
        require(isGenerationPlant(msg.sender));
        _;
    }
    
    function createForwards(uint64 _balancePeriod, address _distributor) public onlyGenerationPlants returns(uint256 __id) {
        // Todo: Wie funktioniert "Der Distributor Contract bestimmt die Gattung der Forwards Art."?
        __id = getTokenId(TokenKind.GenerationBasedForward, _balancePeriod, _distributor);
        balances[__id][_distributor] = 100E18;
    }
    
    function createCertificates(address _generationPlant, uint64 _balancePeriod) public onlyMeteringAuthorities returns(uint256 __id) {
        __id = getTokenId(TokenKind.Certificate, _balancePeriod, _generationPlant);
        // Nothing to do. All balances of this token remain zero.
    }

    function addMeasuredEnergyConsumption(address _plant, uint256 _value, uint64 _balancePeriod, string memory _signature, bool _corrected) onlyMeteringAuthorities public returns (bool __success) {
        // Don't allow a corrected value to be overwritten with a non-corrected value.
        if(!energyDocumentations[_plant][_balancePeriod].corrected || _corrected) {
            return false;
        }
        
        EnergyDocumentation memory energyDocumentation = EnergyDocumentation(_value, _signature, _corrected, false);
        energyDocumentations[_plant][_balancePeriod] = energyDocumentation;
        
        return true;
    }
    
    function addMeasuredEnergyGeneration(address _plant, uint256 _value, uint64 _balancePeriod, string memory _signature, bool _corrected) onlyMeteringAuthorities public returns (bool __success) {
        // Don't allow a corrected value to be overwritten with a non-corrected value.
        if(!energyDocumentations[_plant][_balancePeriod].corrected || _corrected) {
            return false;
        }
        
        EnergyDocumentation memory energyDocumentation = EnergyDocumentation(_value, _signature, _corrected, true);
        energyDocumentations[_plant][_balancePeriod] = energyDocumentation;
        
        return true;
    }
    
    /**
     * tokenId: zeros (24 bit) || tokenKind number (8 bit) || balancePeriod (64 bit) || address of IdentityContract (160 bit)
     */
    function getTokenId(TokenKind _tokenKind, uint64 _balancePeriod, address _identityContractAddress) public pure returns (uint256 __tokenId) {
        __tokenId = 0;
        
        __tokenId += tokenKind2Number(_tokenKind);
        __tokenId = __tokenId << 64;
        __tokenId += _balancePeriod;
        __tokenId = __tokenId << 160;
        __tokenId += uint256(_identityContractAddress);
    }
    
    /**
     * | Bit (rtl) | Meaning                                         |
     * |-----------+-------------------------------------------------|
     * |         0 | Genus (Generation-based 0; Consumption-based 1) |
     * |         1 | Genus (Absolute 0; Relative 1)                  |
     * |         2 | Family (Forwards 0; Certificates 1)             |
     * |         3 |                                                 |
     * |         4 |                                                 |
     * |         5 |                                                 |
     * |         6 |                                                 |
     * |         7 |                                                 |
     * 
     * Bits are zero unless specified otherwise.
     */
    function tokenKind2Number(TokenKind _tokenKind) public pure returns (uint8) {
        if(_tokenKind == TokenKind.AbsoluteForward) {
            return 0;
        }
        if(_tokenKind == TokenKind.GenerationBasedForward) {
            return 2;
        }
        if(_tokenKind == TokenKind.AbsoluteForward) {
            return 3;
        }
        if(_tokenKind == TokenKind.AbsoluteForward) {
            return 4;
        }
        
        // Invalid TokenKind.
        require(false);
    }
}
