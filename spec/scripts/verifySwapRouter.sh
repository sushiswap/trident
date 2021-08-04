certoraRun spec/harness/SwapRouterHarness.sol spec/harness/SimpleBentoBox.sol spec/harness/DummyERC20A.sol spec/harness/DummyERC20B.sol spec/harness/DummyWeth.sol  spec/harness/SymbolicPool.sol \
	--verify SwapRouterHarness:spec/SwapRouter.spec \
	--optimistic_loop --loop_iter 1 \
	--link SwapRouterHarness:bento=SimpleBentoBox SymbolicPool:bento=SimpleBentoBox \
	--packages @openzeppelin=$PWD/node_modules/@openzeppelin \
	--solc_map SwapRouterHarness=solc8.2,DummyERC20A=solc8.2,SimpleBentoBox=solc6.12,SymbolicPool=solc8.2,DummyERC20B=solc8.2,DummyWeth=solc8.2 \
	--settings -ignoreViewFunctions,-postProcessCounterExamples=true,-solvers=z3,-t=120 \
	--cache Trident --short_output \
	--staging  --msg "Swap Router :WETH " 
	#--packages @openzeppelin=/Users/vasu/Documents/Certora/trident/node_modules/@openzeppelin \
	