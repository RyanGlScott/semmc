{-# LANGUAGE GADTs #-}
{-# LANGUAGE TemplateHaskell #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE KindSignatures #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE DataKinds #-}
{-# LANGUAGE ViewPatterns #-}
{-# LANGUAGE PatternSynonyms #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE TypeOperators #-}

module SemMC.Architecture.ARM.Location
    ( Location(..)
    , ArchRepr(..)
    , locMem
    , locPC
    , locRepr
    )
    where

import           Data.Parameterized.Classes
import           Data.Parameterized.Ctx
import           Data.Parameterized.NatRepr
import           Data.Parameterized.TH.GADT
import           Data.Semigroup
import qualified Dismantle.ARM.A32 as A32
import qualified Dismantle.ARM.T32 as T32
import qualified SemMC.Architecture as A
import           What4.BaseTypes
import qualified What4.Interface as WI

import qualified Language.ASL.Globals as ASL

import           Prelude

class ArchRepr arch where
  regWidthRepr :: proxy arch -> NatRepr (A.RegWidth arch)

-- ----------------------------------------------------------------------

-- | A location is simply an index into the globals
data Location arm :: BaseType -> * where
  Location :: ASL.GlobalRef s -> Location arm (ASL.GlobalsType s)

locPC :: Location arm (BaseBVType 32)
locPC = Location $ ASL.knownGlobalRef @"_PC"

locMem :: Location arm
            (WI.BaseArrayType (EmptyCtx ::> WI.BaseBVType 32)
              (WI.BaseBVType 8))
locMem = Location $ ASL.knownGlobalRef @"__Memory"

locRepr :: Location arm tp -> WI.BaseTypeRepr tp
locRepr (Location gr) = ASL.globalRefRepr gr

instance Show (Location arm tp) where
  show loc = case loc of
    _ | Just Refl <- testEquality locPC loc -> "PC"
    _ | Just Refl <- testEquality locMem loc -> "Mem"
    Location gr | Just Refl <- ASL.testGlobalEq @"_Rbv" gr -> "R"
    Location gr -> show $ ASL.globalRefSymbol gr

instance ShowF (Location arm) 

instance TestEquality (Location arm) where
  testEquality (Location gr1) (Location gr2) = testEquality (ASL.globalRefRepr gr1) (ASL.globalRefRepr gr2)

instance OrdF (Location arm) where
  compareF (Location gr1) (Location gr2) = compareF (ASL.globalRefRepr gr1) (ASL.globalRefRepr gr2)
