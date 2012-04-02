
module DDC.Core.Transform.Flatten
        (flatten)
where
import DDC.Core.Transform.TransformX
import qualified DDC.Core.Transform.LiftX       as L
import qualified DDC.Core.Transform.AnonymizeX  as A
import DDC.Core.Exp
import Data.Functor.Identity


flatten :: Ord n 
        => (TransformUpMX Identity c)
        => c a n -> c a n
flatten = transformUpX' flatten1


-- | Perform let-floating on strict non-recursive lets
--   Only does the top level, to clean up the ones directly produced by makeLets.
--   let b1 = (let b2 = def2 in x2)
--   in x1
--   ==>
--   let b2 = def2
--   in let b1 = x2
--   in x1
flatten1
        :: Ord n
        => Exp a n
        -> Exp a n

-- We only do this if b2 is anonymous (ones generated by makeLets are).
-- If we tried to wrap x1 in b2 when b2's name is already used,
-- we'd be in trouble.
flatten1
    (XLet a1
        (LLet LetStrict b1
            (XLet a2 (LLet LetStrict b2@(BAnon _) def2) x2))
        x1)
 = let  -- If b1 is anon, we don't want to lift references to it
        liftDepth = case b1 of { BAnon _ -> 1; _ -> 0 }
        x1'       = L.liftAtDepthX 1 liftDepth x1
   in   XLet a2 (LLet LetStrict b2 def2) 
         $ flatten1
         $ XLet a1 (LLet LetStrict b1 x2) x1'

-- Same as above but b2 isn't anonymous.
-- anonymize inner let & re-flatten.
flatten1
    (XLet a1
        (LLet LetStrict b1 inner@(XLet _ (LLet LetStrict _ _) _))
        x1)
 = flatten1
 $ XLet a1
        (LLet LetStrict b1 (A.anonymizeX inner))
        x1

-- Any let, its bound expression doesn't contain a strict non-recursive
-- let so just flatten the body
flatten1 (XLet a1 llet1 x1)
 = XLet a1 llet1 (flatten1 x1)

-- Anything else we can ignore. 
-- We don't need to recurse, because this is always called immediately after
-- makeLets.
flatten1 x = x

