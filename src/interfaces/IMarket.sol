// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.30;

interface IMarket {
    function marketName() external view returns (string memory);
    function tokenAccepted() external view returns (address);
    function tvl() external view returns (uint256);
    function maxSupply() external view returns (uint256);
    function getPendingReward(uint index) external view returns (uint256);
    function userPositions(address user, uint256 index) external view returns (uint256 amount, uint256 lockPeriod, uint256 pendingReward, uint256 claimedReward, bool withdrawn, bool claimed);

    function deposit(address to, address tokenIn, uint256 amount, uint256 lockPeriod) external;
    function redeem(uint256 index) external;
    function depositAsOwner(uint256 amount) external;
    function redeemToOwner(uint256 amount) external;
    function rollover() external view;

    function balanceOf(address account) external view returns (uint256);
    function lockCount(address user) external view returns (uint256);
    function updateClaimedStatus(address user, uint256 positionIndex, uint256 claimedAmount) external;
}
