#!/bin/bash

yardoc -q --no-progress --no-stats && cp -pur doc/*.png yardoc/ && cp -pur yardoc/* ../schul-dashboard-doc/
cd ../schul-dashboard-doc/
git add * && git commit -a -m 'Updated documentation' && git push -q origin gh-pages
cd ../schul-dashboard/

