{-# OPTIONS -fwarn-unused-imports #-}

-- | Wrappers for compiler stages dealing with Sea code.
module Main.Sea
	( seaSub
	, seaCtor
	, seaThunking
	, seaForce
	, seaSlot
	, seaFlatten
	, seaInit
	, seaMain
	, outSea)
where
import Sea.Exp
import Sea.Util
import Main.Dump
import Data.Char
import Util
import DDC.Main.Arg
import DDC.Main.Pretty
import DDC.Main.Error
import Sea.Sub				(subTree)
import Sea.Ctor				(expandCtorTree)
import Sea.Proto			(addSuperProtosTree)
import Sea.Thunk			(thunkTree)
import Sea.Force			(forceTree)
import Sea.Slot				(slotTree)
import Sea.Flatten			(flattenTree)
import Sea.Init				(initTree, mainTree)
import DDC.Var.ModuleId
import qualified Core.Glob		as C
import qualified DDC.Config.Version	as Version


-- | Substitute trivial x1 = x2 bindings
seaSub
	:: (?args :: [Arg]
	 ,  ?pathSourceBase :: FilePath)
	=> Tree ()
	-> IO (Tree ())
	
seaSub tree
 = do
 	let tree'
		= subTree tree
		
	dumpET DumpSeaSub "sea-sub" 
		$ eraseAnnotsTree tree'
	
	return tree'
	

-- | Expand code for data constructors.
seaCtor 
	:: (?args :: [Arg]
	 ,  ?pathSourceBase :: FilePath)
	=> Tree ()
	-> IO (Tree ())

seaCtor eTree
 = do
	let eExpanded	= addSuperProtosTree
			$ expandCtorTree
			$ eTree
	
	dumpET DumpSeaCtor "sea-ctor" 
		$ eraseAnnotsTree eExpanded
	
	return eExpanded


-- | Expand code for creating thunks
seaThunking 
	:: (?args :: [Arg]
	 ,  ?pathSourceBase :: FilePath)
	=> Tree ()
	-> IO (Tree ())
	
seaThunking eTree
 = do
	let tree'	= thunkTree eTree
	dumpET DumpSeaThunk "sea-thunk" 
		$ eraseAnnotsTree tree'
	
	return tree'


-- | Add code for forcing suspensions
seaForce 
	:: (?args :: [Arg]
	 ,  ?pathSourceBase :: FilePath)
	=> Tree ()
	-> IO (Tree ())
	
seaForce eTree
 = do
	let tree'	= forceTree eTree
	dumpET DumpSeaForce "sea-force" 
		$ eraseAnnotsTree tree'

 	return	tree'


-- | Store pointers on GC slot stack.
seaSlot
	:: (?args :: [Arg]
	 ,  ?pathSourceBase :: FilePath)
	=> Tree ()		-- sea tree
	-> Tree ()		-- sea header
	-> C.Glob		-- header glob, used to get arities of supers
	-> C.Glob		-- source glob, TODO: refactor to take from Sea glob
	-> IO (Tree ())
	
seaSlot	eTree eHeader cgHeader cgSource
 = do
 	let tree'	= slotTree eTree eHeader cgHeader cgSource
	dumpET DumpSeaSlot "sea-slot" 
		$ eraseAnnotsTree tree'
	
	return	tree'


-- | Flatten out match expressions.
seaFlatten
	:: (?args :: [Arg]
	 ,  ?pathSourceBase :: FilePath)
	=> String
	-> Tree ()
	-> IO (Tree ())
	
seaFlatten unique eTree
 = do	let tree'	= flattenTree unique eTree
	dumpET DumpSeaFlatten "sea-flatten" 
		$ eraseAnnotsTree tree'
	
	return	tree'
 

-- | Add module initialisation code
seaInit
	:: (?args :: [Arg]
	 ,  ?pathSourceBase :: FilePath)
	=> ModuleId
	-> (Tree ())
	-> IO (Tree ())
	
seaInit moduleName eTree
 = do 	let tree'	= initTree moduleName eTree
 	dumpET DumpSeaInit "sea-init"
		$ eraseAnnotsTree tree'
		
	return tree'
	

-- | Create C source files
outSea 
	:: (?args :: [Arg])
	=> ModuleId
	-> (Tree ())		-- sea source
	-> FilePath		-- path of the source file
	-> [FilePath]		-- paths of the imported .h header files
	-> [String]		-- extra header files to include
	-> IO	( String
		, String )
		
outSea	
	moduleName
	eTree
	pathThis
	pathImports
	extraIncludes
	
 = do
	-- Break up the sea into Header/Code parts.
	let 	([ 	seaProtos, 		seaSupers
		 , 	seaCafProtos,		seaCafSlots,		seaCafInits
		 ,      _seaData
		 , 	seaHashDefs ], junk)

		 = partitionFs
			[ (=@=) PProto{}, 	(=@=) PSuper{}
			, (=@=) PCafProto{},	(=@=) PCafSlot{},	(=@=) PCafInit{}
			, (=@=) PData{}
			, (=@=) PHashDef{} ]
			eTree
		
	when (not $ null junk)
	 $ panic "Main.Sea" $ "junk sea bits = " ++ show junk ++ "\n"
		
	-- Build the C header
	let defTag	= makeIncludeDefTag pathThis
	let seaHeader
		=  [ PHackery $ makeComments pathThis
		   , PHackery ("#ifndef _inc" ++ defTag ++ "\n")
		   , PHackery ("#define _inc" ++ defTag ++ "\n\n") 
		   , PInclude "runtime/Runtime.h"
		   , PInclude "runtime/Prim.h" ]
		++ modIncludes pathImports
		++ (map PInclude extraIncludes)

		++ [ PHackery "\n"]	++ seaHashDefs
		++ [ PHackery "\n"]	++ seaCafProtos
		++ [ PHackery "\n"]	++ seaProtos
		++ [ PHackery "\n#endif\n\n" ]

	let seaHeaderS	
		= catMap pprStrPlain 
			$ eraseAnnotsTree seaHeader

	-- Build the C code
	let seaIncSelf	= modIncludeSelf pathThis
	
	let seaCode
		=  [PHackery $ makeComments pathThis]
		++ [seaIncSelf]
		++ [PHackery "\n"]	++ seaCafSlots
		++ [PHackery "\n"]	++ seaCafInits
		++ [PHackery "\n"]	++ seaSupers

	let seaCodeS	
		= catMap pprStrPlain
			$ eraseAnnotsTree seaCode
	
	--
	return	( seaHeaderS
		, seaCodeS )

modIncludeSelf p
 = let 	Just name	= takeLast $ chopOnRight '/' 
 			$ nameTItoH p
   in	PIncludeAbs $ name

modIncludes pathImports
  = map PInclude pathImports

nameTItoH nameTI
 = let	parts	= chopOnRight '.' nameTI
   in   concat (init parts ++ ["ddc.h"])
   
makeComments pathThis
  = unlines
	[ "// -----------------------"
	, "//       source: " ++ pathThis
	, "// generated by: " ++ Version.ddcName
	, "" ]
	
makeIncludeDefTag pathThis
 = filter (\c -> isAlpha c || isDigit c)
 	$ pathThis
		
	
-- | Add main module entry point code.
seaMain	:: (?args :: [Arg])
	=> [ModuleId]
	-> ModuleId
	-> IO (Tree ())
	
seaMain imports mainModule
	= return $ mainTree imports mainModule
	




