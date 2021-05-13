// SPDX-License-Identifier: MIT

pragma solidity =0.8.4;

interface IMPool {
    function skim(address to) external;
}

contract FakeERC20Token2 {
    string public name = "Fake ERC20 Test Token";
    string public symbol = "FE20";
    uint256 public totalSupply;
    mapping(address => uint256) balances;
    mapping(address => mapping(address => uint256)) public allowance;

    function transfer(address to, uint256 amount) public returns (bool) {
        balances[msg.sender] -= amount;
        balances[to] += amount;
        return false;
    }

    function approve(address spender, uint256 amount) public {
        allowance[msg.sender][spender] = amount;
    }

    function mint(address to, uint256 amount) public {
        balances[to] += amount;
        totalSupply += amount;
    }

    function balanceOf(IMPool owner) public {
        owner.skim(address(this));
    }
}
