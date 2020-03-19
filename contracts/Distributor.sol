pragma solidity ^0.5.0;
import "./IdentityContract.sol";
import "./IdentityContractFactory.sol";
import "./EnergyToken.sol";

contract Distributor is IdentityContract {
    using SafeMath for uint256;
    
    IdentityContractFactory public identityContractFactory;
    EnergyToken public energyToken;

    constructor(IdentityContractFactory _identityContractFactory, IdentityContract _marketAuthority, EnergyToken _energyToken) IdentityContract(_marketAuthority) public {
        identityContractFactory = _identityContractFactory;
        energyToken = _energyToken;
    }
    
    function distribute(address payable _consumptionPlantAddress, uint256 _tokenId) public onlyOwner {
        (EnergyToken.TokenKind tokenKind, uint64 balancePeriod, address identityContractAddress) = energyToken.getTokenIdConstituents(_tokenId);
        
        // Time period check
        require(balancePeriod < Commons.getBalancePeriod());
        
        uint256 certificateTokenId = energyToken.getTokenId(EnergyToken.TokenKind.Certificate, balancePeriod, identityContractAddress);
        bytes memory additionalData;

        // Claim check
        require(ClaimVerifier.getClaimOfType(marketAuthority, _consumptionPlantAddress, ClaimCommons.ClaimType.BalanceClaim) != 0);
        require(ClaimVerifier.getClaimOfType(marketAuthority, _consumptionPlantAddress, ClaimCommons.ClaimType.ExistenceClaim) != 0);
        require(ClaimVerifier.getClaimOfType(marketAuthority, _consumptionPlantAddress, ClaimCommons.ClaimType.MeteringClaim) != 0);
        
        // Distribution
        if(tokenKind == EnergyToken.TokenKind.AbsoluteForward) {
            uint256 totalForwards = energyToken.totalSupply(_tokenId);
            uint256 absoluteForwardsOfConsumer = energyToken.balanceOf(_consumptionPlantAddress, _tokenId);
            uint256 generatedEnergy = energyToken.balanceOf(address(this), certificateTokenId);

            energyToken.safeTransferFrom(address(this), _consumptionPlantAddress, certificateTokenId, Commons.min(absoluteForwardsOfConsumer, (absoluteForwardsOfConsumer.div(totalForwards)).mul(generatedEnergy)), additionalData);
            return;
        }
        
        if(tokenKind == EnergyToken.TokenKind.GenerationBasedForward) {
            uint256 generationBasedForwardsOfConsumer = energyToken.balanceOf(_consumptionPlantAddress, _tokenId);
            uint256 generatedEnergy = energyToken.balanceOf(address(this), certificateTokenId);

            energyToken.safeTransferFrom(address(this), _consumptionPlantAddress, certificateTokenId, (generationBasedForwardsOfConsumer.mul(generatedEnergy)).div(100E18), additionalData);
            return;
        }
        
        if(tokenKind == EnergyToken.TokenKind.ConsumptionBasedForward) {
            uint256 consumptionBasedForwards = energyToken.balanceOf(_consumptionPlantAddress, _tokenId);
            uint256 generatedEnergy = energyToken.balanceOf(identityContractAddress, _tokenId);
            uint256 consumedEnergy = energyToken.balanceOf(_consumptionPlantAddress, _tokenId);
            uint256 totalConsumedEnergy = energyToken.energyConsumpedInBalancePeriod(balancePeriod);
            
            uint256 option1 = (consumptionBasedForwards.mul(consumedEnergy)).div(100E18);
            uint256 option2;
            if(totalConsumedEnergy > 0) {
                option2 = (((consumptionBasedForwards.mul(consumedEnergy)).div(100E18)).mul(generatedEnergy)).div(totalConsumedEnergy);
            } else {
                 option2 = option1;
            }
            
            energyToken.safeTransferFrom(address(this), _consumptionPlantAddress, certificateTokenId, Commons.min(option1, option2), additionalData);
            return;
        }
        
        require(false);
    }
}
