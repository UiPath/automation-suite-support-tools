# Ceph Manager Tool
CephManager is a bash script that can be used to help manage storage issues with ceph.

Ceph is a storage solution UiPath deploys in Automation Suite. It provides us with S3 style buckets for storing
files. 

It can be used to print information about storage usage and can be used to trigger cleanup of some logs.

_NOTE: The cleanDatasets option should never be used without assistance from UiPath. See Additional Notes_

## Installation
To install the tool from a linux machine (with internet access).
```
wget https://github.com/UiPath/automation-suite-support-tools/raw/main/Scripts/cephManager/cephManager.zip
unzip cephManager.zip
chmod -R 755 cephManager
```

For airgapped, download the zip file and transfer to the your linux machine. Then run the following commands:
```
unzip cephManager.zip
chmod -R 755 cephManager
```

## Usage
```
Usage: cephManager.sh --storageStats | --aicenterStats | --cleanSFLogs | --cleanPipeline | --cleanDatasets"
    -s  | --storageStats         Display the storage stats."
    -a  | --aicenterStats        Display the aicenter storage stats."
    -cs | --cleanSFLogs          Clean the sf logs."
    -cp | --cleanPipeline        Clean the pipeline logs and artifacts."
    -ds | --cleanDatasets        Clean the datasets."
    -h  | --help                 Displays this message
```

## Examples
```
Examples:
    cephManager.sh --storageStats
    cephManager.sh --aicenterStats
    cephManager.sh --cleanSFLogs
    cephManager.sh --cleanPipeline
    cephManager.sh --cleanDatasets
    cephManager.sh --help  
```

## Detailed Options Explanation

### storageStats
This option will display bucket statistics. In the output we include:
1. Storage usage by bucket
    ```
    BucketName                                                     NoOfObjects  SizeInMB
    --------------------                                           ------       ------
    train-data                                                     0            0
    dataservice
    prometheus                                                     52           1217
    orchestrator-fd2bd9fd-4190-46b9-b10b-8d543a879cff              8            21
    rook-ceph-bucket-checker-583d3717-c9cf-4341-a313-198ca1b6f926  0            0
    testbucket
    uipath                                                         5058         6866
    orchestrator-host                                              484          2831
    sf-logs                                                        6732         610
    ```

    In the above output, we can see eight buckets, and we can see storage statics for each. The largest bucket is the uipath bucket.

    For the most part cleanup of bucket data is managed through the UI in Automation Suite. For example in the output we have one 
    orchestrator bucket called: orchestrator-fd2bd9fd-4190-46b9-b10b-8d543a879cff. This represents bucket storage for a tenant in 
    in the instance. Deleting bucket data would reduce the storage.

    The only buckets we would manually cleanup would be for items within train-data or sf-logs (as of writing this).

2. Total capacity versus usage
    ```
    MB Total  MB Available   MB Used
    102400    90217.8828125  12182.1171875
    ```

    This shows the total MB available vs used. MB Total will be higher then used due to some overhead.

### aicenterStats

This will give detailed information about the specific folders within the train-data bucket. 

It will print out the parent folders within a given tenant and show usage. This is mostly used 
for triaging storage issues.

The output will show usage for each tenant. Each tenant will have:
    1. Folders representing projects. These will follow the format train-data/training-XXXX/XXXX
    2. Folders representing pipeline artificats. These will follow the format train-data/training-XXXX/PipelineRuns
    3. Folders representing ML skill logs: These will follow the format train-data/training-XXXX/Logs

The XXXX represent GUIDs. We do not provide a way to map the GUID to the tenants in this script. The GUID would have to
be crossed checked via the UI or DB. However the purpose is of this script is to simply identify _if_ something is using
more storage then expected.

If more detailed analysis is needed, open a ticket with uipath support.

### cleanSFLogs

Deletes all logs older than seven days from sf-logs. AS has an automatic job to do this but 
if it ever fails this can be used (mostly for older versions where a bug caused some logs to be 
missed)

It will run in the background after triggering.

### cleanPipeline

This will clean the logs and artifacts from pipelines executed in AI Center. It is possible to do this
from the UI but it can be tedious.

This deletes data from all pipelines. This is normally safe to do as the data can be regenerated but if 
any artifacts are need make sure to download those from the UI first.

It would not affect packages that have been produced from pipelines.

### cleanupDatasets

This option should only be ran with assistance from UiPath. This will delete all datasets in AI Center. It should only 
be used when the datasets only contain training data that was exported from labeling sessions.

In AI Center, for DU packages, the process involves labeling documents and then exporting them. Each export causes data
to be duplicated and the export is typically used for training a single pipeline. We can delete the dataset and always
re-export it from the labeling session.

Datasets can be deleted from the UI but in cases where datasets were never cleanup and the incredible amounts of duplication
occured. We can delete all the datasets and re-export any that are need from the labeling session.

