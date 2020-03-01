{-# LANGUAGE DataKinds #-}
{-# LANGUAGE EmptyCase #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE FlexibleInstances #-}
{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE ScopedTypeVariables #-}
{-# LANGUAGE StandaloneDeriving #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE TypeInType #-}
{-# LANGUAGE TypeOperators #-}
{-# LANGUAGE UndecidableInstances #-}
-- | Support for "pseudo" archtiectures that wrap other architectures to provide
-- extra operands beyond the native architecture
--
-- This is primarily used in semmc-learning for learning machine code
-- instruction semantics.  It is included in this base library so that semmc
-- architecture implementations can provide the necessary primitives without
-- depending on semmc-learning.
module SemMC.Architecture.Pseudo (
  Pseudo,
  ArchitectureWithPseudo(..),
  EmptyPseudo,
  pseudoAbsurd,
  SynthOpcode(..),
  SynthInstruction(..),
  RvwpOptimization(..)
  ) where

import           Data.Kind
import           Data.Parameterized.Classes
import           Data.Parameterized.HasRepr ( HasRepr(..) )
import qualified Data.Parameterized.SymbolRepr as SR
import qualified Data.Parameterized.List as SL
import           Data.Proxy ( Proxy(..) )
import           GHC.TypeLits ( Symbol )

import qualified Dismantle.Instruction.Random as D

import qualified SemMC.Architecture as A
import qualified SemMC.Architecture.View as V


-- | The type of pseudo-ops for the given architecture.
--
-- If you don't want any pseudo-ops, then just use 'EmptyPseudo':
--
-- > type instance Pseudo <your arch> = EmptyPseudo
-- > instance ArchitectureWithPseudo <your arch> where
-- >   assemblePseudo _ = pseudoAbsurd
type family Pseudo arch :: (Symbol -> Type) -> [Symbol] -> Type

-- | An architecture with pseuo-ops.
class (A.Architecture arch,
       ShowF (Pseudo arch (A.Operand arch)),
       TestEquality (Pseudo arch (A.Operand arch)),
       OrdF (Pseudo arch (A.Operand arch)),
       HasRepr (Pseudo arch (A.Operand arch)) (A.ShapeRepr arch),
       D.ArbitraryOperands (Pseudo arch) (A.Operand arch)) =>
      ArchitectureWithPseudo arch where
  -- | Turn a given pseudo-op with parameters into a series of actual,
  -- machine-level instructions.
  assemblePseudo :: proxy arch -> Pseudo arch o sh -> SL.List o sh -> [A.Instruction arch]

----------------------------------------------------------------
-- * Helper type for arches with no pseudo ops
--
-- $emptyPseudo
--
-- See 'Pseudo' type family above for usage.

data EmptyPseudo o sh

deriving instance Show (EmptyPseudo o sh)

-- | Do proof-by-contradiction by eliminating an `EmptyPseudo`.
pseudoAbsurd :: EmptyPseudo o sh -> a
pseudoAbsurd = \case

instance D.ArbitraryOperands EmptyPseudo o where
  arbitraryOperands _gen = pseudoAbsurd

instance ShowF (EmptyPseudo o)

instance TestEquality (EmptyPseudo o) where
  testEquality = pseudoAbsurd

instance OrdF (EmptyPseudo o) where
  compareF = pseudoAbsurd

instance HasRepr (EmptyPseudo o) (SL.List SR.SymbolRepr) where
  typeRepr = pseudoAbsurd



-- | An opcode in the context of this learning process.
--
-- We need to represent it as such so that, when generating formulas, we can use
-- the much simpler direct formulas of the pseudo-ops, rather than the often
-- complicated formulas generated by the machine instructions equivalent to the
-- pseudo-op.
data SynthOpcode arch sh = RealOpcode (A.Opcode arch (A.Operand arch) sh)
                         -- ^ An actual, machine opcode
                         | PseudoOpcode (Pseudo arch (A.Operand arch) sh)
                         -- ^ A pseudo-op

deriving instance (Show (A.Opcode arch (A.Operand arch) sh),
          Show (Pseudo arch (A.Operand arch) sh)) =>
         Show (SynthOpcode arch sh)

instance forall arch . (ShowF (A.Opcode arch (A.Operand arch)),
                        ShowF (Pseudo arch (A.Operand arch))) =>
         ShowF (SynthOpcode arch) where
  withShow _ (_ :: q sh) x =
    withShow (Proxy @(A.Opcode arch (A.Operand arch))) (Proxy @sh) $
    withShow (Proxy @(Pseudo arch (A.Operand arch))) (Proxy @sh) $
    x

instance (TestEquality (A.Opcode arch (A.Operand arch)),
          TestEquality (Pseudo arch (A.Operand arch))) =>
         TestEquality (SynthOpcode arch) where
  testEquality (RealOpcode op1) (RealOpcode op2) =
    fmap (\Refl -> Refl) (testEquality op1 op2)
  testEquality (PseudoOpcode pseudo1) (PseudoOpcode pseudo2) =
    fmap (\Refl -> Refl) (testEquality pseudo1 pseudo2)
  testEquality _ _ = Nothing

instance (TestEquality (A.Opcode arch (A.Operand arch)),
          TestEquality (Pseudo arch (A.Operand arch))) =>
         Eq (SynthOpcode arch sh) where
  op1 == op2 = isJust (testEquality op1 op2)

mapOrderingF :: (a :~: b -> c :~: d) -> OrderingF a b -> OrderingF c d
mapOrderingF _ LTF = LTF
mapOrderingF f EQF =
  case f Refl of
    Refl -> EQF
mapOrderingF _ GTF = GTF

instance (OrdF (A.Opcode arch (A.Operand arch)),
          OrdF (Pseudo arch (A.Operand arch))) =>
         OrdF (SynthOpcode arch) where
  compareF (RealOpcode op1) (RealOpcode op2) =
    mapOrderingF (\Refl -> Refl) (compareF op1 op2)
  compareF (RealOpcode _) (PseudoOpcode _) = LTF
  compareF (PseudoOpcode _) (RealOpcode _) = GTF
  compareF (PseudoOpcode pseudo1) (PseudoOpcode pseudo2) =
    mapOrderingF (\Refl -> Refl) (compareF pseudo1 pseudo2)

instance (OrdF (A.Opcode arch (A.Operand arch)),
          OrdF (Pseudo arch (A.Operand arch))) =>
         Ord (SynthOpcode arch sh) where
  compare op1 op2 = toOrdering (compareF op1 op2)

instance (rep ~ A.ShapeRepr arch,
          HasRepr ((A.Opcode arch) (A.Operand arch)) rep,
          HasRepr ((Pseudo arch) (A.Operand arch)) rep) =>
  HasRepr (SynthOpcode arch) rep where
  typeRepr (RealOpcode op) = typeRepr op
  typeRepr (PseudoOpcode op) = typeRepr op

-- | Like 'D.GenericInstruction', but can have either a real or a pseudo-opcode.
data SynthInstruction arch =
  forall sh . SynthInstruction (SynthOpcode arch sh) (SL.List (A.Operand arch) sh)

instance (TestEquality (A.Opcode arch (A.Operand arch)),
          TestEquality (Pseudo arch (A.Operand arch)),
          TestEquality (A.Operand arch)) =>
         Eq (SynthInstruction arch) where
  SynthInstruction op1 list1 == SynthInstruction op2 list2 =
    isJust (testEquality op1 op2) && isJust (testEquality list1 list2)

instance (OrdF (A.Opcode arch (A.Operand arch)),
          OrdF (Pseudo arch (A.Operand arch)),
          OrdF (A.Operand arch)) =>
         Ord (SynthInstruction arch) where
  compare (SynthInstruction op1 list1) (SynthInstruction op2 list2) =
    toOrdering (compareF op1 op2) <> toOrdering (compareF list1 list2)

instance (ShowF (A.Operand arch), ShowF (A.Opcode arch (A.Operand arch)), ShowF (Pseudo arch (A.Operand arch))) => Show (SynthInstruction arch) where
  showsPrec p (SynthInstruction op lst) = showParen (p > app_prec) $
    showString "SynthInstruction " .
    showsPrecF (app_prec+1) op .
    showString " " .
    showsPrec (app_prec+1) lst
    where
      app_prec = 10

class RvwpOptimization arch where
  -- | The @rvwpMov dst src@ returns an instruction sequence that
  -- moves @src@ to @dst@, if available. This allows us to fix a
  -- candidate with a single right value in the wrong place.
  rvwpMov :: V.View arch n -> V.View arch n -> Maybe [SynthInstruction arch]
  -- If we add support for fixing multiple rvs in the wps, then we'll
  -- want to have
  {-
  rvwpSwap :: V.View arch n -> V.View arch n -> Maybe [SynthInstruction arch]
  -}
  -- that does an in place swap, e.g. via xor if the underlying arch
  -- doesn't support it directly.
