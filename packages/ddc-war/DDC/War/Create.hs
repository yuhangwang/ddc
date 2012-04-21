
module DDC.War.Create
        (create)
where
import DDC.War.Interface.Config
import DDC.War.Job
import Data.Maybe
import Data.Set                 (Set)
import qualified DDC.War.Create.CreateDCE       as CreateDCE

create :: Way -> Set FilePath -> FilePath -> [Chain]
create way allFiles filePath
 =      catMaybes
        [ creat way allFiles filePath
        | creat <- [ CreateDCE.create ]]




