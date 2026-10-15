#!/usr/bin/env bash
set -eu
echo "Requesting a small interactive allocation."
echo "If needed, edit this script to add your site's --partition and --account."
salloc --ntasks=1 --cpus-per-task=1 --mem=512M --time=00:10:00 bash
