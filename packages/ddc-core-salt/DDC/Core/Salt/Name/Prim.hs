
-- | Names shared by several language profiles.
module DDC.Core.Salt.Name.Prim
        ( PrimTyCon     (..),   readPrimTyCon

        , PrimOp        (..)
        , PrimCast      (..),   readPrimCast
        , PrimCall      (..),   readPrimCall
        , PrimControl   (..),   readPrimControl
        , PrimStore     (..),   readPrimStore
        , PrimArith     (..),   readPrimArith)
where
import DDC.Base.Pretty
import Data.Char
import Data.List


-- PrimTyCon -----------------------------------------------------------------
-- | Primitive type constructors.
data PrimTyCon
        -- | @Void#@ the Void type has no values.
        = PrimTyConVoid

        -- | @Bool#@ unboxed booleans.
        | PrimTyConBool

        -- | @Nat#@ natural numbers.
        --   Big enough to count every addressable byte in the system.
        | PrimTyConNat

        -- | @Int#@ signed integers,
        | PrimTyConInt

        -- | @WordN#@ machine words of the given length.
        | PrimTyConWord   Int

        -- | @FloatN#@ floating point numbers of the given length.
        | PrimTyConFloat  Int

        -- | @Tag#@ data type tags.
        | PrimTyConTag

        -- | @Addr#@ machine addresses.
        | PrimTyConAddr

        -- | @Ptr#@ store pointers.
        | PrimTyConPtr

        -- | @String#@ String of UTF8 characters.
        -- 
        --   These are primitive until we can define our own unboxed types.
        | PrimTyConString 
        deriving (Eq, Ord, Show)


instance Pretty PrimTyCon where
 ppr tc
  = case tc of
        PrimTyConVoid           -> text "Void#"
        PrimTyConBool           -> text "Bool#"
        PrimTyConNat            -> text "Nat#"
        PrimTyConInt            -> text "Int#"
        PrimTyConWord   bits    -> text "Word"  <> int bits <> text "#"
        PrimTyConFloat  bits    -> text "Float" <> int bits <> text "#"
        PrimTyConTag            -> text "Tag#"
        PrimTyConAddr           -> text "Addr#"
        PrimTyConPtr            -> text "Ptr#"
        PrimTyConString         -> text "String#"


-- | Read a primitive typ constructor.
readPrimTyCon :: String -> Maybe PrimTyCon
readPrimTyCon str
        | str == "Void#"   = Just $ PrimTyConVoid
        | str == "Bool#"   = Just $ PrimTyConBool
        | str == "Nat#"    = Just $ PrimTyConNat
        | str == "Int#"    = Just $ PrimTyConInt
        | str == "Tag#"    = Just $ PrimTyConTag
        | str == "Addr#"   = Just $ PrimTyConAddr
        | str == "Ptr#"    = Just $ PrimTyConPtr
        | str == "String#" = Just $ PrimTyConString

        -- WordN#
        | Just rest     <- stripPrefix "Word" str
        , (ds, "#")     <- span isDigit rest
        , not $ null ds
        , n             <- read ds
        , elem n [8, 16, 32, 64]
        = Just $ PrimTyConWord n

        -- FloatN#
        | Just rest     <- stripPrefix "Float" str
        , (ds, "#")     <- span isDigit rest
        , not $ null ds
        , n             <- read ds
        , elem n [32, 64]
        = Just $ PrimTyConFloat n

        | otherwise
        = Nothing


-- PrimOp ---------------------------------------------------------------------
-- | Primitive operators implemented directly by the machine or runtime system.
data    PrimOp
        -- | Arithmetic and bitwise-operators.
        = PrimArith     PrimArith

        -- | Casting between numeric types.
        | PrimCast      PrimCast

        -- | Raw store access.
        | PrimStore     PrimStore

        -- | Special function calling conventions.
        | PrimCall      PrimCall

        -- | Non-functional control flow.
        | PrimControl   PrimControl
        deriving (Eq, Ord, Show)


instance Pretty PrimOp where
 ppr pp
  = case pp of
        PrimArith    op -> ppr op
        PrimCast     c  -> ppr c
        PrimStore    p  -> ppr p
        PrimCall     c  -> ppr c
        PrimControl  c  -> ppr c


-- PrimCast -------------------------------------------------------------------
-- | Primitive cast between two types.
data PrimCast
        -- | Promote a value to one of a larger or similar size, 
        --   without loss of precision.
        = PrimCastPromote

        -- | Truncate a value to a new width, 
        --   possibly losing precision.
        | PrimCastTruncate
        deriving (Eq, Ord, Show)


instance Pretty PrimCast where
 ppr c
  = case c of
        PrimCastPromote         -> text "promote#"
        PrimCastTruncate        -> text "truncate#"


readPrimCast :: String -> Maybe PrimCast
readPrimCast str
 = case str of
        "promote#"              -> Just PrimCastPromote
        "truncate#"             -> Just PrimCastTruncate
        _                       -> Nothing


-- PrimCall -------------------------------------------------------------------
-- | Primitive ways of invoking a function, 
--   where control flow returns back to the caller.
data PrimCall
        -- | Tailcall a function
        = PrimCallTail    Int
        deriving (Eq, Ord, Show)


instance Pretty PrimCall where
 ppr pc
  = case pc of
        PrimCallTail    arity
         -> text "tailcall" <> int arity <> text "#"


readPrimCall :: String -> Maybe PrimCall
readPrimCall str

        -- tailcallN#
        | Just rest     <- stripPrefix "tailcall" str
        , (ds, "#")     <- span isDigit rest
        , not $ null ds
        , n             <- read ds
        , n > 0
        = Just $ PrimCallTail n

        | otherwise
        = Nothing


-- PrimControl ----------------------------------------------------------------
-- | Primitive non-returning control flow.
data PrimControl
        -- | Ungraceful failure -- just abort the program.
        --   This is called on internal errors in the runtime system.
        --   There is no further debugging info provided, so you'll need to 
        --   look at the stack trace to debug it.
        = PrimControlFail

        -- | Return from the enclosing function with the given value.
        | PrimControlReturn
        deriving (Eq, Ord, Show)


instance Pretty PrimControl where
 ppr pc
  = case pc of
        PrimControlFail         -> text "fail#"
        PrimControlReturn       -> text "return#"


readPrimControl :: String -> Maybe PrimControl
readPrimControl str
 = case str of
        "fail#"         -> Just $ PrimControlFail
        "return#"       -> Just $ PrimControlReturn
        _               -> Nothing


-- PrimStore --------------------------------------------------------------------
-- | A projection of some other object.
data PrimStore
        -- Constants ------------------
        -- | Number of bytes needed to store a value of a primitive type.
        = PrimStoreSize

        -- | Log2 of number of bytes need to store a value of a primitive type.
        | PrimStoreSize2

        -- Allocation -----------------
        -- | Create a heap of the given size.
        --     This must be called before alloc# below, and has global side effect. 
        --     Calling it twice in the same program is undefined.
        | PrimStoreCreate

        -- | Check whether there is this many bytes on the heap.
        | PrimStoreCheck

        -- | Force a GC to recover this many bytes.
        | PrimStoreRecover

        -- | Allocate some space on the heap.
        --   There must be enough space available, else undefined.
        | PrimStoreAlloc

        -- Addr operations ------------
        -- | Read a value from the store at a given address and offset.
        | PrimStoreRead

        -- | Write a value to the store at the given address and offset.
        | PrimStoreWrite

        -- | Add an offset to an address.
        | PrimStorePlusAddr

        -- | Subtract an offset from an address.
        | PrimStoreMinusAddr

        -- Ptr operations -------------
        -- | Read a value from a pointer plus the given offset.
        | PrimStorePeek

        -- | Write a value to a pointer plus the given offset.
        | PrimStorePoke

        -- | Add an offset to a pointer.
        | PrimStorePlusPtr

        -- | Subtract an offset from a pointer.
        | PrimStoreMinusPtr

        -- | Convert an raw address to a pointer.
        | PrimStoreMakePtr

        -- | Convert a pointer to a raw address.
        | PrimStoreTakePtr

        -- | Cast between pointer types.
        | PrimStoreCastPtr
        deriving (Eq, Ord, Show)


instance Pretty PrimStore where
 ppr p
  = case p of        
        PrimStoreSize           -> text "size#"
        PrimStoreSize2          -> text "size2#"        
        PrimStoreCreate         -> text "create#"
        PrimStoreCheck          -> text "check#"
        PrimStoreRecover        -> text "recover#"
        PrimStoreAlloc          -> text "alloc#"

        PrimStoreRead           -> text "read#"
        PrimStoreWrite          -> text "write#"
        PrimStorePlusAddr       -> text "plusAddr#"
        PrimStoreMinusAddr      -> text "minusAddr#"

        PrimStorePeek           -> text "peek#"
        PrimStorePoke           -> text "poke#"
        PrimStorePlusPtr        -> text "plusPtr#"
        PrimStoreMinusPtr       -> text "minusPtr#"
        PrimStoreMakePtr        -> text "makePtr#"
        PrimStoreTakePtr        -> text "takePtr#"
        PrimStoreCastPtr        -> text "castPtr#"


readPrimStore :: String -> Maybe PrimStore
readPrimStore str
 = case str of
        "size#"                 -> Just PrimStoreSize
        "size2#"                -> Just PrimStoreSize2

        "create#"               -> Just PrimStoreCreate
        "check#"                -> Just PrimStoreCheck
        "recover#"              -> Just PrimStoreRecover
        "alloc#"                -> Just PrimStoreAlloc

        "read#"                 -> Just PrimStoreRead
        "write#"                -> Just PrimStoreWrite
        "plusAddr#"             -> Just PrimStorePlusAddr
        "minusAddr#"            -> Just PrimStoreMinusAddr

        "peek#"                 -> Just PrimStorePeek
        "poke#"                 -> Just PrimStorePoke
        "plusPtr#"              -> Just PrimStorePlusPtr
        "minusPtr#"             -> Just PrimStoreMinusPtr
        "makePtr#"              -> Just PrimStoreMakePtr
        "takePtr#"              -> Just PrimStoreTakePtr
        "castPtr#"              -> Just PrimStoreCastPtr

        _                       -> Nothing


-- PrimArith ------------------------------------------------------------------
-- | Primitive arithmetic, logic, or comparison opretors.
--   We expect the backend/machine to be able to implement these directly.
data PrimArith
        -- arithmetic
        = PrimArithNeg
        | PrimArithAdd
        | PrimArithSub
        | PrimArithMul
        | PrimArithDiv
        | PrimArithRem

        -- comparison
        | PrimArithEq
        | PrimArithNeq
        | PrimArithGt
        | PrimArithGe
        | PrimArithLt
        | PrimArithLe

        -- boolean
        | PrimArithAnd
        | PrimArithOr

        -- bitwise
        | PrimArithShl
        | PrimArithShr
        | PrimArithBAnd
        | PrimArithBOr
        | PrimArithBXOr
        deriving (Eq, Ord, Show)


instance Pretty PrimArith where
 ppr op
  = let Just (_, n) = find (\(p, _) -> op == p) primArithNames
    in  (text n)


-- | Read a primitive operator.
readPrimArith :: String -> Maybe PrimArith
readPrimArith str
  =  case find (\(_, n) -> str == n) primArithNames of
        Just (p, _)     -> Just p
        _               -> Nothing


-- | Names of primitve operators.
primArithNames :: [(PrimArith, String)]
primArithNames
 =      [ (PrimArithNeg,        "neg#")
        , (PrimArithAdd,        "add#")
        , (PrimArithSub,        "sub#")
        , (PrimArithMul,        "mul#")
        , (PrimArithDiv,        "div#")
        , (PrimArithRem,        "rem#")
        , (PrimArithEq ,        "eq#" )
        , (PrimArithNeq,        "neq#")
        , (PrimArithGt ,        "gt#" )
        , (PrimArithGe ,        "ge#" )
        , (PrimArithLt ,        "lt#" )
        , (PrimArithLe ,        "le#" )
        , (PrimArithAnd,        "and#")
        , (PrimArithOr ,        "or#" ) 
        , (PrimArithShl,        "shl#")
        , (PrimArithShr,        "shr#")
        , (PrimArithBAnd,       "band#")
        , (PrimArithBOr,        "bor#")
        , (PrimArithBXOr,       "bxor#") ]

