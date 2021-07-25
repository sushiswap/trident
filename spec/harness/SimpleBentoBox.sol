pragma solidity 0.6.12;
pragma experimental ABIEncoderV2;

import "contracts/flat/BentoBoxV1Flat.sol";

// Note: Rebasing tokens ARE NOT supported and WILL cause loss of funds
contract SimpleBentoBox is BentoBoxV1 {
	using BoringMath for uint256;

	uint256 private constant RATIO = 2;

	function toShare(IERC20 token, uint256 amount, bool roundUp)
			public override view returns (uint256 share) {
		// if (RATIO == 1)
		//	return amount;

        if (roundUp)
		 	return (amount.add(1)) / RATIO;
		else 
		 	return amount / RATIO; 
    }

    function toAmount(IERC20 token, uint256 share, bool roundUp)
			public override view returns (uint256 amount) {
		// if (RATIO == 1)
		// 	return share; 
		
        return share.mul(RATIO);
    }

	function assumeRatio(IERC20 token_, uint ratio) external view {
		require(totals[IERC20(token_)].elastic == ratio.mul(totals[IERC20(token_)].base));
	}
	
	function deposit(IERC20 token_, address from, address to, uint256 amount, uint256 share)
			public payable allowed(from) override returns (uint256 amountOut, uint256 shareOut) {
		IERC20 token = token_ == USE_ETHEREUM ? wethToken : token_;

		// we trust here 
		if (share == 0) {
			shareOut = toShare(token, amount, false);
			amountOut = amount;
		} else {
			shareOut = share;
			amountOut = toAmount(token, share, false);
		}

		balanceOf[token][from] = balanceOf[token][from].add(shareOut);

		
	}

	function withdraw(IERC20 token_, address from, address to,
					  uint256 amount, uint256 share) 
			public allowed(from) override returns (uint256 amountOut, uint256 shareOut) {
		IERC20 token = token_ == USE_ETHEREUM ? wethToken : token_;

		if (share == 0) {
			shareOut = toShare(token, amount, true);
			amountOut = amount;
		} else {
			shareOut = share;
			amountOut = toAmount(token, share, true);
		}

		balanceOf[token][from] = balanceOf[token][from].sub(shareOut);

		token.transfer(to, amountOut);
	}
	
	constructor(IERC20 wethToken_) BentoBoxV1(wethToken_) public { }

	function batch(bytes[] calldata calls, bool revertOnFail) 
		external override payable returns(bool[] memory successes, bytes[] memory results) { }
	
	function deploy(address masterContract, bytes calldata data, bool useCreate2)
		public override payable returns(address cloneAddress){ }
	
	// does nothing
	function permitToken(IERC20 token, address from, uint256 amount, 
						 uint256 deadline, uint8 v, bytes32 r, bytes32 s) external { }

	function batchFlashLoan(IBatchFlashBorrower borrower, address[] calldata receivers,
        					IERC20[] calldata tokens, uint256[] calldata amounts,
							bytes calldata data) public virtual override { }
}