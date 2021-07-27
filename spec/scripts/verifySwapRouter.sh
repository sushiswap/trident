certoraRun spec/harness/SwapRouterHarness.sol spec/harness/SimpleBentoBox.sol spec/harness/DummyERC20A.sol spec/harness/DummyERC20B.sol spec/harness/DummyWeth.sol  spec/harness/SymbolicPool.sol \
	--verify SwapRouterHarness:spec/SwapRouter.spec \
	--optimistic_loop --loop_iter 2 \
	--link SwapRouterHarness:bento=SimpleBentoBox SymbolicPool:bento=SimpleBentoBox \
	--packages @openzeppelin=$PWD/node_modules/@openzeppelin \
	--solc_map SwapRouterHarness=solc8.2,DummyERC20A=solc8.2,SimpleBentoBox=solc6.12,SymbolicPool=solc8.2,DummyERC20B=solc8.2,DummyWeth=solc8.2 \
	--settings -ignoreViewFunctions,-postProcessCounterExamples=true \
	--cache Trident \
	--rule $1 \
	--staging  jtoman/fix-trident --msg "Swap Router : $1 with 8.2 jhon "
	#--packages @openzeppelin=/Users/vasu/Documents/Certora/trident/node_modules/@openzeppelin \
	