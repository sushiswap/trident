# virtualize functions for BentoBoxV1
perl -0777 -i -pe 's/public payable \{/public virtual payable \{/g' contracts/flat/BentoBoxV1Flat.sol
perl -0777 -i -pe 's/external payable returns/external virtual payable returns/g' contracts/flat/BentoBoxV1Flat.sol
perl -0777 -i -pe 's/external view returns \(uint256 /external virtual view returns \(uint256 /g' contracts/flat/BentoBoxV1Flat.sol
perl -0777 -i -pe 's/uint256\[\] calldata amounts,\s+bytes calldata data\s+\) public/uint256\[\] calldata amounts,bytes calldata data\) public virtual/g' contracts/flat/BentoBoxV1Flat.sol
perl -0777 -i -pe 's/external payable returns \(bool /external virtual payable returns \(bool /g' contracts/flat/BentoBoxV1Flat.sol
perl -0777 -i -pe 's/public payable returns \(address /public virtual payable returns \(address /g' contracts/flat/BentoBoxV1Flat.sol
perl -0777 -i -pe 's/        external\n        payable/        external\n        virtual\n        payable/g' contracts/flat/BentoBoxV1Flat.sol # for batch

# virtualize functions for SwapRouter
perl -0777 -i -pe 's/external payable returns/external virtual payable returns/g' contracts/SwapRouter.sol
perl -0777 -i -pe 's/external payable /public virtual payable /g' contracts/SwapRouter.sol
perl -0777 -i -pe 's/        external\n        payable/        public\n        virtual\n        payable/g' contracts/SwapRouter.sol # for ExactSingleInput and others ...

# remove hardhat console
perl -0777 -i -pe 's/import \"hardhat/\/\/ import \"hardhat/g' contracts/SwapRouter.sol
perl -0777 -i -pe 's/import \"hardhat/\/\/ import \"hardhat/g' contracts/pool/HybridPool.sol
perl -0777 -i -pe 's/import \"hardhat/\/\/ import \"hardhat/g' contracts/pool/ConstantProductPool.sol

# add import for Simplifications and Simplifications object in ConstantProductPool
perl -0777 -i -pe 's/import \"..\/deployer\/MasterDeployer.sol\";/import \"..\/deployer\/MasterDeployer.sol\";\nimport \"..\/..\/spec\/harness\/Simplifications.sol\";/g' contracts/pool/ConstantProductPool.sol
perl -0777 -i -pe 's/address internal immutable barFeeTo;/address internal immutable barFeeTo;\n    Simplifications public simplified;/g' contracts/pool/ConstantProductPool.sol

# simplifying sqrt MirinMath.sqrt\(balance0 \* balance1\); in ConstantProductPool
perl -0777 -i -pe 's/MirinMath.sqrt\(/simplified.sqrt\(/g' contracts/pool/ConstantProductPool.sol

# _balance: internal -> public
perl -0777 -i -pe 's/_balance\(\) internal view/_balance\(\) public view/g' contracts/pool/ConstantProductPool.sol

# reserve: internal -> public
perl -0777 -i -pe 's/uint128 internal reserve0;/uint128 public reserve0;/g' contracts/pool/ConstantProductPool.sol
perl -0777 -i -pe 's/uint128 internal reserve1;/uint128 public reserve1;/g' contracts/pool/ConstantProductPool.sol