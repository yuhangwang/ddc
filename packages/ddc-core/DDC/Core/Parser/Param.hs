
module DDC.Core.Parser.Param
        ( ParamSpec     (..)
        , funTypeOfParams
        , expOfParams
        , pBindParamSpec)
where
import DDC.Core.Exp
import DDC.Core.Parser.Type
import DDC.Core.Parser.Base             (Parser)
import DDC.Core.Lexer.Tokens
import qualified DDC.Base.Parser        as P
import qualified DDC.Type.Compounds     as T


-- | Specification of a function parameter.
--   We can determine the contribution to the type of the function, 
--   as well as its expression based on the parameter.
data ParamSpec n
        = ParamType    (Bind n)
        | ParamWitness (Bind n)
        | ParamValue   (Bind n) (Type n) (Type n)


-- | Build the type of a function from specifications of its parameters,
--   and the type of the body.
funTypeOfParams 
        :: [ParamSpec n]        -- ^ Spec of parameters.
        -> Type n               -- ^ Type of body.
        -> Type n               -- ^ Type of whole function.

funTypeOfParams [] tBody        = tBody
funTypeOfParams (p:ps) tBody
 = case p of
        ParamType  b    
         -> TForall b 
                $ funTypeOfParams ps tBody

        ParamWitness b
         -> T.tImpl (T.typeOfBind b)
                $ funTypeOfParams ps tBody

        ParamValue b eff clo
         -> T.tFun (T.typeOfBind b) eff clo 
                $ funTypeOfParams ps tBody


-- | Build the expression of a function from specifications of its parameters,
--   and the expression for the body.
expOfParams 
        :: a
        -> [ParamSpec n]        -- ^ Spec of parameters.
        -> Exp a n              -- ^ Body of function.
        -> Exp a n              -- ^ Expression of whole function.

expOfParams _ [] xBody            = xBody
expOfParams a (p:ps) xBody
 = case p of
        ParamType b     
         -> XLAM a b $ expOfParams a ps xBody
        
        ParamWitness b
         -> XLam a b $ expOfParams a ps xBody

        ParamValue b _ _
         -> XLam a b $ expOfParams a ps xBody


-- | Parse a parameter specification.
--
--       [BIND1 BIND2 .. BINDN : TYPE]
--   or  (BIND : TYPE)
--   or  (BIND : TYPE) { EFFECT | CLOSURE }
--
pBindParamSpec :: Ord n => Parser n [ParamSpec n]
pBindParamSpec
 = P.choice
        -- Type parameter
        -- [BIND1 BIND2 .. BINDN : TYPE]
 [ do   pTok KSquareBra
        bs      <- P.many1 pBinder
        pTok KColon
        t       <- pType
        pTok KSquareKet
        return  [ ParamType b 
                | b <- zipWith T.makeBindFromBinder bs (repeat t)]


        -- Witness parameter
        -- <BIND : TYPE>
 , do   pTok KAngleBra
        b       <- pBinder
        pTok KColon
        t       <- pType
        pTok KAngleKet
        return  [ ParamWitness $ T.makeBindFromBinder b t]

        -- Value parameter
        -- (BIND : TYPE) 
        -- (BIND : TYPE) { TYPE | TYPE }
 , do   pTok KRoundBra
        b       <- pBinder
        pTok KColon
        t       <- pType
        pTok KRoundKet

        (eff, clo) 
         <- P.choice
                [ do    pTok KBraceBra
                        eff'    <- pType
                        pTok KBar
                        clo'    <- pType
                        pTok KBraceKet
                        return  (eff', clo')
                
                , do    return  (T.tBot T.kEffect, T.tBot T.kClosure) ]
                

        return  $ [ParamValue (T.makeBindFromBinder b t) eff clo]
 ]


