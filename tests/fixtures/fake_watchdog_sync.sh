#!/bin/sh

# Record a persistence flush without touching real GPS files.
printf 'sync run\n' >> "${WOMO_FAKE_ACTION_LOG:?}"
