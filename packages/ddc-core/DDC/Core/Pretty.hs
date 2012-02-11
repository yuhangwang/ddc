
-- | Pretty printing for core expressions.
module DDC.Core.Pretty 
        ( module DDC.Type.Pretty
        , module DDC.Base.Pretty)
where
import DDC.Core.Exp
import DDC.Core.Compounds
import DDC.Core.Predicates
import DDC.Type.Pretty
import DDC.Type.Compounds
import DDC.Type.Predicates
import DDC.Base.Pretty


-- Binder ---------------------------------------------------------------------
-- | Pretty print a binder, adding spaces after names.
--   The RAnon and None binders don't need spaces, as they're single symbols.
pprBinderSep   :: Pretty n => Binder n -> Doc
pprBinderSep bb
 = case bb of
        RName v         -> ppr v
        RAnon           -> text "^"
        RNone           -> text "_"


-- | Print a group of binders with the same type.
pprLamBinderGroup :: (Pretty n, Eq n) => ([Binder n], Type n) -> Doc                            -- TODO: refactor into below
pprLamBinderGroup (rs, t)
        = text "\\"  <> parens ((cat $ map pprBinderSep rs) <+> text ":" <+> ppr t) <> dot

pprLAMBinderGroup :: (Pretty n, Eq n) => ([Binder n], Type n) -> Doc
pprLAMBinderGroup (rs, t)
        = text "/\\" <> parens ((cat $ map pprBinderSep rs) <+> text ":" <+> ppr t) <> dot


-- Exp ------------------------------------------------------------------------
instance (Pretty n, Eq n) => Pretty (Exp a n) where
 pprPrec d xx
  = case xx of
        XVar  _ u       -> ppr u
        XCon  _ tc      -> ppr tc
        
        XLAM{}
         -> let Just (bs, xBody) = takeXLAMs xx
                groups = partitionBindsByType bs
            in  pprParen' (d > 1)
                 $  (cat $ map pprLAMBinderGroup groups) 
                 <>  (if      isXLAM    xBody then empty
                      else if isXLam    xBody then line <> space
                      else if isSimpleX xBody then space
                      else    line)
                 <>  ppr xBody

        XLam{}
         -> let Just (bs, xBody) = takeXLams xx
                groups = partitionBindsByType bs
            in  pprParen' (d > 1)
                 $  (cat $ map pprLamBinderGroup groups) 
                 <> breakWhen (not $ isSimpleX xBody)
                 <> ppr xBody

        XApp _ x1 x2
         -> pprParen' (d > 10)
         $  pprPrec 10 x1 
                <> nest 4 (breakWhen (not $ isSimpleX x2) 
                           <> pprPrec 11 x2)

        XLet _ lts x
         -> pprParen' (d > 2)
         $   ppr lts <+> text "in"
         <$> ppr x

        XCase _ x alts
         -> pprParen' (d > 2) 
         $  (nest 2 $ text "case" <+> ppr x <+> text "of" <+> lbrace <> line
                <> (vcat $ punctuate semi $ map ppr alts))
         <> line 
         <> rbrace

        XCast _ cc x
         -> pprParen' (d > 10)
         $  ppr cc <+> text "in" <> line
         <> pprPrec 10 x

        XType    t      -> text "[" <> ppr t <> text "]"
        XWitness w      -> text "<" <> ppr w <> text ">"


-- Pat ------------------------------------------------------------------------
instance (Pretty n, Eq n) => Pretty (Pat n) where
 ppr pp
  = case pp of
        PDefault        -> text "_"
        PData u bs      -> ppr u <+> sep (map pprPatBind bs)


-- | Pretty print a binder, 
--   showing its type annotation only if it's not bottom.
pprPatBind :: (Eq n, Pretty n) => Bind n -> Doc
pprPatBind b
        | isBot (typeOfBind b)  = ppr $ binderOfBind b
        | otherwise             = parens $ ppr b


-- Alt ------------------------------------------------------------------------
instance (Pretty n, Eq n) => Pretty (Alt a n) where
 ppr (AAlt p x)
  = ppr p <+> nest 1 (line <> nest 3 (text "->" <+> ppr x))


-- Cast -----------------------------------------------------------------------
instance (Pretty n, Eq n) => Pretty (Cast n) where
 ppr cc
  = case cc of
        CastWeakenEffect  eff   
         -> text "weakeff" <+> brackets (ppr eff)

        CastWeakenClosure clo
         -> text "weakclo" <+> brackets (ppr clo)

        CastPurify w
         -> text "purify"  <+> angles   (ppr w)

        CastForget w
         -> text "forget"  <+> angles   (ppr w)


-- Lets -----------------------------------------------------------------------
instance (Pretty n, Eq n) => Pretty (Lets a n) where
 ppr lts
  = case lts of
        LLet m b x
         -> let dBind = if isBot (typeOfBind b)
                          then ppr (binderOfBind b)
                          else ppr b
            in  text "let"
                 <+> align (  dBind <> ppr m
                           <> nest 2 ( breakWhen (not $ isSimpleX x)
                                     <> text "=" <+> align (ppr x)))

        LRec bxs
         -> let pprLetRecBind (b, x)
                 =   ppr (binderOfBind b)
                 <+> text ":"
                 <+> ppr (typeOfBind b)
                 <>  nest 2 (  breakWhen (not $ isSimpleX x)
                            <> text "=" <+> align (ppr x))
        
           in   (nest 2 $ text "letrec"
                  <+> lbrace 
                  <>  (  line 
                      <> (vcat $ punctuate (semi <> line)
                               $ map pprLetRecBind bxs)))
                <$> rbrace


        LLetRegion b []
         -> text "letregion"
                <+> ppr (binderOfBind b)

        LLetRegion b bs
         -> text "letregion"
                <+> ppr (binderOfBind b)
                <+> text "with"
                <+> braces (cat $ punctuate (text "; ") $ map ppr bs)

        LWithRegion b
         -> text "withregion"
                <+> ppr b


instance (Pretty n, Eq n) => Pretty (LetMode n) where
 ppr lm
  = case lm of
        LetStrict        -> empty
        LetLazy Nothing  -> text " lazy"
        LetLazy (Just w) -> text " lazy <" <> ppr w <> text ">"


-- Witness --------------------------------------------------------------------
instance (Pretty n, Eq n) => Pretty (Witness n) where
 pprPrec d ww
  = case ww of
        WCon wc         -> ppr wc
        WVar n          -> ppr n

        WApp w1 w2
         -> pprParen (d > 10) (ppr w1 <+> pprPrec 11 w2)
         
        WJoin w1 w2
         -> pprParen (d > 9)  (ppr w1 <+> text "&" <+> ppr w2)

        WType t         -> text "[" <> ppr t <> text "]"


instance Pretty WiCon where
 ppr wc
  = case wc of
        WiConPure       -> text "pure"
        WiConEmpty      -> text "empty"
        WiConGlobal     -> text "global"
        WiConConst      -> text "const"
        WiConMutable    -> text "mutable"
        WiConLazy       -> text "lazy"
        WiConManifest   -> text "manifest"
        WiConUse        -> text "use"
        WiConRead       -> text "read"
        WiConAlloc      -> text "alloc"


-- Utils ----------------------------------------------------------------------
breakWhen :: Bool -> Doc
breakWhen True   = line
breakWhen False  = space

isAtomT :: Type n -> Bool
isAtomT tt
 = case tt of
        TVar{}          -> True
        TCon{}          -> True
        _               -> False

isAtomW :: Witness n -> Bool
isAtomW ww
 = case ww of
        WVar{}          -> True
        WCon{}          -> True
        _               -> False

isAtomX :: Exp a n -> Bool
isAtomX xx
 = case xx of
        XVar{}          -> True
        XCon{}          -> True
        XType t         -> isAtomT t
        XWitness w      -> isAtomW w
        _               -> False



isSimpleX :: Exp a n -> Bool
isSimpleX xx
 = case xx of
        XVar{}          -> True
        XCon{}          -> True
        XType{}         -> True
        XWitness{}      -> True
        XApp _ x1 x2    -> isSimpleX x1 && isAtomX x2
        _               -> False


parens' :: Doc -> Doc
parens' d = lparen <> nest 1 d <> rparen


-- | Wrap a `Doc` in parens if the predicate is true.
pprParen' :: Bool -> Doc -> Doc
pprParen' b c
 = if b then parens' c
        else c
