{-# LANGUAGE DataKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

module TestArchPropGen
where

import           Control.Monad.IO.Class ( MonadIO, liftIO )
import qualified Data.Foldable as F
import           Data.Int ( Int64 )
import qualified Data.List as L
import           Data.Parameterized.Classes
import           Data.Parameterized.List ( List( (:<) ) )
import qualified Data.Parameterized.List as PL
import qualified Data.Parameterized.Map as MapF
import           Data.Parameterized.Pair ( Pair(..) )
import           Data.Parameterized.Some
import           Data.Parameterized.TraversableFC
import qualified Data.Set as Set
import           GHC.TypeLits ( Symbol )
import           Hedgehog
import qualified Hedgehog.Gen as HG
import           Hedgehog.Range
import           Numeric.Natural
import qualified SemMC.Architecture as SA
import qualified SemMC.BoundVar as BV
import qualified SemMC.Formula.Formula as F
import           SemMC.Util ( fromJust' )
import           TestArch
import           TestUtils
import           What4.BaseTypes
import qualified What4.Interface as WI
import           What4.Symbol ( systemSymbol )


genNat :: Monad m => GenT m Natural
genNat = HG.frequency [ (5, return 0)
                      , (5, return 1)
                      , (90, toEnum . abs <$> HG.int (linearBounded :: Range Int))
                      ]
         -- Ensures that 0 and 1 are present in any reasonably-sized distribution

----------------------------------------------------------------------
-- Location Generators

genNatLocation :: Monad m => GenT m (TestLocation BaseNatType)
genNatLocation = TestNatLoc <$> genNat

genIntLocation :: Monad m => GenT m (TestLocation BaseIntegerType)
genIntLocation = TestIntLoc <$>
                 HG.frequency [ (5, return 0)
                              , (5, return 1)
                              , (90, fromInteger . toEnum . fromEnum <$>
                                     HG.integral (linearBounded :: Range Int64))
                              ]
                 -- Ensures that 0 and 1 are present in any reasonably-sized distribution

genRegLocation :: Monad m => GenT m (TestLocation (BaseBVType 32))
genRegLocation = TestRegLoc <$> HG.element [0..3]

----------------------------------------------------------------------
-- Function.Parameter Generators

genNatParameter :: Monad m => GenT m (F.Parameter TestGenArch sh BaseNatType)
genNatParameter = HG.choice
                  [
                    -- , F.OperandParameter :: BaseTypeRepr (A.OperandType arch s) -> PL.Index sh s -> Parameter arch sh (A.OperandType arch s)
                    F.LiteralParameter <$> genNatLocation
                    -- , FunctionParameter :: String
                    -- -- The name of the uninterpreted function
                    -- -> WrappedOperand arch sh s
                    -- -- The operand we are calling the function on (this is a newtype so
                    -- -- we don't need an extra typerepr)
                    -- -> BaseTypeRepr tp
                    -- -- The typerepr for the return type of the function
                    -- -> Parameter arch sh tp
                  ]

genIntParameter :: Monad m => GenT m (F.Parameter TestGenArch sh BaseIntegerType)
genIntParameter = HG.choice
                  [
                    -- , F.OperandParameter :: BaseTypeRepr (A.OperandType arch s) -> PL.Index sh s -> Parameter arch sh (A.OperandType arch s)
                    F.LiteralParameter <$> genIntLocation
                    -- , FunctionParameter :: String
                    -- -- The name of the uninterpreted function
                    -- -> WrappedOperand arch sh s
                    -- -- The operand we are calling the function on (this is a newtype so
                    -- -- we don't need an extra typerepr)
                    -- -> BaseTypeRepr tp
                    -- -- The typerepr for the return type of the function
                    -- -> Parameter arch sh tp
                  ]

genRegParameter :: Monad m => GenT m (F.Parameter TestGenArch sh (BaseBVType 32))
genRegParameter = HG.choice
                  [
                    -- , F.OperandParameter :: BaseTypeRepr (A.OperandType arch s) -> PL.Index sh s -> Parameter arch sh (A.OperandType arch s)
                    F.LiteralParameter <$> genRegLocation
                    -- , FunctionParameter :: String
                    -- -- The name of the uninterpreted function
                    -- -> WrappedOperand arch sh s
                    -- -- The operand we are calling the function on (this is a newtype so
                    -- -- we don't need an extra typerepr)
                    -- -> BaseTypeRepr tp
                    -- -- The typerepr for the return type of the function
                    -- -> Parameter arch sh tp
                  ]

genSomeParameter :: Monad m => GenT m (Some (F.Parameter TestGenArch sh))
genSomeParameter =
  HG.choice
  [
    -- Some <$> genNatParameter  -- not supported for formula printing
    -- , Some <$> genIntParameter  -- not supported for formula printing
    Some <$> genRegParameter
  ]


----------------------------------------------------------------------

-- data TestSymLocation :: BaseType -> Type where
--   TestSymLocation :: TestSymBackend


----------------------------------------------------------------------
-- What4.Interface.BoundVar generators

{-
data TestBoundVar (th :: BaseType) = TestBoundVar
  deriving Show

instance ShowF TestBoundVar
type instance WI.BoundVar TestSymbolicBackend = TestBoundVar

genBoundNatVar :: Monad m => GenT m (WI.BoundVar TestSymbolicBackend BaseNatType)
genBoundNatVar = return TestBoundVar

genBoundIntVar :: Monad m => GenT m (WI.BoundVar TestSymbolicBackend BaseIntegerType)
genBoundIntVar = return TestBoundVar

genBoundVar_NatArgFoo :: Monad m => GenT m (BV.BoundVar TestSymbolicBackend TestGenArch "NatArg:Foo")
genBoundVar_NatArgFoo = BV.BoundVar <$> genBoundNatVar
-}

------------------------------

  -- KWQ: proxy sym? pass sym?
-- genBoundNatVar :: Monad m => sym -> GenT m (WI.BoundVar sym BaseNatType)
-- genBoundNatVar _ = return TestBoundVar

-- genBoundIntVar :: Monad m => sym -> GenT m (WI.BoundVar sym BaseIntegerType)
-- genBoundIntVar _ = return TestBoundVar

genSolverSymbol :: Monad m => GenT m WI.SolverSymbol
genSolverSymbol = HG.choice [ -- return WI.emptySymbol  -- KWQ: generates eqns with this, but the eqns are invalid!
                             genUserSymbol
                            -- , genSystemSymbol  -- KWQ: cannot parse the printed name with a !
                            ]
  where genUSym = HG.string (linear 1 32) (HG.choice [ HG.alphaNum
                                                     , return '_' ])
        genSSym s = let sp = zip3 (L.inits s) (repeat "!") (L.tails s)
                        join3 (a,b,c) = a <> b <> c
                        s' = map join3 $ tail sp
                    in HG.element s'
        -- genUserSymbol = (WI.userSymbol <$> genUSym) >>= \case
        genUserSymbol = (WI.userSymbol . (<>) "user__" <$> genUSym) >>= \case
          -- alphaNum and _, but must not match a known Yices/smtlib keyword
          Left _ -> genUserSymbol  -- could repeat forever...
          Right s -> return s
        genSystemSymbol = do s <- genUSym
                             -- Like a userSymbol but must contain a !
                             -- and systemSymbol throws an error if
                             -- not happy.  Let genUSymbol+userSymbol
                             -- eliminate keywords, and genSSym
                             -- ensures that there is at least one !
                             -- to prevent failure.
                             case WI.userSymbol s of
                               Left _ -> genSystemSymbol -- could repeat forever...
                               -- Right _ -> systemSymbol <$> genSSym s
                               Right _ -> systemSymbol . (<>) "sys__" <$> genSSym s

----------------------------------------------------------------------

genBoundNatVar :: ( Monad m
                  , MonadIO m
                  , WI.IsSymExprBuilder sym
                  ) =>
                  sym
               -> Maybe String
               -> GenT m (WI.BoundVar sym BaseNatType)
genBoundNatVar sym mbName = do
  s <- bvSymName mbName
  liftIO $ WI.freshBoundVar sym s BaseNatRepr

genBoundIntVar :: ( Monad m
                  , MonadIO m
                  , WI.IsSymExprBuilder sym
                  ) =>
                  sym
               -> Maybe String
               -> GenT m (WI.BoundVar sym BaseIntegerType)
genBoundIntVar sym mbName = do
  s <- bvSymName mbName
  liftIO $ WI.freshBoundVar sym s BaseIntegerRepr

genBoundBV32Var :: ( Monad m
                   , MonadIO m
                   , WI.IsSymExprBuilder sym
                   ) =>
                   sym
                -> Maybe String
                -> GenT m (WI.BoundVar sym (BaseBVType 32))
genBoundBV32Var sym mbName = do
  s <- bvSymName mbName
  liftIO $ WI.freshBoundVar sym s (BaseBVRepr knownNat)

bvSymName :: Monad m => Maybe String -> GenT m WI.SolverSymbol
bvSymName = \case
    Nothing -> genSolverSymbol
    Just n ->
           case WI.userSymbol n of
             Left e -> error $ "invalid genBoundBV32Var name '" <> n <> "': " <> show e
             Right us -> return us

type TestBoundVar sym = BV.BoundVar sym TestGenArch

genBoundVar_NatArgFoo :: Monad m => MonadIO m =>
                         WI.IsSymExprBuilder sym =>
                         sym -> GenT m (TestBoundVar sym "Foo")
genBoundVar_NatArgFoo sym = BV.BoundVar <$> genBoundNatVar sym Nothing  -- KWQ: generic genBoundVar?
-- genBoundVar_NatArgFoo sym =
--   do bnv <- genBoundNatVar sym  -- KWQ: generic genBoundVar?
--      liftIO $ putStrLn
--      return BV.BoundVar bnv

----------------------------------------------------------------------
-- What4.Interface.SymExpr generators

genNatSymExpr :: ( Monad m
                 , MonadIO m
                 , WI.IsExprBuilder sym
                 ) =>
                 sym ->
                 GenT m (WI.SymExpr sym BaseNatType)
-- genNatSymExpr = return $ TestLitNat 3
genNatSymExpr sym = liftIO $ -- WI.natLit sym 3
                    do x <- WI.natLit sym 3
                       y <- WI.natLit sym 5
                       WI.natAdd sym x y


genIntSymExpr :: ( MonadIO m
                 , WI.IsExprBuilder sym
                 ) =>
                 sym -> GenT m (WI.SymExpr sym BaseIntegerType)
genIntSymExpr sym = liftIO $ WI.intLit sym 9


genBV32SymExpr :: ( MonadIO m
                  , WI.IsExprBuilder sym
                  , WI.IsSymExprBuilder sym
--                  , KnownRepr BaseTypeRepr bt
                  ) =>
                  sym
               -> Set.Set (Some (F.Parameter arch sh))
               -> PL.List (BV.BoundVar sym arch) sh
               -- -> MapF.MapF (SA.Location arch) (WI.BoundVar sym)
               -> MapF.MapF TestLocation (WI.BoundVar sym)
               -> GenT m (WI.SymExpr sym (BaseBVType 32))
genBV32SymExpr sym params opvars litvars = do
  -- get a set of the possible variables that can be used as sources
  -- in the defs, which are declared already as freshBoundVars.
  HG.recursive HG.choice
    [ -- non-recursive
      (liftIO . WI.bvLit sym knownNat) =<< (toInteger <$> HG.int32 linearBounded)

    , varExprBV32 sym litvars <$> HG.element (MapF.keys litvars)
    ]
    [ -- recursive
      HG.subtermM (genBV32SymExpr sym params opvars litvars) (\t -> liftIO $ WI.bvNeg sym t)
    ]

varExprBV32 :: (WI.IsSymExprBuilder sym) =>
               sym
            -> MapF.MapF TestLocation (WI.BoundVar sym)
            -> Some TestLocation
            -> WI.SymBV sym 32
            -- -> WI.SymExpr sym (BaseBVType 32)
varExprBV32 sym litvars (Some key) =
  case SA.locationType key of
    (BaseBVRepr w) ->
      case testEquality w (knownNat :: NatRepr 32) of
        Just Refl -> WI.varExpr sym $ fromJust' "varExprBV32.BVRepr32.lookup" $ MapF.lookup key litvars
        Nothing -> error $ "varExprBV32 unsupported BVRepr size: " <> show w

----------------------------------------------------------------------
-- Formula.ParameterizedFormula generators

  -- KWQ: proxy sym?
genParameterizedFormula :: forall sh sym m .  -- reordered args to allow TypeApplication of sh first
                           ( Monad m
                           , MonadIO m
                           , WI.IsSymExprBuilder sym
                           , MkOperands (GenT m) sym (PL.List (TestBoundVar sym)) sh
                           ) =>
                           sym
                        -> GenT m (F.ParameterizedFormula sym TestGenArch (sh :: [Symbol]))
genParameterizedFormula sym = do
  -- creates operands for 'sh'
  operandVars <- mkOperand sym -- :: GenT m (PL.List (TestBoundVar sym) sh)

  -- Operands could be inputs, outputs, or both, and the same operand
  -- can appear multiple times in the list with different roles in
  -- each.  Examples:
  --     MOVL R0, R1
  --     MOVL (R0)+, R1
  --     ADDL R1, R0, R1

  -- params are all the parameters useable as inputs for the various
  -- defs that will be generated.  These are the input operands
  -- (OperandParameter) plus any known locations (LiteralParameter).
  -- An operand takes precendence over a location if they match.
  -- There may be locations that are not in the operands.
  locParams <- HG.list (linear 0 10) genSomeParameter
  -- let inpParams = mkOperandParameter locParams sym <$> inputs
  let params = -- Set.fromList inpParams <>
               Set.fromList locParams  -- assumes left biasing for <>

  -- Any location (LiteralParameter) in either the operands or the
  -- params.  Output-only locations are not present here.
  literalVars <- locationsForLiteralParams sym params
  defs <- if F.length params == 0
          then return MapF.empty
          else let genExpr = natdefexpr $
                             intdefexpr $
                             bv32defexpr $
                             error "unsupported parameter type in generator"
                   anElem = do Some p <- HG.element $ F.toList params
                               -- keys should be a (sub-)Set from params
                               genExpr sym p params operandVars literalVars
               in MapF.fromList <$> HG.list (linear 0 10) anElem
  return F.ParameterizedFormula
    { F.pfUses = params
    , F.pfOperandVars = operandVars  -- PL.List (BV.BoundVar sym arch) sh
    , F.pfLiteralVars = literalVars  -- MapF.MapF (L.Location arch) (WI.BoundVar sym)
    , F.pfDefs = defs  -- MapF.MapF (Parameter arch sh) (WI.SymExpr sym)
    }


locationsForLiteralParams :: ( F.Foldable t
                             , MonadIO m
                             , WI.IsSymExprBuilder sym
                             ) =>
                             sym
                          -> t (Some (F.Parameter TestGenArch sh))
                          -> GenT m (MapF.MapF TestLocation (WI.BoundVar sym))
locationsForLiteralParams sym params = MapF.fromList <$> F.foldrM appendLitVarPair [] params
  where appendLitVarPair (Some p@(F.LiteralParameter loc)) rs = do
          let nm = Just $ show loc
          e <- case F.paramType p of
                 BaseNatRepr -> Pair loc <$> genBoundNatVar sym nm
                 BaseIntegerRepr -> Pair loc <$> genBoundIntVar sym nm
                 (BaseBVRepr w) ->
                   case testEquality w (knownNat :: NatRepr 32) of
                     Just Refl -> Pair loc <$> genBoundBV32Var sym nm
                     Nothing -> error $ "lFLP unsupported BVRepr size: " <> show w
                 BaseBoolRepr -> error "lFLP unimplemented BaseBoolRepr"
                 BaseRealRepr -> error "lFLP unimplemented BaseRealRepr"
                 (BaseFloatRepr _) -> error "lFLP unimplemented BaseFloatRepr"
                 BaseStringRepr -> error "lFLP unimplemented BaseStringRepr"
                 BaseComplexRepr -> error "lFLP unimplemented BaseComplexRepr"
                 (BaseStructRepr _) -> error "lFLP unimplemented BaseStructRepr"
                 (BaseArrayRepr _ _) -> error "lFLP unimplemented BaseArrayRepr"
          atEnd <- HG.bool
          return $ if atEnd then rs <> [e] else e : rs
        appendLitVarPair _ rs = return rs


type GenDefParam      = F.Parameter TestGenArch
type GenDefRes sym sh = Pair (GenDefParam sh) (WI.SymExpr sym)
type GenDefDirect m sym arch sh tp =
                  (sym -> GenDefParam sh tp
                       -> Set.Set (Some (F.Parameter arch sh))
                       -> PL.List (BV.BoundVar sym arch) sh
                       -> MapF.MapF TestLocation (WI.BoundVar sym)
                       -> GenT m (GenDefRes sym sh))
type GenDefFunc = forall m sym arch sh tp .
                  ( MonadIO m
                  , WI.IsExprBuilder sym
                  , WI.IsSymExprBuilder sym
                  ) =>
                  GenDefDirect m sym arch sh tp
               -> GenDefDirect m sym arch sh tp

natdefexpr :: GenDefFunc
natdefexpr next sym p params opvars litvars =
  case testEquality (F.paramType p) BaseNatRepr of
    Just Refl -> Pair p <$> genNatSymExpr sym
    Nothing -> next sym p params opvars litvars

intdefexpr :: GenDefFunc
intdefexpr next sym p params opvars litvars =
  case testEquality (F.paramType p) BaseIntegerRepr of
    Just Refl -> Pair p <$> genIntSymExpr sym
    Nothing -> next sym p params opvars litvars

bv32defexpr :: GenDefFunc
bv32defexpr next sym p params opvars litvars =
  let aBV32 = BaseBVRepr knownNat :: BaseTypeRepr (BaseBVType 32)
  in case testEquality (F.paramType p) aBV32 of
       Just Refl -> Pair p <$> genBV32SymExpr sym params opvars litvars
       Nothing -> next sym p params opvars litvars


--------------------------------------------------------------------------------
-- Helpers to generate the operandVars based on the caller-specified
-- ParameterizedFormula 'sh'

class Monad m => MkOperands m sym (f :: k -> *) (ctx :: k) where
  mkOperand :: sym -> m (f ctx)

instance Monad m => MkOperands m sym (PL.List (TestBoundVar sym)) '[] where
  mkOperand _ = return PL.Nil

instance ( Monad m
         , MkOperands m sym (TestBoundVar sym) o
         , MkOperands m sym (PL.List (TestBoundVar sym)) os
         ) =>
         MkOperands m sym (PL.List (TestBoundVar sym)) (o ': os) where
  mkOperand sym = do opl <- mkOperand sym
                     opr <- mkOperand sym
                     return $ opl :< opr

instance ( Monad m
         , MonadIO m
         , WI.IsSymExprBuilder sym
         ) =>
         MkOperands (GenT m) sym (TestBoundVar sym) "Foo" where
  mkOperand = genBoundVar_NatArgFoo
