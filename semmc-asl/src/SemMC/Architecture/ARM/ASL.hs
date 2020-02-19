{-# LANGUAGE GADTs #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE UndecidableInstances #-}
{-# LANGUAGE ConstraintKinds #-}

-- | Converting the output of the asl translator into semmc formulas

module SemMC.Architecture.ARM.ASL
  ( encodingToFormula
  , symFnsToLibrary
  ) where

import           Data.Kind
import qualified Data.Text as T
import qualified Data.Set as Set
import qualified Data.Map as Map
import           Control.Applicative ( Const(..) )
import           Control.Monad.Identity
import           Control.Monad ( liftM, forM )
import           Data.Proxy

import qualified Data.Parameterized.Context as Ctx
import qualified Data.Type.List as TL
import qualified Data.Parameterized.TyMap as TM
import           Data.Parameterized.SymbolRepr ( Symbol )
import qualified Data.Parameterized.SymbolRepr as SR
import           Data.Parameterized.Classes
import           Data.Parameterized.List as SL
import qualified Data.Parameterized.TraversableFC as FC
import qualified Data.Parameterized.Map as MapF
import           Data.Parameterized.Some
import           Data.Parameterized.Pair
import           Data.Parameterized.HasRepr

import qualified SemMC.BoundVar as BV
import qualified SemMC.Architecture as A
import qualified SemMC.Architecture.Location as L
import qualified SemMC.Formula.Formula as SF

import qualified Dismantle.ARM.T32 as T32
import qualified Dismantle.ARM.A32 as A32
import qualified Dismantle.ARM.ASL as ASL

import           SemMC.Architecture.AArch32 ( AArch32 )
import qualified SemMC.Architecture.AArch32 as ARM
import qualified SemMC.Architecture.ARM.Location as ARM
import           SemMC.Architecture.ARM.Combined ( ARMOperandRepr )
import qualified SemMC.Architecture.ARM.Combined as ARM

import qualified Language.ASL.Globals as ASL

import qualified What4.Interface as WI
import qualified What4.Expr.Builder as WB
import           What4.Utils.Util ( SomeSome(..) )

data OperandTypeWrapper (arch :: Type) :: TL.TyFun Symbol WI.BaseType -> Type
type instance TL.Apply (OperandTypeWrapper arch) s = A.OperandType arch s
type OperandTypes arch sh = TL.Map (OperandTypeWrapper arch) sh
type OperandTypesCtx arch sh = TL.ToContext (TL.Map (OperandTypeWrapper arch) sh)

data GlobalsTypeWrapper :: TL.TyFun Symbol WI.BaseType -> Type
type instance TL.Apply GlobalsTypeWrapper s = ASL.GlobalsType s


_testGlobalSyms :: Ctx.Assignment f (TM.MapContext GlobalsTypeWrapper ASL.GlobalSymsCtx) :~: Ctx.Assignment f ASL.GlobalsCtx
_testGlobalSyms = Refl


shapeOfOperands :: SL.List ARMOperandRepr sh -> SL.List WI.BaseTypeRepr (OperandTypes AArch32 sh)
shapeOfOperands SL.Nil = SL.Nil
shapeOfOperands (a SL.:< oprepr) = ARM.shapeReprType a SL.:< shapeOfOperands oprepr


mkOperandVars :: forall sym sh
               . WI.IsSymExprBuilder sym
              => sym
              -> ARM.ARMOpcode ARM.ARMOperand sh
              -> IO (SL.List (BV.BoundVar sym AArch32) sh)
mkOperandVars sym op = do
  FC.traverseFC mkBV (typeRepr op)
  where
    mkBV :: ARMOperandRepr s -> IO (BV.BoundVar sym AArch32 s)
    mkBV opRep = do
      let ty = ARM.shapeReprType opRep
      BV.BoundVar <$> WI.freshBoundVar sym (WI.safeSymbol $ A.operandTypeReprSymbol (Proxy @AArch32) opRep) ty

type FnArgSig sh = WI.BaseStructType (OperandTypesCtx AArch32 sh Ctx.::> WI.BaseStructType ASL.GlobalsCtx)

testOpcodeSig :: forall sym args ret sh
               . WI.IsSymExprBuilder sym
              => sym
              -> ARM.ARMOpcode ARM.ARMOperand sh
              -> WI.SymFn sym args ret
              -> Maybe ((WI.BaseTypeRepr (WI.BaseStructType args), WI.BaseTypeRepr ret) :~: (WI.BaseTypeRepr (FnArgSig sh), (WI.BaseTypeRepr (WI.BaseStructType ASL.GlobalsCtx))))
testOpcodeSig _ op symfn = do
  Refl <- testEquality (operandsToAsn (typeRepr op) Ctx.:> WI.BaseStructRepr ASL.trackedGlobalBaseReprs) (WI.fnArgTypes symfn)
  Refl <- testEquality (WI.BaseStructRepr ASL.trackedGlobalBaseReprs) (WI.fnReturnType symfn)
  return $ Refl

data GlobalBoundVar sym s =
  GlobalBoundVar { unGBoundVar :: WI.BoundVar sym (ASL.GlobalsType s) }


operandsToAsn :: SL.List ARMOperandRepr sh -> Ctx.Assignment WI.BaseTypeRepr (OperandTypesCtx AArch32 sh)
operandsToAsn repr = TL.toAssignment (shapeOfOperands repr)

bvsToAsn :: SL.List (BV.BoundVar sym AArch32) sh
         -> Ctx.Assignment (WI.BoundVar sym) (OperandTypesCtx AArch32 sh)
bvsToAsn bvs = TL.toAssignment $ TM.applyMapList (Proxy @(OperandTypeWrapper AArch32)) BV.unBoundVar bvs

unGBoundVarAsn :: WI.IsSymExprBuilder sym
               => sym
               -> Ctx.Assignment (GlobalBoundVar sym) ASL.GlobalSymsCtx
               -> Ctx.Assignment (WI.BoundVar sym) ASL.GlobalsCtx
unGBoundVarAsn sym gbvs = TM.applyMapContext (Proxy @GlobalsTypeWrapper) unGBoundVar gbvs


mkGlobalVars :: forall sym
              . WI.IsSymExprBuilder sym
             => sym -> IO (Ctx.Assignment (GlobalBoundVar sym) ASL.GlobalSymsCtx)
mkGlobalVars sym = FC.traverseFC mkBV ASL.allGlobalRefs
  where
    mkBV :: ASL.GlobalRef s -> IO (GlobalBoundVar sym s)
    mkBV gr =
      GlobalBoundVar <$> WI.freshBoundVar sym (WI.safeSymbol $ T.unpack $ SR.symbolRepr $ ASL.globalRefSymbol gr) (ASL.globalRefRepr gr)


getLiteralVarMap :: Ctx.Assignment (GlobalBoundVar sym) ASL.GlobalSymsCtx
                 -> MapF.MapF (L.Location AArch32) (WI.BoundVar sym)
getLiteralVarMap bvs = MapF.fromList $ FC.toListFC (\(Const c) -> c) $
  Ctx.zipWith (\(GlobalBoundVar bv) gr -> Const (Pair (ARM.Location gr) bv)) bvs ASL.allGlobalRefs

getGlobalStruct :: WI.IsSymExprBuilder sym
                => sym
                -> Ctx.Assignment (GlobalBoundVar sym) ASL.GlobalSymsCtx
                -> IO (WI.SymExpr sym (WI.BaseStructType ASL.GlobalsCtx))
getGlobalStruct sym gbvs = do
  let bvs = unGBoundVarAsn sym gbvs
  WI.mkStruct sym (FC.fmapFC (WI.varExpr sym) bvs)


mkOpParams :: SL.List ARMOperandRepr sh -> Set.Set (Some (SF.Parameter AArch32 sh))
mkOpParams bvs =
  Set.fromList $ FC.toListFC (\(Const c) -> c) $
    SL.imap (\idx v -> Const (Some (SF.OperandParameter @AArch32 (ARM.shapeReprType v) idx))) bvs


class WI.IsSymExprBuilder sym => SymFnsHaveBVs sym where
  fnBoundVars :: sym -> WI.SymFn sym args ret -> Maybe (Ctx.Assignment (WI.BoundVar sym) args)
  showSymFn :: sym -> WI.SymFn sym args ret -> String

instance SymFnsHaveBVs (WB.ExprBuilder t st fs) where
  fnBoundVars _sym symFn = case WB.symFnInfo symFn of
      WB.DefinedFnInfo vars _ _ -> Just vars
      _ -> Nothing
  showSymFn _sym symFn = show symFn


encodingToFormula :: forall sym sh
                   . SymFnsHaveBVs sym
                  => sym
                  -> Map.Map T.Text (SomeSome (WI.SymFn sym))
                  -> ARM.ARMOpcode ARM.ARMOperand sh
                  -> ASL.Encoding
                  -> IO (SF.ParameterizedFormula sym AArch32 sh)
encodingToFormula sym symFnEnv opcode enc = case Map.lookup (T.pack $ (ASL.encName enc)) symFnEnv of
  Just (SomeSome symFn) -> do
    case testOpcodeSig sym opcode symFn of
      Just Refl -> do
        opvars <- mkOperandVars sym opcode
        gbvars <- mkGlobalVars sym
        gbstruct <- getGlobalStruct sym gbvars
        argbvs <- return $ FC.fmapFC (WI.varExpr sym) $ bvsToAsn opvars

        expr <- WI.applySymFn sym symFn (argbvs Ctx.:> gbstruct)
        defs <- (MapF.fromList . FC.toListFC (\(Const c) -> c)) <$> FC.traverseFC (mkPair expr) ASL.allGlobalRefs
        let litVarMap = getLiteralVarMap gbvars
        let params = mkOpParams (typeRepr opcode) `Set.union` (Set.fromList $ MapF.keys defs)
        return $
          SF.ParameterizedFormula
            { SF.pfUses = params
            , SF.pfOperandVars = opvars
            , SF.pfLiteralVars = litVarMap
            , SF.pfDefs = defs
            }
  where
    mkPair :: forall s. WI.SymExpr sym (WI.BaseStructType ASL.GlobalsCtx)
           -> ASL.GlobalRef s
           -> IO (Const (Pair (SF.Parameter AArch32 sh) (WI.SymExpr sym)) s)
    mkPair struct gr = do
      expr <- WI.structField sym struct (ASL.globalRefIndex gr)
      return $ Const $ Pair (SF.LiteralParameter (ARM.Location gr)) expr


symFnsToLibrary :: forall sym
                 . SymFnsHaveBVs sym
                => sym
                -> [(T.Text, SomeSome (WI.SymFn sym))]
                -> SF.Library sym
symFnsToLibrary sym funs = runIdentity $ do
  liftM MapF.fromList $ forM funs $ \(nm, SomeSome symFn) -> do
    (argtps, argvars) <- return $ mkArgLists symFn
    Refl <- return $ TL.toFromCtxFwd (WI.fnArgTypes symFn)
    let rettp = WI.fnReturnType symFn

    let ref = SF.FunctionRef
                { SF.frName = T.unpack nm
                , SF.frArgTypes = argtps
                , SF.frRetType = rettp
                }

    return $ Pair ref $ SF.FunctionFormula
      { SF.ffName = T.unpack nm
      , SF.ffArgTypes = argtps
      , SF.ffArgVars = argvars
      , SF.ffRetType = rettp
      , SF.ffDef = symFn
      }
  where
    mkArgLists :: WI.SymFn sym args ret
               -> ( SL.List WI.BaseTypeRepr (TL.FromContextFwd args)
                  , SL.List (WI.BoundVar sym) (TL.FromContextFwd args)
                  )
    mkArgLists symFn = case fnBoundVars sym symFn of
      Just vars -> (TL.fromAssignmentFwd (WI.fnArgTypes symFn), TL.fromAssignmentFwd vars)
      _ -> error $ "Unexpected uninterpreted function: " ++ showSymFn sym symFn