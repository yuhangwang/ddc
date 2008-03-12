
module Main.Dump
	( dumpST
	, dumpS
	, dumpDot
	, dumpCT
	, dumpET
	, dumpOpen)

where

import Main.Arg

import qualified Source.Pretty

import qualified Core.Pretty
import qualified Core.Util

import qualified Sea.Pretty
import qualified Type.Pretty

import Shared.Pretty
import System.IO
import Util

-- | Convert an arg into the pretty mode it enables
takePrettyMode :: Arg -> Maybe PrettyMode
takePrettyMode aa
 = case aa of
 	DumpPrettyUnique	-> Just $ PrettyUnique
	DumpPrettyTypeSpaces	-> Just $ PrettyTypeSpaces
	DumpPrettyCoreTypes	-> Just $ PrettyCoreTypes
	_			-> Nothing

-- | Dump a source tree
dumpST flag name sourceTree
 = do	let pprMode	= catMaybes $ map takePrettyMode ?args

 	when (elem flag ?args)
  	 (writeFile 
		(?pathSourceBase ++ ".dump-" ++ name ++ ".ds")
		(concat $ map (pprStr pprMode)
			$ sourceTree))
	
	return ()

-- | Dump a string
dumpS flag name str
 = do	when (elem flag ?args)
	 (writeFile 
	 	(?pathSourceBase ++ ".dump-" ++ name ++ ".ds")
		str)
	
	return ()

-- | Dump a dot file
dumpDot flag name str
 = do	when (elem flag ?args)
	 (writeFile 
	 	(?pathSourceBase ++ ".graph-" ++ name ++ ".dot")
		str)
	
	return ()


-- | Dump a core tree
dumpCT flag name tree
 = do	let pprMode	= catMaybes $ map takePrettyMode ?args

 	when (elem flag ?args)
  	 (writeFile 
		(?pathSourceBase ++ ".dump-" ++ name ++ ".dc")
		(catInt "\n"
			$ map (pprStr pprMode)
			$ tree))
	
	return ()


-- Dump a sea tree
dumpET flag name tree
 = do	let pprMode	= catMaybes $ map takePrettyMode ?args

 	when (elem flag ?args)
  	 (writeFile 
		(?pathSourceBase ++ ".dump-" ++ name ++ ".c")
		(catInt "\n"
			$ map (pprStr pprMode)
			$ tree))
	
	return ()


-----
dumpOpen flag name
 = do	
	if elem flag ?args
	 then do
	 	h	<- openFile 
				(?pathSourceBase ++ ".dump-" ++ name ++ ".ds") 
				WriteMode
		return $ Just h
		
	 else	return Nothing
