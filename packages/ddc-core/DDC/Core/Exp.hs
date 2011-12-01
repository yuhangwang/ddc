
-- | Abstract syntax for the DDC core language.
module DDC.Core.Exp 
        ( module DDC.Type.Exp

          -- * Computation expressions
        , Exp  (..)
        , Cast (..)
        , Lets (..)
        , Alt  (..)
        , Pat  (..)
                        
          -- * Witnesses expressions
        , Witness (..)
        , WiCon   (..))
where
import DDC.Type.Exp


-- Values -----------------------------------------------------------------------------------------
-- | A value expression, universe of computation.
data Exp a p n
        -- | Value variable.
        = XVar  a (Bound n)

        -- | A primitive operator or literal.
        | XPrim a p

        -- | Data constructor.
        | XCon  a (Bound n)

        -- | Value application.
        | XApp  a (Exp a p n) (Exp a p n)

        -- | Function abstraction.
        | XLam  a (Bind n)    (Exp a p n)

        -- | Some possibly recursive definitions.
        | XLet  a (Lets a p n) (Exp a p n)

        -- | Case branching.
        | XCase a (Exp a p n) [Alt a p n]

        -- | Type cast.
        | XCast a (Exp a p n) (Cast n)

        -- | Type can appear as the argument of an `XApp`.
        | XType    (Type n)

        -- | Witness can appear as the argument of an `XApp`.
        | XWitness (Witness n)
        deriving (Eq, Show)


-- | Type casts.
data Cast n
        -- | Weaken the effect of an expression.
        = CastWeakenEffect  (Effect n)
        
        -- | Weaken the closure of an expression.
        | CastWeakenClosure (Closure n)

        -- | Purify the effect of an expression.
        | CastPurify (Witness n)

        -- | Hide sharing in a closure of an expression.
        | CastForget (Witness n)
        deriving (Eq, Show)


-- | Possibly recursive bindings.
data Lets a p n
        -- | Non-recursive binding
        = LLet  (Bind n) (Exp a p n)
        
        -- | Recursive binding
        | LRec  [(Bind n, Exp a p n)]

        -- | Bind a local region variable, and (non-recursive) witnesses to its properties.
        | XLocal (Bind n) [(Bind n, Type n)]
        deriving (Eq, Show)


-- | Case alternatives.
data Alt a p n
        = XAlt (Pat p n) (Exp a p n)
        deriving (Eq, Show)


-- | Pattern matches.
data Pat p n

        -- | The default pattern always succeeds.
        = PDefault

        -- | Match a literal.
        | PLit  p

        -- | Match a data constructor and bind its arguments.
        | PData (Bound n) [Bind n]
        deriving (Eq, Show)
        

-- Witness ----------------------------------------------------------------------------------------
data Witness n
        -- | Witness constructor.
        = WCon  WiCon 
        
        -- | Witness variable.
        | WVar  n
        
        -- | Witness application.
        | WApp  (Witness n) (Witness n)

        -- | Joining of witnesses.
        | WJoin (Witness n) (Witness n)
        deriving (Eq, Show)


-- | Witness constructor.
data WiCon
        -- | The pure effect is pure
        = WiConPure             -- pure     :: Pure (!0)

        -- | The empty closure is empty
        | WiConEmpty            -- empty    :: Empty ($0)

        -- | Witness that a region is constant.
        | WiConConst            -- const    :: [r: %]. Const r
        
        -- | Witness that a region is mutable.
        | WiConMutable          -- mutable  :: [r: %]. Mutable r

        -- | Witness that a region is lazy.
        | WiConLazy             -- lazy     :: [r: %]. Const r
        
        -- | Witness that a region is direct.
        | WiConDirect           -- direct   :: [r: %]. Mutable r

        -- | Purify a read from a constant region.
        | WiConRead             -- read     :: [r: %]. Const r => Pure  (Read r)

        -- | Hide the sharing of a constant region.
        | WiConShare            -- share    :: [r: %]. Const r => Empty (Share r)

        -- | Witness that some regions are distinct.
        | WiConDistinct Int     -- distinct :: [r0 r1 ... rn : %]. Distinct_n r0 r1 .. rn
        deriving (Eq, Show)

