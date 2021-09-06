##################################################
#                   BentoBoxV1                   #
##################################################
# virtualize functions for BentoBoxV1
perl -0777 -i -pe 's/public payable \{/public virtual payable \{/g' contracts/flat/BentoBoxV1Flat.sol
perl -0777 -i -pe 's/external payable returns/external virtual payable returns/g' contracts/flat/BentoBoxV1Flat.sol
perl -0777 -i -pe 's/external view returns \(uint256 /external virtual view returns \(uint256 /g' contracts/flat/BentoBoxV1Flat.sol
perl -0777 -i -pe 's/uint256\[\] calldata amounts,\s+bytes calldata data\s+\) public/uint256\[\] calldata amounts,bytes calldata data\) public virtual/g' contracts/flat/BentoBoxV1Flat.sol
perl -0777 -i -pe 's/external payable returns \(bool /external virtual payable returns \(bool /g' contracts/flat/BentoBoxV1Flat.sol
perl -0777 -i -pe 's/public payable returns \(address /public virtual payable returns \(address /g' contracts/flat/BentoBoxV1Flat.sol
perl -0777 -i -pe 's/        external\n        payable/        external\n        virtual\n        payable/g' contracts/flat/BentoBoxV1Flat.sol # for batch

# adding transfer functions to the IERC20 interface in the BentoBoxV1
perl -0777 -i -pe 's/function decimals\(\) external view returns \(uint256\);/function decimals\(\) external view returns \(uint256\);\n    function transfer\(address to, uint256 amount\) external;\n    function transferFrom\(address from, address to, uint256 amount\) external;/g' contracts/flat/BentoBoxV1Flat.sol

# bytes4 private -> bytes4 internal for BentoBoxV1
perl -0777 -i -pe 's/private/internal/g' contracts/flat/BentoBoxV1Flat.sol

# virtualizing deposit and withdraw
perl -0777 -i -pe 's/\) public payable allowed\(from\)/\) public virtual payable allowed\(from\)/g' contracts/flat/BentoBoxV1Flat.sol
perl -0777 -i -pe 's/\) public allowed\(from\) returns/\) public virtual allowed\(from\) returns/g' contracts/flat/BentoBoxV1Flat.sol

##################################################
#                  TridentHelper                 #
##################################################
# virtualizing batch function
perl -0777 -i -pe 's/function batch\(bytes\[\] calldata data\) external/function batch\(bytes\[\] calldata data\) external virtual/g' contracts/utils/TridentHelper.sol

##################################################
#                   TridentRouter                #
##################################################
# remove hardhat console
perl -0777 -i -pe 's/import \"hardhat/\/\/ import \"hardhat/g' contracts/TridentRouter.sol

# virtualizing receive
perl -0777 -i -pe 's/receive\(\) external payable \{/receive\(\) external virtual payable \{/g' contracts/TridentRouter.sol

# virtualize functions for TridentRouter
perl -0777 -i -pe 's/external payable /public virtual payable /g' contracts/TridentRouter.sol
perl -0777 -i -pe 's/        external\n        payable/        public\n        virtual\n        payable/g' contracts/TridentRouter.sol # for ExactSingleInput and others ...

# external checkDeadline -> public virtual checkDeadline
perl -0777 -i -pe 's/external checkDeadline/public virtual checkDeadline/g' contracts/TridentRouter.sol

# virtualize 
# ) external { -> ) public virtual {
perl -0777 -i -pe 's/\) external \{/\) public virtual \{/g' contracts/TridentRouter.sol
# ) public { -> ) public virtual {
perl -0777 -i -pe 's/\) public \{/\) public virtual \{/g' contracts/TridentRouter.sol
# ) internal { -> ) internal virtual {
perl -0777 -i -pe 's/\) internal \{/\) internal virtual \{/g' contracts/TridentRouter.sol

# calldata -> memory
perl -0777 -i -pe 's/calldata/memory/g' contracts/TridentRouter.sol

##################################################
#               ConstantProductPool              #
##################################################
# add import for Simplifications, IBentoBoxMinimal, and Simplifications object in ConstantProductPool
perl -0777 -i -pe 's/import \"..\/deployer\/MasterDeployer.sol\";/import \"..\/deployer\/MasterDeployer.sol\";\nimport \"..\/..\/spec\/harness\/Simplifications.sol\";\nimport \"..\/interfaces\/IBentoBoxMinimal.sol\";/g' contracts/pool/ConstantProductPool.sol
perl -0777 -i -pe 's/address public immutable barFeeTo;/address public immutable barFeeTo;\n    Simplifications public simplified;/g' contracts/pool/ConstantProductPool.sol

# BentoBox and MasterDeployer object
perl -0777 -i -pe 's/address public immutable bento;/IBentoBoxMinimal public immutable bento;/g' contracts/pool/ConstantProductPool.sol
perl -0777 -i -pe 's/address public immutable masterDeployer;/MasterDeployer public immutable masterDeployer;/g' contracts/pool/ConstantProductPool.sol

perl -0777 -i -pe 's/\(, bytes memory _bento\)/\/\/ \(, bytes memory _bento\)/g' contracts/pool/ConstantProductPool.sol
perl -0777 -i -pe 's/\(, bytes memory _barFeeTo\)/\/\/ \(, bytes memory _barFeeTo\)/g' contracts/pool/ConstantProductPool.sol

perl -0777 -i -pe 's/bento = abi.decode\(_bento, \(address\)\);/bento = IBentoBoxMinimal\(MasterDeployer\(_masterDeployer\).bento\(\)\);/g' contracts/pool/ConstantProductPool.sol
perl -0777 -i -pe 's/barFeeTo = abi.decode\(_barFeeTo, \(address\)\);/barFeeTo = MasterDeployer\(_masterDeployer\).barFeeTo\(\);/g' contracts/pool/ConstantProductPool.sol
perl -0777 -i -pe 's/masterDeployer = _masterDeployer;/masterDeployer = MasterDeployer\(_masterDeployer\);/g' contracts/pool/ConstantProductPool.sol

perl -0777 -i -pe 's/address migrator = MasterDeployer\masterDeployer\).migrator\(\);/address migrator = masterDeployer.migrator\(\);/g' contracts/pool/ConstantProductPool.sol

perl -0777 -i -pe 's/\(, bytes memory _balance0\)/\/\/ \(, bytes memory _balance0\)/g' contracts/pool/ConstantProductPool.sol
perl -0777 -i -pe 's/\(, bytes memory _balance1\)/\/\/ \(, bytes memory _balance1\)/g' contracts/pool/ConstantProductPool.sol

perl -0777 -i -pe 's/balance0 = abi.decode\(_balance0, \(uint256\)\);/balance0 = bento.balanceOf\(token0, address\(this\)\);/g' contracts/pool/ConstantProductPool.sol
perl -0777 -i -pe 's/balance1 = abi.decode\(_balance1, \(uint256\)\);/balance1 = bento.balanceOf\(token1, address\(this\)\);/g' contracts/pool/ConstantProductPool.sol

perl -0777 -i -pe 's/\(, bytes memory _barFee\)/\/\/ \(, bytes memory _barFee\)/g' contracts/pool/ConstantProductPool.sol
perl -0777 -i -pe 's/uint256 barFee = abi.decode\(_barFee, \(uint256\)\);/uint256 barFee = MasterDeployer\(masterDeployer\).barFee\(\);/g' contracts/pool/ConstantProductPool.sol

perl -0777 -i -pe 's/require\(success, \"WITHDRAW_FAILED\"\);/\/\/ require\(success, \"WITHDRAW_FAILED\"\);/g' contracts/pool/ConstantProductPool.sol
perl -0777 -i -pe 's/require\(success, \"TRANSFER_FAILED\"\);/\/\/ require\(success, \"TRANSFER_FAILED\"\);/g' contracts/pool/ConstantProductPool.sol
perl -0777 -i -pe 's/\(bool success, \) = bento.call\(abi.encodeWithSelector\(0x97da6d30, token, address\(this\), to, 0, shares\)\);/bento.withdraw\(token, address\(this\), to, 0, shares\);/g' contracts/pool/ConstantProductPool.sol
perl -0777 -i -pe 's/\(bool success, \) = bento.call\(abi.encodeWithSelector\(0xf18d03cc, token, address\(this\), to, shares\)\);/bento.transfer\(token, address\(this\), to, shares\);/g' contracts/pool/ConstantProductPool.sol

# simplifying sqrt TridentMath.sqrt(balance0 * balance1) in ConstantProductPool
perl -0777 -i -pe 's/contract ConstantProductPool is IPool, TridentERC20/contract ConstantProductPool is IPool, TridentERC20, Simplifications/g' contracts/pool/ConstantProductPool.sol
perl -0777 -i -pe 's/TridentMath.sqrt\(/simplified.sqrt\(/g' contracts/pool/ConstantProductPool.sol

# _balance: internal -> public
perl -0777 -i -pe 's/_balance\(\) internal view/_balance\(\) public view/g' contracts/pool/ConstantProductPool.sol

# reserve: internal -> public
perl -0777 -i -pe 's/uint112 internal reserve0;/uint112 public reserve0;/g' contracts/pool/ConstantProductPool.sol
perl -0777 -i -pe 's/uint112 internal reserve1;/uint112 public reserve1;/g' contracts/pool/ConstantProductPool.sol

# virtualizing mint, burn, burnSingle, swap, flashSwap, _getAmountOut, getAmountOut
perl -0777 -i -pe 's/function mint\(bytes calldata data\) public/function mint\(bytes memory data\) public virtual/g' contracts/pool/ConstantProductPool.sol
perl -0777 -i -pe 's/function burn\(bytes calldata data\) public/function burn\(bytes memory data\) public virtual/g' contracts/pool/ConstantProductPool.sol
perl -0777 -i -pe 's/function burnSingle\(bytes calldata data\) public/function burnSingle\(bytes memory data\) public virtual/g' contracts/pool/ConstantProductPool.sol
perl -0777 -i -pe 's/function swap\(bytes calldata data\) public/function swap\(bytes memory data\) public virtual/g' contracts/pool/ConstantProductPool.sol
perl -0777 -i -pe 's/function flashSwap\(bytes calldata data\) public/function flashSwap\(bytes memory data\) public virtual/g' contracts/pool/ConstantProductPool.sol
perl -0777 -i -pe 's/internal view returns \(uint256 amountOut\)/public virtual view returns \(uint256 amountOut\)/g' contracts/pool/ConstantProductPool.sol
perl -0777 -i -pe 's/function getAmountOut\(bytes calldata data\) public/function getAmountOut\(bytes memory data\) public virtual/g' contracts/pool/ConstantProductPool.sol

# internal -> public fee constants
perl -0777 -i -pe 's/uint256 internal constant MAX_FEE = 10000;/uint256 public constant MAX_FEE = 10000;/g' contracts/pool/ConstantProductPool.sol
perl -0777 -i -pe 's/uint256 internal immutable MAX_FEE_MINUS_SWAP_FEE/uint256 public immutable MAX_FEE_MINUS_SWAP_FEE/g' contracts/pool/ConstantProductPool.sol

##################################################
#                    HybridPool                  #
##################################################
# _balance: internal -> public
perl -0777 -i -pe 's/_balance\(\) internal view/_balance\(\) public view/g' contracts/pool/HybridPool.sol

# reserve: internal -> public
perl -0777 -i -pe 's/uint128 internal reserve0;/uint128 public reserve0;/g' contracts/pool/HybridPool.sol
perl -0777 -i -pe 's/uint128 internal reserve1;/uint128 public reserve1;/g' contracts/pool/HybridPool.sol

# virtualizing mint, burn, burnSingle, swap, flashSwap, _getAmountOut, getAmountOut
perl -0777 -i -pe 's/function mint\(bytes calldata data\) public/function mint\(bytes memory data\) public virtual/g' contracts/pool/HybridPool.sol
perl -0777 -i -pe 's/function burn\(bytes calldata data\) public/function burn\(bytes memory data\) public virtual/g' contracts/pool/HybridPool.sol
perl -0777 -i -pe 's/function burnSingle\(bytes calldata data\) public/function burnSingle\(bytes memory data\) public virtual/g' contracts/pool/HybridPool.sol
perl -0777 -i -pe 's/function swap\(bytes calldata data\) public/function swap\(bytes memory data\) public virtual/g' contracts/pool/HybridPool.sol
perl -0777 -i -pe 's/function flashSwap\(bytes calldata data\) public/function flashSwap\(bytes memory data\) public virtual/g' contracts/pool/HybridPool.sol
perl -0777 -i -pe 's/public view returns \(uint256\)/public virtual view returns \(uint256\)/g' contracts/pool/HybridPool.sol
perl -0777 -i -pe 's/function getAmountOut\(bytes calldata data\) public/function getAmountOut\(bytes memory data\) public virtual/g' contracts/pool/HybridPool.sol

# internal -> public fee constants
perl -0777 -i -pe 's/uint256 internal constant MAX_FEE = 10000;/uint256 public constant MAX_FEE = 10000;/g' contracts/pool/HybridPool.sol