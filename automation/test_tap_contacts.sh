#!/bin/bash

UDID="132B1310-2AF5-45F4-BB8E-CA5A2FEB9481"

# Tap menu button
idb ui tap 361 1447 --udid "$UDID"

# Very short delay
sleep 0.2

# Tap contacts icon (third from left in expanded menu)
idb ui tap 368 1447 --udid "$UDID"