//SPDX-License-Identifier: MIT

pragma solidity 0.8.20;

interface IFlashLoanReceiver {
    function execute() external payable;
}
