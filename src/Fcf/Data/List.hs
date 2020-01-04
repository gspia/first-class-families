{-# LANGUAGE
    DataKinds,
    PolyKinds,
    TypeFamilies,
    TypeInType,
    TypeOperators,
    UndecidableInstances #-}

-- | Lists.
module Fcf.Data.List
  ( Foldr
  , Unfoldr
  , UnList
  , Cons
  , type (++)
  , Concat
  , ConcatMap
  , Filter
  , Head
  , Last
  , Tail
  , Init
  , Null
  , Length
  , Replicate
  , Find
  , FindIndex
  , Elem
  , Lookup
  , SetIndex
  , ZipWith
  , Zip
  , Unzip
  , Cons2
  ) where

import qualified GHC.TypeLits as TL

import Fcf.Core
import Fcf.Combinators
import Fcf.Classes
import Fcf.Data.Common
import Fcf.Data.Nat
import Fcf.Utils

data Cons :: a -> [a] -> Exp [a]
type instance Eval (Cons a as) = a ': as

data Foldr :: (a -> b -> Exp b) -> b -> [a] -> Exp b
type instance Eval (Foldr f y '[]) = y
type instance Eval (Foldr f y (x ': xs)) = Eval (f x (Eval (Foldr f y xs)))

-- | N.B.: This is equivalent to a 'Foldr' flipped.
data UnList :: b -> (a -> b -> Exp b) -> [a] -> Exp b
type instance Eval (UnList y f xs) = Eval (Foldr f y xs)

-- Helper for the Unfoldr.
data UnfoldrCase :: (b -> Exp (Maybe (a,b))) -> Maybe (a,b) -> Exp [a]
type instance Eval (UnfoldrCase f ('Just '(a,b))) =
    Eval ( '[a] ++ Eval (Unfoldr f b) )
type instance Eval (UnfoldrCase _ 'Nothing) = '[]

-- | Type-level Unfoldr.
--
-- Example:
--
-- >>> data ToThree :: Nat -> Exp (Maybe (Nat,Nat))
-- >>> type instance Eval (ToThree b) = Eval
-- >>>     (If ( Eval ( b Fcf.>= 4) )
-- >>>         (Pure Nothing)
-- >>>         (Pure (Just '(b, b TL.+ 1 )))
-- >>>     )
--
-- >>> :kind! Eval (Unfoldr ToThree 0)
--
-- See also the definition of `Replicate`.
data Unfoldr :: (b -> Exp (Maybe (a,b))) -> b -> Exp [a]
type instance Eval (Unfoldr f c) = Eval
    (If (Eval (IsJust (f @@ c)))
         ( Pure (Eval (UnfoldrCase f =<< Pure (f @@ c) ) ) )
         ( Pure '[] )
    )


data (++) :: [a] -> [a] -> Exp [a]
type instance Eval ((++) '[] ys) = ys
type instance Eval ((++) (x ': xs) ys) = x ': Eval ((++) xs ys)

-- | Concat for lists.
--
-- Examples:
--
-- >>> :kind! Eval (Concat ( '[ '[1,2], '[3,4], '[5,6])
-- >>> :kind! Eval (Concat ( '[ '[Int, Maybe Int], '[Maybe String, Either Double Int]])
type Concat lsts = Foldr (++) '[] lsts

-- | ConcatMap for lists.
type ConcatMap f lst = Concat (Eval (Map f lst))

data Filter :: (a -> Exp Bool) -> [a] -> Exp [a]
type instance Eval (Filter _p '[]) = '[]
type instance Eval (Filter p (a ': as)) =
  If (Eval (p a))
    (a ': Eval (Filter p as))
    (Eval (Filter p as))

data Head :: [a] -> Exp (Maybe a)
type instance Eval (Head '[]) = 'Nothing
type instance Eval (Head (a ': _as)) = 'Just a

data Last :: [a] -> Exp (Maybe a)
type instance Eval (Last '[]) = 'Nothing
type instance Eval (Last (a ': '[])) = 'Just a
type instance Eval (Last (a ': b ': as)) = Eval (Last (b ': as))

data Init :: [a] -> Exp (Maybe [a])
type instance Eval (Init '[]) = 'Nothing
type instance Eval (Init (a ': '[])) = 'Just '[]
type instance Eval (Init (a ': b ': as)) =
  Eval (Map (Cons a) =<< (Init (b ': as)))

data Tail :: [a] -> Exp (Maybe [a])
type instance Eval (Tail '[]) = 'Nothing
type instance Eval (Tail (_a ': as)) = 'Just as

data Null :: [a] -> Exp Bool
type instance Eval (Null '[]) = 'True
type instance Eval (Null (a ': as)) = 'False

data Length :: [a] -> Exp Nat
type instance Eval (Length '[]) = 0
type instance Eval (Length (a ': as)) = 1 TL.+ Eval (Length as)

-- Helper for the Replicate.
data NumIter :: a -> Nat -> Nat -> Exp (Maybe (a,Nat))
type instance Eval (NumIter a s b) = Eval
    (If ( Eval ( b >= s) )
        (Pure 'Nothing)
        (Pure ('Just '( a, b TL.+ 1 )))
    )

-- | Type-level `Replicate` for lists.
--
-- Example:
--
-- >>> :kind Eval (Replicate 4 '("ok",2))
type Replicate n a = Unfoldr (NumIter a n) 0


data Find :: (a -> Exp Bool) -> [a] -> Exp (Maybe a)
type instance Eval (Find _p '[]) = 'Nothing
type instance Eval (Find p (a ': as)) =
  If (Eval (p a))
    ('Just a)
    (Eval (Find p as))

-- | Find the index of an element satisfying the predicate.
data FindIndex :: (a -> Exp Bool) -> [a] -> Exp (Maybe Nat)
type instance Eval (FindIndex _p '[]) = 'Nothing
type instance Eval (FindIndex p (a ': as)) =
  Eval (If (Eval (p a))
    (Pure ('Just 0))
    (Map ((+) 1) =<< FindIndex p as))

type Elem a as = IsJust =<< FindIndex (TyEq a) as

-- | Find an element associated with a key.
-- @
-- 'Lookup' :: k -> [(k, b)] -> 'Exp' ('Maybe' b)
-- @
type Lookup (a :: k) (as :: [(k, b)]) =
  (Map Snd (Eval (Find (TyEq a <=< Fst) as)) :: Exp (Maybe b))

-- | Modify an element at a given index.
--
-- The list is unchanged if the index is out of bounds.
data SetIndex :: Nat -> a -> [a] -> Exp [a]
type instance Eval (SetIndex n a' as) = SetIndexImpl n a' as

type family SetIndexImpl (n :: Nat) (a' :: k) (as :: [k]) where
  SetIndexImpl _n _a' '[] = '[]
  SetIndexImpl 0 a' (_a ': as) = a' ': as
  SetIndexImpl n a' (a ': as) = a ': SetIndexImpl (n TL.- 1) a' as

data ZipWith :: (a -> b -> Exp c) -> [a] -> [b] -> Exp [c]
type instance Eval (ZipWith _f '[] _bs) = '[]
type instance Eval (ZipWith _f _as '[]) = '[]
type instance Eval (ZipWith f (a ': as) (b ': bs)) =
  Eval (f a b) ': Eval (ZipWith f as bs)

-- |
-- @
-- 'Zip' :: [a] -> [b] -> 'Exp' [(a, b)]
-- @
type Zip = ZipWith (Pure2 '(,))

data Unzip :: Exp [(a, b)] -> Exp ([a], [b])
type instance Eval (Unzip as) = Eval (Foldr Cons2 '( '[], '[]) (Eval as))

data Cons2 :: (a, b) -> ([a], [b]) -> Exp ([a], [b])
type instance Eval (Cons2 '(a, b) '(as, bs)) = '(a ': as, b ': bs)

