certoraRun spec/harness/SwapRouterHarness.sol spec/harness/SimpleBentoBox.sol spec/harness/DummyERC20A.sol  spec/harness/SymbolicPool.sol \
	--verify SwapRouterHarness:spec/SwapRouter.spec \
	--optimistic_loop --loop_iter 2 \
	--link SwapRouterHarness:bento=SimpleBentoBox SymbolicPool:bento=SimpleBentoBox \
	--packages @openzeppelin=$PWD/node_modules/@openzeppelin \
	--solc_map SwapRouterHarness=solc8.4,DummyERC20A=solc8.4,SimpleBentoBox=solc6.12,SymbolicPool=solc8.4 \
	--settings -ignoreViewFunctions,-postProcessCounterExamples=true \
	--cache Trident \
	--staging --msg "Swap Router : $1 - $2"
	#--packages @openzeppelin=/Users/vasu/Documents/Certora/trident/node_modules/@openzeppelin \
	