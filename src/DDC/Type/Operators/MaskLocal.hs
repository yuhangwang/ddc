{-# OPTIONS -fwarn-incomplete-patterns -fwarn-unused-matches -fwarn-name-shadowing #-}
module DDC.Type.Operators.MaskLocal
	(maskLocalT)
where
import Util
import Shared.VarPrim
import DDC.Type.Exp
import DDC.Type.Predicates
import DDC.Type.Compounds
import DDC.Type.Kind
import DDC.Type.Builtin
import DDC.Type.Pretty	()
import qualified Data.Set	as Set


-- | Mask effects on local regions.
--   At generalisation time, if a region is not present in the type or closure of a
--   function then is local to that function and all effects involving that region 
--   can be erased from the type.
--
--   We can also erase Const/Mutable Lazy/Direct constraints because these will be
--   fulfilled by the letregion construct used to locally create the region.
--
maskLocalT :: Set Type -> Type -> Type
maskLocalT tsVis tt
 = case tt of
	TForall  b k t1	
	 -> TForall b k (maskLocalT tsVis t1)

	TConstrain t1 crs
	 -> TConstrain t1 
	  $ constraintsOfFetters
	  $ catMaybes 
	  $ map (maskF tsVis)
	  $ fettersOfConstraints crs

	_ -> tt


-- | Erase read effects to regions not in this list.
--	also erase Const, Mutable, Lazy, Direct constraints on regions not in the list
maskF :: Set Type -> Fetter -> Maybe Fetter
maskF	tsVis (FWhere t1 t2)
	| isEffect t1
	= Just $ FWhere t1 (maskE tsVis t2)

maskF	tsVis (FConstraint v [tR])
	| elem v [primConst, primMutable, primLazy, primDirect]
	, isTClass tR || isSomeTVar tR
	, not $ Set.member tR tsVis
	= Nothing
	
maskF	_ f	
	= Just f


-- | Erase read effects to regions not in this list.
maskE :: Set Type -> Effect -> Effect
maskE	 tsVis	eff
	= makeTSum kEffect 
	$ catMaybes $ map (maskE' tsVis) 
	$ flattenTSum eff 

	
maskE'	tsVis eff

	| TApp t1 tR	<- eff
	, elem t1 [tRead, tWrite]
	, isTClass tR || isSomeTVar tR
	, not $ Set.member tR tsVis
	= Nothing
	
	| otherwise
	= Just eff


