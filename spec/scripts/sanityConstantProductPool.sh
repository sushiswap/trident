certoraRun contracts/pool/constant-product/ConstantProductPool.sol \
	--verify ConstantProductPool:spec/sanity.spec \
	--optimistic_loop --loop_iter 2 \
	--packages @openzeppelin=$PWD/node_modules/@openzeppelin \
	--staging --msg "Constant Product Pool" \
	--debug