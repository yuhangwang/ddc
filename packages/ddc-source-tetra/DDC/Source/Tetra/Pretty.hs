{-# LANGUAGE TypeFamilies, UndecidableInstances #-}

-- | Pretty printing for Tetra modules and expressions.
module DDC.Source.Tetra.Pretty
        ( module DDC.Core.Pretty
        , module DDC.Base.Pretty 
        , PrettyLanguage)
where
import DDC.Source.Tetra.Exp.Predicates
import DDC.Source.Tetra.DataDef
import DDC.Source.Tetra.Module
import DDC.Source.Tetra.Exp.Source
import DDC.Type.Exp.Generic.Pretty
import DDC.Core.Pretty
import DDC.Base.Pretty
import Prelude                                  hiding ((<$>))
import qualified Data.Text                      as Text


type PrettyLanguage l 
 =      ( Pretty l
        , Pretty (GTAnnot    l)
        , Pretty (GTBindVar  l), Pretty (GTBoundVar l)
        , Pretty (GTBindCon  l), Pretty (GTBoundCon l)
        , Pretty (GTPrim     l)

        , Pretty (GXAnnot    l)
        , Pretty (GXBindVar  l), Pretty (GXBoundVar l)
        , Pretty (GXBindCon  l), Pretty (GXBoundCon l)
        , Pretty (GXPrim l)
        , Pretty (DaCon (GXBoundCon l) (GType l)))


instance Pretty Bind where
 ppr bb
  = case bb of 
        BNone   -> text "_"
        BAnon   -> text "^"
        BName t -> text (Text.unpack t)


instance Pretty Bound where
 ppr uu
  = case uu of
        UIx i   -> int i
        UName t -> text (Text.unpack t)
        UHole   -> text "?"


instance Pretty DaConBind where
 ppr (DaConBindName tt)         = text (Text.unpack tt)


instance Pretty DaConBound where
 ppr uu
  = case uu of
        DaConBoundName tt       -> text (Text.unpack tt)
        DaConBoundLit  pl       -> ppr  pl


instance Pretty TyConBind where
 ppr (TyConBindName tx)  = text (Text.unpack tx)


instance Pretty TyConBound where
 ppr (TyConBoundName tx) = text (Text.unpack tx)


-- Bind -------------------------------------------------------------------------------------------
instance PrettyLanguage l => Pretty (GXBindVarMT l) where
 ppr (XBindVarMT b mt)
  = case mt of
        Nothing         -> ppr b
        Just  _t        -> ppr b


-- Type -------------------------------------------------------------------------------------------
instance PrettyLanguage l => Pretty (GType l) where
 pprPrec d tt
  = case tt of
        TAnnot _ t      -> pprPrec d t
        TCon tc         -> ppr tc
        TVar bv         -> ppr bv

        TAbs bv k t
         -> text "λ" <> ppr bv <> text ":" <+> ppr k <> text "." <+> ppr t

        TApp (TApp (TCon TyConFun) t1) t2
         -> pprParen' (d > 5)
         $  pprPrec 6  t1 <+> text "->" <+> pprPrec 5 t2

        TApp t1 t2      
         -> pprParen' (d > 10)
         $  pprPrec 10 t1 <+> pprPrec 11 t2
 


instance PrettyLanguage l => Pretty (GTyCon l) where
 ppr tc
  = pprRawC tc


-- Module -----------------------------------------------------------------------------------------
instance PrettyLanguage l => Pretty (Module l) where
 ppr Module
        { moduleName            = name
        , moduleExportTypes     = _exportedTypes
        , moduleExportValues    = _exportedValues
        , moduleImportModules   = _importedModules
        , moduleImportTypes     = importedTypes
        , moduleImportValues    = importedValues
        , moduleTops            = tops }
  =  text "module" 
        <+> ppr name 
        <>  sImportedTypes
        <>  sImportedValues
        <>   (if null importedTypes && null importedValues
                then space <> text "where" 
                else text "where")
        <$$> (vcat $ map ppr tops)

  where sImportedTypes
         | null importedTypes   = empty
         | otherwise
         = line 
         <> (vcat $ map pprImportType importedTypes) 
         <> line

        sImportedValues
         | null importedValues  = empty
         | otherwise
         = (vcat $ map pprImportValue importedValues)
         <> line


-- Top --------------------------------------------------------------------------------------------
instance PrettyLanguage l => Pretty (Top l) where
 ppr (TopClause _ c) 
  =  ppr c
  <> semi <> line

 ppr (TopData _ (DataDef name params ctors))
  = (text "data"
        <+> hsep ( ppr name
                 : map pprParam params)
        <+> text "where"
        <+> lbrace)
  <$> indent 8
        (vcat [ ppr (dataCtorName ctor) 
                <+> text ":" 
                <+> (hsep   $ punctuate (text " ->") 
                                $ (  map (pprPrec 6) (dataCtorFieldTypes ctor)
                                  ++ [ ppr           (dataCtorResultType ctor)]))
                <> semi
                        | ctor       <- ctors ])
  <> line <> rbrace <> semi
  <> line

 ppr (TopType _ b t)
  =  text "type" <+> ppr b <+> text "=" <+> ppr t
  <> semi
  <> line

pprParam (b, t)
 = parens $ ppr b <> text ":" <+> ppr t


-- Exp --------------------------------------------------------------------------------------------
instance PrettyLanguage l => Pretty (GExp l) where
 pprPrec d xx
  = {-# SCC "ppr[Exp]" #-}
    case xx of
        XAnnot _ x      -> pprPrec d x

        XVar  u         -> ppr u
        XCon  dc        -> ppr dc
        XPrim u         -> ppr u
        
        XLAM  b xBody
         -> pprParen' (d > 1)
                 $   text "/\\" <>  ppr b <> text "."
                 <>  (if      isXLAM    xBody then empty
                      else if isXLam    xBody then line <> space
                      else if isSimpleX xBody then space
                      else    line)
                 <>  ppr xBody

        XLam b xBody
         -> pprParen' (d > 1)
                 $  text "\\" <> ppr b <> text "."
                 <> breakWhen (not $ isSimpleX xBody)
                 <> ppr xBody

        XApp x1 x2
         -> pprParen' (d > 10)
         $  pprPrec 10 x1 
                <> nest 4 (breakWhen (not $ isSimpleX x2) 
                           <> pprPrec 11 x2)

        XLet lts x
         ->  pprParen' (d > 2)
         $   ppr lts <+> text "in"
         <$> ppr x

        XCase x alts
         -> pprParen' (d > 2) 
         $  (nest 2 $ text "case" <+> ppr x <+> text "of" <+> lbrace <> line
                <> (vcat $ punctuate semi $ map ppr alts))
         <> line 
         <> rbrace

        XCast CastBox x
         -> pprParen' (d > 2)
         $  text "box"  <$> ppr x

        XCast CastRun x
         -> pprParen' (d > 2)
         $  text "run"  <+> ppr x

        XCast cc x
         ->  pprParen' (d > 2)
         $   ppr cc <+> text "in"
         <$> ppr x

        XType    t    -> text "[" <> ppr t <> text "]"
        XWitness w    -> text "<" <> ppr w <> text ">"

        XDefix    _ xs
         -> text "[" <> text "DEFIX|" <+> hsep (map (pprPrec 11) xs) <+> text "]"

        XInfixOp  _ str
         -> parens $ text "INFIXOP"  <+> text "\"" <> text str <> text "\""

        XInfixVar _ str
         -> parens $ text "INFIXVAR" <+> text "\"" <> text str <> text "\""

        XMatch _ alts xDefault
         -> pprParen' (d > 2)
         $  (nest 2 $ text "match" <+> lbrace <> line
                <> (vcat $ punctuate (semi <> line) $ map ppr alts))
         <> line
         <> rbrace
         <+> text "else" <+> pprPrec 10 xDefault

        XWhere _ x cls
         ->  pprParen' (d > 2)
         $   ppr x 
         <+> line
         <>  (text "where" 
                <+> text "{" <> line
                <>  (nest 4 $ vcat $ map ppr cls)
                <>  line
                <>  text "}")

        XLamPat _ p mt xBody
         -> pprParen' (d > 1)
         $  text "\\" 
                <> pprPrec 2 p 
                <> (case mt of
                        Just t  -> text ": " <> ppr t
                        Nothing -> empty)
                <> text "."
         <> breakWhen (not $ isSimpleX xBody)
         <> ppr xBody

        XLamCase _ alts
         -> pprParen' (d > 1)
         $  text "λcase." <> lbrace <> line
                <> (vcat $ punctuate semi $ map ppr alts)
         <> line <> rbrace


-- Lets -------------------------------------------------------------------------------------------
instance PrettyLanguage l => Pretty (GLets l) where
 ppr lts
  = case lts of
        LLet b x
         -> text "let"
                 <+> align (  ppr b
                           <> nest 2 ( breakWhen (not $ isSimpleX x)
                                     <> text "=" <+> align (ppr x)))
        LRec bxs
         -> let pprLetRecBind (b, x)
                 =   ppr b
                 <>  nest 2 (  breakWhen (not $ isSimpleX x)
                            <> text "=" <+> align (ppr x))
        
           in   (nest 2 $ text "letrec"
                  <+> lbrace 
                  <>  (  line 
                      <> (vcat $ punctuate (semi <> line)
                               $ map pprLetRecBind bxs)))
                <$> rbrace

        LPrivate bs Nothing []
         -> text "private"
                <+> (hcat $ punctuate space (map ppr bs))
        
        LPrivate bs Nothing bsWit
         -> text "private"
                <+> (hcat $ punctuate space (map ppr bs))
                <+> text "with"
                <+> braces (cat $ punctuate (text "; ") $ map ppr bsWit)

        LPrivate bs (Just parent) []
         -> text "extend"
                <+> ppr parent
                <+> text "using"
                <+> (hcat $ punctuate space (map ppr bs))

        LPrivate bs (Just parent) bsWit
         -> text "extend"
                <+> ppr parent
                <+> text "using"
                <+> (hcat $ punctuate space (map ppr bs))
                <+> text "with"
                <+> braces (cat $ punctuate (text "; ") $ map ppr bsWit)

        LGroup cs
         ->   text "letgroup" 
                <+> nest 2 (lbrace 
                                <> line 
                                <> (vcat $ map ppr cs)
                                <> line <> rbrace)


-- Clause -----------------------------------------------------------------------------------------
instance PrettyLanguage l => Pretty (GClause l) where
 ppr (SSig _ b t)
  = ppr b <+> text ":" <+> ppr t

 ppr (SLet _ b ps [GExp x])
  = ppr b       <+> hsep (map (pprPrec 10) ps) 
                <>  nest 2 ( breakWhen (not $ isSimpleX x)
                           <> text "=" <+> align (ppr x))

 ppr (SLet _ b ps gxs)
  = ppr b       <+> hsep (map (pprPrec 10) ps) 
                <>  nest 2 (line <> vcat (map (pprGuardedExp "=") gxs))


-- Param ------------------------------------------------------------------------------------------
instance PrettyLanguage l => Pretty (GParam l) where
 pprPrec _d (MType    b Nothing)
  = text "[" <> ppr b <> text "]"

 pprPrec _d (MType    b (Just t))
  = text "[" <> ppr b <> text ":" <+> ppr t <> text "]"

 pprPrec _d (MWitness b Nothing)
  = text "<" <> ppr b <> text ">"

 pprPrec _d (MWitness b (Just t))
  = text "<" <> ppr b <> text ":" <+> ppr t <> text ">"

 pprPrec d (MValue   p Nothing)
  = pprPrec d p

 pprPrec _ (MValue   p (Just t))
  = parens $ pprPrec 0 p <> text ":" <+> ppr t


-- Pat --------------------------------------------------------------------------------------------
instance PrettyLanguage l => Pretty (GPat l) where
 pprPrec d pp
  = case pp of
        PDefault        -> text "_"
        PAt   b p       -> ppr b <> text "@" <> ppr p
        PVar  b         -> ppr b

        PData u []      -> ppr u

        PData u ps
         -> pprParen' (d > 1) 
         $  ppr u <+> sep (map (pprPrec 2) ps)


-- GuardedExp -------------------------------------------------------------------------------------
pprGuardedExp :: PrettyLanguage l => String -> GGuardedExp l -> Doc
pprGuardedExp sTerm gx
  = pprGs "|" gx
  where
        pprGs _c (GExp x)
         = text sTerm <+> ppr x

        pprGs c (GGuard g gs)
         = pprG c g <> line <> pprGs "," gs

        pprG  c (GPat p x)
         = text c <+> ppr p  <+> text "<-" <+> ppr x

        pprG  c (GPred x)
         = text c <+> ppr x

        pprG  c GDefault
         = text c <+> text "otherwise"
        

-- Guard ------------------------------------------------------------------------------------------
instance PrettyLanguage l => Pretty (GGuard l) where
 ppr gg
  = case gg of
        GPat p w
         -> ppr p <+> text "<-" <+> ppr w

        GPred p
         -> ppr p

        GDefault
         -> text "otherwise"


-- AltCase ----------------------------------------------------------------------------------------
instance PrettyLanguage l => Pretty (GAltCase l) where
 ppr (AAltCase p gxs)
  =  ppr p <> nest 2 (line <> vcat (map (pprGuardedExp "->") gxs))


-- AltMatch ---------------------------------------------------------------------------------------
instance PrettyLanguage l => Pretty (GAltMatch l) where
 ppr (AAltMatch gs)
  = pprGuardedExp "=" gs


-- Cast -------------------------------------------------------------------------------------------
instance PrettyLanguage l => Pretty (GCast l) where
 ppr cc
  = case cc of
        CastWeakenEffect  eff -> text "weakeff" <+> brackets (ppr eff)
        CastPurify w    -> text "purify"  <+> angles   (ppr w)
        CastBox         -> text "box"
        CastRun         -> text "run"


-- Witness ----------------------------------------------------------------------------------------
instance PrettyLanguage l => Pretty (GWitness l) where
 pprPrec d ww
  = case ww of
        WAnnot _ w      -> ppr w
        WVar   n        -> ppr n
        WCon   wc       -> ppr wc
        WApp   w1 w2    -> pprParen (d > 10) (ppr w1 <+> pprPrec 11 w2)
        WType  t        -> text "[" <> ppr t <> text "]"


instance PrettyLanguage l => Pretty (GWiCon l) where
 ppr wc
  = case wc of
        WiConBound   u  _ -> ppr u


instance Pretty n => Pretty (DaCon n t) where
 ppr dc
  = case dc of
        DaConUnit       -> text "()"
        DaConPrim n _   -> ppr n
        DaConBound n    -> ppr n


-- Utils ------------------------------------------------------------------------------------------
breakWhen :: Bool -> Doc
breakWhen True   = line
breakWhen False  = space


isSimpleX :: GExp l -> Bool
isSimpleX xx
 = case xx of
        XAnnot _ x      -> isSimpleX x
        XVar{}          -> True
        XCon{}          -> True
        XType{}         -> True
        XWitness{}      -> True
        XApp x1 x2      -> isSimpleX x1 && isAtomX x2
        _               -> False


parens' :: Doc -> Doc
parens' d = lparen <> nest 1 d <> rparen


-- | Wrap a `Doc` in parens if the predicate is true.
pprParen' :: Bool -> Doc -> Doc
pprParen' b c
 = if b then parens' c
        else c

