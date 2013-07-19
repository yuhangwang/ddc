
module DDC.Core.Blue.Env
        ( primDataDefs
        , primSortEnv
        , primKindEnv
        , primTypeEnv)
where
import DDC.Core.Blue.Prim
import DDC.Core.Blue.Compounds
import DDC.Type.DataDef
import DDC.Type.Exp
import DDC.Type.Env             (Env)
import qualified DDC.Type.Env   as Env


-- DataDefs -------------------------------------------------------------------
-- | Data type definitions 
--
-- >  Type                         Constructors
-- >  ----                ------------------------------
-- >  Bool                True False
-- >  Nat                 0 1 2 ...
-- >  Int                 ... -2i -1i 0i 1i 2i ...
-- >  Word{8,16,32,64}#   42w8 123w64 ...
-- 
primDataDefs :: DataDefs Name
primDataDefs
 = fromListDataDefs
        -- Primitive -----------------------------------------------
        -- Bool
        [ DataDef (NameTyConPrim TyConPrimBool) 
                [] 
                (Just   [ (NameLitBool True,  []) 
                        , (NameLitBool False, []) ])

        -- Nat
        , DataDef (NameTyConPrim TyConPrimNat)  [] Nothing

        -- Int
        , DataDef (NameTyConPrim TyConPrimInt)  [] Nothing

        -- WordN
        , DataDef (NameTyConPrim (TyConPrimWord 64)) [] Nothing
        , DataDef (NameTyConPrim (TyConPrimWord 32)) [] Nothing
        , DataDef (NameTyConPrim (TyConPrimWord 16)) [] Nothing
        , DataDef (NameTyConPrim (TyConPrimWord 8))  [] Nothing
        ]

-- Sorts ---------------------------------------------------------------------
-- | Sort environment containing sorts of primitive kinds.
primSortEnv :: Env Name
primSortEnv  = Env.setPrimFun sortOfPrimName Env.empty


-- | Take the sort of a primitive kind name.
sortOfPrimName :: Name -> Maybe (Sort Name)
sortOfPrimName _ = Nothing


-- Kinds ----------------------------------------------------------------------
-- | Kind environment containing kinds of primitive data types.
primKindEnv :: Env Name
primKindEnv = Env.setPrimFun kindOfPrimName Env.empty


-- | Take the kind of a primitive name.
--
--   Returns `Nothing` if the name isn't primitive. 
--
kindOfPrimName :: Name -> Maybe (Kind Name)
kindOfPrimName nn
 = case nn of
        NameTyConPrim tc                -> Just $ kindTyConPrim tc
        _                               -> Nothing


-- Types ----------------------------------------------------------------------
-- | Type environment containing types of primitive operators.
primTypeEnv :: Env Name
primTypeEnv = Env.setPrimFun typeOfPrimName Env.empty


-- | Take the type of a name,
--   or `Nothing` if this is not a value name.
typeOfPrimName :: Name -> Maybe (Type Name)
typeOfPrimName dc
 = case dc of
        NameOpPrimArith p       -> Just $ typeOpPrimArith p

        NameLitBool _           -> Just $ tBool
        NameLitNat  _           -> Just $ tNat
        NameLitInt  _           -> Just $ tInt
        NameLitWord _ bits      -> Just $ tWord bits

        _                       -> Nothing
