
module DDC.Driver.Command.ToC
        (cmdToC)
where
import DDC.Driver.Stage
import DDC.Driver.Source
import DDC.Build.Pipeline
import DDC.Build.Language
import DDC.Core.Fragment
import System.FilePath
import Control.Monad.Trans.Error
import Control.Monad.IO.Class
import qualified DDC.Build.Language.Salt        as Salt
import qualified DDC.Build.Language.Lite        as Lite
import qualified DDC.Base.Pretty                as P


-- | Parse, check, and convert a module to C.
--
--   The output is printed to @stdout@. 
--
cmdToC  :: Config       -- ^ Compiler configuration.
        -> Language     -- ^ Language definition.
        -> Source       -- ^ Source of the code.
        -> String       -- ^ Program module text.
        -> ErrorT String IO ()

cmdToC config language source sourceText
 | Language bundle      <- language
 , fragment             <- bundleFragment  bundle
 , profile              <- fragmentProfile fragment
 = do   
        let fragName = profileName profile
        let mSuffix  = case source of 
                        SourceFile filePath     -> Just $ takeExtension filePath
                        _                       -> Nothing

        -- Decide what to do based on file extension and current fragment.
        let compile
                -- Compile a Core Lite module.
                | fragName == "Lite" || mSuffix == Just ".dcl"
                = liftIO
                $ pipeText (nameOfSource source) (lineStartOfSource source) sourceText
                $ PipeTextLoadCore Lite.fragment
                [ PipeCoreStrip
                [ stageLiteOpt     config source 
                [ stageLiteToSalt  config source 
                [ stageSaltOpt     config source
                [ stageSaltToC     config source SinkStdout]]]]]

                -- Compile a Core Salt module.
                | fragName == "Salt" || mSuffix == Just ".dcs"
                = liftIO
                $ pipeText (nameOfSource source) (lineStartOfSource source) sourceText
                $ PipeTextLoadCore Salt.fragment
                [ PipeCoreStrip
                [ stageSaltOpt     config source
                [ stageSaltToC     config source SinkStdout]]]

                -- Unrecognised.
                | otherwise
                = throwError "Don't know how to convert this to C"


        -- Throw any errors that arose during compilation
        errs <- compile
        case errs of
         []     -> return ()
         es     -> throwError $ P.renderIndent $ P.vcat $ map P.ppr es

