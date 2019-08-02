{-# LANGUAGE DataKinds #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE PolyKinds #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeOperators #-}

-- | Functions for converting between What4 and Crucible types.
module SemMC.ASL.Types
  ( ToBaseType
  , ToBaseTypes
  , ToBaseTypesList
  , ToCrucibleTypes
  , toBaseType
  , toBaseTypes
  , toCrucTypes
  , baseCrucProof
  ) where

import qualified Data.Parameterized.Context as Ctx

import qualified Lang.Crucible.Types as CT
import What4.BaseTypes as WT

type family ToBaseType (ctp :: CT.CrucibleType) :: WT.BaseType where
  ToBaseType (CT.BaseToType bt) = bt

type family ToBaseTypes (ctps :: CT.Ctx CT.CrucibleType) :: CT.Ctx WT.BaseType where
  ToBaseTypes CT.EmptyCtx = CT.EmptyCtx
  ToBaseTypes (tps CT.::> tp) = ToBaseTypes tps CT.::> ToBaseType tp

toBaseType :: CT.TypeRepr ctp -> WT.BaseTypeRepr (ToBaseType ctp)
toBaseType repr = case CT.asBaseType repr of
  CT.NotBaseType -> error "Illegal crucible type"
  CT.AsBaseType brepr -> brepr

toBaseTypes :: Ctx.Assignment CT.TypeRepr ctps -> Ctx.Assignment WT.BaseTypeRepr (ToBaseTypes ctps)
toBaseTypes Ctx.Empty = Ctx.Empty
toBaseTypes (reprs Ctx.:> repr) = toBaseTypes reprs Ctx.:> toBaseType repr

type family ToCrucibleTypes (wtps :: CT.Ctx WT.BaseType) :: CT.Ctx CT.CrucibleType where
  ToCrucibleTypes CT.EmptyCtx = CT.EmptyCtx
  ToCrucibleTypes (tps CT.::> tp) = ToCrucibleTypes tps CT.::> CT.BaseToType tp

type family ToBaseTypesList (ctps :: CT.Ctx CT.CrucibleType) :: [WT.BaseType] where
  ToBaseTypesList CT.EmptyCtx = '[]
  ToBaseTypesList (tps CT.::> tp) = ToBaseType tp ': ToBaseTypesList tps

type family ToCrucTypes (wtps :: CT.Ctx WT.BaseType) :: CT.Ctx CT.CrucibleType where
  ToCrucTypes CT.EmptyCtx = CT.EmptyCtx
  ToCrucTypes (wtps CT.::> wtp) = ToCrucTypes wtps CT.::> CT.BaseToType wtp

toCrucTypes :: Ctx.Assignment WT.BaseTypeRepr wtps -> Ctx.Assignment CT.TypeRepr (ToCrucTypes wtps)
toCrucTypes Ctx.Empty = Ctx.Empty
toCrucTypes (wReprs Ctx.:> wRepr) = toCrucTypes wReprs Ctx.:> CT.baseToType wRepr

baseCrucProof :: Ctx.Assignment WT.BaseTypeRepr wtps -> (ToBaseTypes (ToCrucTypes wtps) :~: wtps)
baseCrucProof Ctx.Empty = Refl
baseCrucProof (wtps Ctx.:> _) = case baseCrucProof wtps of
  Refl -> Refl