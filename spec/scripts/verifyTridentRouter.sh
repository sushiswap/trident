certoraRun spec/harness/TridentRouterHarness.sol spec/harness/SimpleBentoBox.sol spec/harness/DummyERC20A.sol spec/harness/DummyERC20B.sol spec/harness/DummyWeth.sol  spec/harness/SymbolicPool.sol \
	--verify TridentRouterHarness:spec/TridentRouter.spec \
	--optimistic_loop --loop_iter 1 \
	--link TridentRouterHarness:bento=SimpleBentoBox SymbolicPool:bento=SimpleBentoBox \
	--packages @openzeppelin=$PWD/node_modules/@openzeppelin \
	--solc_map TridentRouterHarness=solc8.2,DummyERC20A=solc8.2,SimpleBentoBox=solc6.12,SymbolicPool=solc8.2,DummyERC20B=solc8.2,DummyWeth=solc8.2 \
	--settings -ignoreViewFunctions,-postProcessCounterExamples=true,-solvers=z3,-t=120 \
	--cache Trident --short_output \
	--staging  --msg "Trident Router: WETH"