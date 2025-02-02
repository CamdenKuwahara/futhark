-- | A simple index operation representation.  Every operation corresponds to a
-- constructor.
module Futhark.IR.Mem.IxFun.Alg
  ( IxFun (..),
    iota,
    offsetIndex,
    permute,
    reshape,
    coerce,
    slice,
    flatSlice,
    rebase,
    shape,
    index,
  )
where

import Futhark.IR.Prop
import Futhark.IR.Syntax
  ( DimIndex (..),
    FlatDimIndex (..),
    FlatSlice (..),
    Slice (..),
    flatSliceDims,
    sliceDims,
    unitSlice,
  )
import Futhark.Util.IntegralExp
import Futhark.Util.Pretty
import Prelude hiding (mod)

type Shape num = [num]

type Indices num = [num]

type Permutation = [Int]

data IxFun num
  = Direct (Shape num)
  | Permute (IxFun num) Permutation
  | Index (IxFun num) (Slice num)
  | FlatIndex (IxFun num) (FlatSlice num)
  | Reshape (IxFun num) (Shape num)
  | Coerce (IxFun num) (Shape num)
  | OffsetIndex (IxFun num) num
  | Rebase (IxFun num) (IxFun num)
  deriving (Eq, Show)

instance Pretty num => Pretty (IxFun num) where
  ppr (Direct dims) =
    text "Direct" <> parens (commasep $ map ppr dims)
  ppr (Permute fun perm) = ppr fun <> ppr perm
  ppr (Index fun is) = ppr fun <> ppr is
  ppr (FlatIndex fun is) = ppr fun <> ppr is
  ppr (Reshape fun oldshape) =
    ppr fun
      <> text "->reshape"
      <> parens (ppr oldshape)
  ppr (Coerce fun oldshape) =
    ppr fun
      <> text "->coerce"
      <> parens (ppr oldshape)
  ppr (OffsetIndex fun i) =
    ppr fun <> text "->offset_index" <> parens (ppr i)
  ppr (Rebase new_base fun) =
    text "rebase(" <> ppr new_base <> text ", " <> ppr fun <> text ")"

iota :: Shape num -> IxFun num
iota = Direct

offsetIndex :: IxFun num -> num -> IxFun num
offsetIndex = OffsetIndex

permute :: IxFun num -> Permutation -> IxFun num
permute = Permute

slice :: IxFun num -> Slice num -> IxFun num
slice = Index

flatSlice :: IxFun num -> FlatSlice num -> IxFun num
flatSlice = FlatIndex

rebase :: IxFun num -> IxFun num -> IxFun num
rebase = Rebase

reshape :: IxFun num -> Shape num -> IxFun num
reshape = Reshape

coerce :: IxFun num -> Shape num -> IxFun num
coerce = Reshape

shape ::
  IntegralExp num =>
  IxFun num ->
  Shape num
shape (Direct dims) =
  dims
shape (Permute ixfun perm) =
  rearrangeShape perm $ shape ixfun
shape (Index _ how) =
  sliceDims how
shape (FlatIndex ixfun how) =
  flatSliceDims how <> tail (shape ixfun)
shape (Reshape _ dims) =
  dims
shape (Coerce _ dims) =
  dims
shape (OffsetIndex ixfun _) =
  shape ixfun
shape (Rebase _ ixfun) =
  shape ixfun

index ::
  (IntegralExp num, Eq num) =>
  IxFun num ->
  Indices num ->
  num
index (Direct dims) is =
  sum $ zipWith (*) is slicesizes
  where
    slicesizes = drop 1 $ sliceSizes dims
index (Permute fun perm) is_new =
  index fun is_old
  where
    is_old = rearrangeShape (rearrangeInverse perm) is_new
index (Index fun (Slice js)) is =
  index fun (adjust js is)
  where
    adjust (DimFix j : js') is' = j : adjust js' is'
    adjust (DimSlice j _ s : js') (i : is') = j + i * s : adjust js' is'
    adjust _ _ = []
index (FlatIndex fun (FlatSlice offset js)) is =
  index fun $ sum (offset : zipWith f is js) : drop (length js) is
  where
    f i (FlatDimIndex _ s) = i * s
index (Reshape fun newshape) is =
  let new_indices = reshapeIndex (shape fun) newshape is
   in index fun new_indices
index (Coerce fun _) is =
  index fun is
index (OffsetIndex fun i) is =
  case shape fun of
    d : ds ->
      index (Index fun (Slice (DimSlice i (d - i) 1 : map (unitSlice 0) ds))) is
    [] -> error "index: OffsetIndex: underlying index function has rank zero"
index (Rebase new_base fun) is =
  let fun' = case fun of
        Direct old_shape ->
          if old_shape == shape new_base
            then new_base
            else reshape new_base old_shape
        Permute ixfun perm ->
          permute (rebase new_base ixfun) perm
        Index ixfun iis ->
          slice (rebase new_base ixfun) iis
        FlatIndex ixfun iis ->
          flatSlice (rebase new_base ixfun) iis
        Reshape ixfun new_shape ->
          reshape (rebase new_base ixfun) new_shape
        Coerce ixfun new_shape ->
          coerce (rebase new_base ixfun) new_shape
        OffsetIndex ixfun s ->
          offsetIndex (rebase new_base ixfun) s
        r@Rebase {} ->
          r
   in index fun' is
