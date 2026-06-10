# NAB survey drop folder

Drop the monthly NAB business survey file here (xlsx, xls or csv), any filename.
Pushing to this folder triggers a nowcast run automatically; the new survey shows
up in the release table as "NAB Business Survey" with its measured impact.

Newer files override overlapping months — don't delete old ones. Parsing is by
header matching ("business conditions", "business confidence", "capacity
utilisation", "trading", "employment" + a date column). Full details in the
repo README.
