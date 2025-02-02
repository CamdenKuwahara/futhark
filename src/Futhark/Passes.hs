{-# LANGUAGE FlexibleContexts #-}

-- | Optimisation pipelines.
module Futhark.Passes
  ( standardPipeline,
    sequentialPipeline,
    kernelsPipeline,
    sequentialCpuPipeline,
    gpuPipeline,
    mcPipeline,
    multicorePipeline,
  )
where

import Control.Category ((>>>))
import Futhark.IR.GPU (GPU)
import Futhark.IR.GPUMem (GPUMem)
import Futhark.IR.MC (MC)
import Futhark.IR.MCMem (MCMem)
import Futhark.IR.SOACS (SOACS, usesAD)
import Futhark.IR.Seq (Seq)
import Futhark.IR.SeqMem (SeqMem)
import Futhark.Optimise.CSE
import Futhark.Optimise.DoubleBuffer
import Futhark.Optimise.EntryPointMem
import Futhark.Optimise.Fusion
import Futhark.Optimise.GenRedOpt
import Futhark.Optimise.HistAccs
import Futhark.Optimise.InPlaceLowering
import Futhark.Optimise.InliningDeadFun
import qualified Futhark.Optimise.MemoryBlockMerging as MemoryBlockMerging
import Futhark.Optimise.MergeGPUBodies
import Futhark.Optimise.ReduceDeviceSyncs
import Futhark.Optimise.Sink
import Futhark.Optimise.TileLoops
import Futhark.Optimise.Unstream
import Futhark.Pass.AD
import Futhark.Pass.ExpandAllocations
import qualified Futhark.Pass.ExplicitAllocations.GPU as GPU
import qualified Futhark.Pass.ExplicitAllocations.MC as MC
import qualified Futhark.Pass.ExplicitAllocations.Seq as Seq
import Futhark.Pass.ExtractKernels
import Futhark.Pass.ExtractMulticore
import Futhark.Pass.FirstOrderTransform
import Futhark.Pass.KernelBabysitting
import Futhark.Pass.Simplify
import Futhark.Pipeline

-- | A pipeline used by all current compilers.  Performs inlining,
-- fusion, and various forms of cleanup.  This pipeline will be
-- followed by another one that deals with parallelism and memory.
standardPipeline :: Pipeline SOACS SOACS
standardPipeline =
  passes
    [ simplifySOACS,
      inlineConservatively,
      simplifySOACS,
      inlineAggressively,
      simplifySOACS,
      performCSE True,
      simplifySOACS,
      fuseSOACs,
      performCSE True,
      simplifySOACS,
      removeDeadFunctions
    ]
    >>> condPipeline usesAD adPipeline

-- | This is the pipeline that applies the AD transformation and
-- subsequent interesting optimisations.
adPipeline :: Pipeline SOACS SOACS
adPipeline =
  passes
    [ applyAD,
      simplifySOACS,
      performCSE True,
      fuseSOACs,
      performCSE True,
      simplifySOACS
    ]

-- | The pipeline used by the CUDA and OpenCL backends, but before
-- adding memory information.  Includes 'standardPipeline'.
kernelsPipeline :: Pipeline SOACS GPU
kernelsPipeline =
  standardPipeline
    >>> onePass extractKernels
    >>> passes
      [ simplifyGPU,
        optimiseGenRed,
        simplifyGPU,
        tileLoops,
        simplifyGPU,
        histAccsGPU,
        babysitKernels,
        simplifyGPU,
        unstreamGPU,
        performCSE True,
        simplifyGPU,
        sinkGPU, -- Sink reads before migrating them.
        reduceDeviceSyncs,
        simplifyGPU, -- Simplify and hoist storages.
        performCSE True, -- Eliminate duplicate storages.
        mergeGPUBodies,
        simplifyGPU, -- Cleanup merged GPUBody kernels.
        sinkGPU, -- Sink reads within GPUBody kernels.
        inPlaceLoweringGPU
      ]

-- | The pipeline used by the sequential backends.  Turns all
-- parallelism into sequential loops.  Includes 'standardPipeline'.
sequentialPipeline :: Pipeline SOACS Seq
sequentialPipeline =
  standardPipeline
    >>> onePass firstOrderTransform
    >>> passes
      [ simplifySeq,
        inPlaceLoweringSeq
      ]

-- | Run 'sequentialPipeline', then add memory information (and
-- optimise it slightly).
sequentialCpuPipeline :: Pipeline SOACS SeqMem
sequentialCpuPipeline =
  sequentialPipeline
    >>> onePass Seq.explicitAllocations
    >>> passes
      [ performCSE False,
        simplifySeqMem,
        entryPointMemSeq,
        simplifySeqMem
      ]

-- | Run 'kernelsPipeline', then add memory information (and optimise
-- it a lot).
gpuPipeline :: Pipeline SOACS GPUMem
gpuPipeline =
  kernelsPipeline
    >>> onePass GPU.explicitAllocations
    >>> passes
      [ simplifyGPUMem,
        performCSE False,
        simplifyGPUMem,
        entryPointMemGPU,
        doubleBufferGPU,
        simplifyGPUMem,
        MemoryBlockMerging.optimise,
        simplifyGPUMem,
        expandAllocations,
        simplifyGPUMem
      ]

-- | Run 'standardPipeline' and then convert to multicore
-- representation (and do a bunch of optimisation).
mcPipeline :: Pipeline SOACS MC
mcPipeline =
  standardPipeline
    >>> onePass extractMulticore
    >>> passes
      [ simplifyMC,
        unstreamMC,
        performCSE True,
        simplifyMC,
        sinkMC,
        inPlaceLoweringMC
      ]

-- | Run 'mcPipeline' and then add memory information.
multicorePipeline :: Pipeline SOACS MCMem
multicorePipeline =
  mcPipeline
    >>> onePass MC.explicitAllocations
    >>> passes
      [ simplifyMCMem,
        performCSE False,
        simplifyMCMem,
        entryPointMemMC,
        doubleBufferMC,
        simplifyMCMem
      ]
