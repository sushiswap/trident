certoraRun contracts/pool/ConstantProductPool.sol \
	--verify ConstantProductPool:spec/sanity.spec \
	--optimistic_loop --loop_iter 2 \
	--packages @openzeppelin=/Users/nate/Documents/Projects/Sushi/trident/node_modules/@openzeppelin
	--staging --msg "Constant Product Pool"