// SPDX-License-Identifier: MIT OR Apache-2.0
pragma solidity >=0.8.0;

import {ISlasher} from "../interfaces/avs/vendored/ISlasher.sol";

/**
 * @notice This contract simulate the whole EL protocol for testing and demonstrating purpose
 * We assume the function freezeOperator has security mechanism to prevent anyone to slash an operator
 */
contract Slasher is ISlasher {
    address public insuranceFundETH;

    function setInsuranceFundETH(address _insuranceFundETH) external {
        insuranceFundETH = _insuranceFundETH;
    }

    mapping(address => bool) public isELOperator;
    mapping(address => uint256) public operatorStake;

    function registerOperator(address operator, uint32 stake) external {
        isELOperator[operator] = true;
        operatorStake[operator] = stake;
    }

    /// @notice We assume the function freezeOperator has security mechanism to prevent anyone to slash an operator
    function freezeOperator(address operator) external {
        require(insuranceFundETH != address(0), "Insurance fund not set");
        require(isELOperator[operator], "Operator not registered");
        require(operatorStake[operator] > 0, "Operator do not have staked");

        (bool success, ) = payable(insuranceFundETH).call{
            value: operatorStake[operator]
        }("");
        require(success, "Transfer to insurance fund failed");
    }
}
