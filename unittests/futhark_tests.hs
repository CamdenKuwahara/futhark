module Main (main) where

import qualified Futhark.AD.DerivativesTests
import qualified Futhark.BenchTests
import qualified Futhark.IR.Mem.IxFunTests
import qualified Futhark.IR.PropTests
import qualified Futhark.IR.Syntax.CoreTests
import qualified Futhark.Optimise.MemoryBlockMerging.GreedyColoringTests
import qualified Futhark.Pkg.SolveTests
import qualified Language.Futhark.PrimitiveTests
import qualified Language.Futhark.SyntaxTests
import qualified Language.Futhark.TypeCheckerTests
import Test.Tasty

allTests :: TestTree
allTests =
  testGroup
    ""
    [ Language.Futhark.SyntaxTests.tests,
      Futhark.AD.DerivativesTests.tests,
      Futhark.BenchTests.tests,
      Futhark.IR.PropTests.tests,
      Futhark.IR.Syntax.CoreTests.tests,
      Futhark.Pkg.SolveTests.tests,
      Futhark.IR.Mem.IxFunTests.tests,
      Language.Futhark.PrimitiveTests.tests,
      Futhark.Optimise.MemoryBlockMerging.GreedyColoringTests.tests,
      Language.Futhark.TypeCheckerTests.tests
    ]

main :: IO ()
main = defaultMain allTests
