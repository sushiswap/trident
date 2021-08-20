pragma solidity >=0.8.0;

contract Receiver {

    fallback() external payable {}
    function sendTo() external payable returns (bool) { return true; }
    receive() external payable {}
}
