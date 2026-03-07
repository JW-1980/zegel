#!/bin/bash
cd lib
dart analyze
cd ../cli
dart analyze
cd ../app
flutter analyze
