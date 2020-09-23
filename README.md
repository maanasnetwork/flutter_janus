# flutterjanus

Flutter plugin for Janus Gateway. flutterjanus is port of janus.js. All the functions and calls are mapped in flutter to make things easy for porting an existing javascript app for flutter. The calls are modified only to suit the static typing of the flutter.

## Organisation

The code is organised in four files

- janus.dart - This file contains the static calls and basic transport mechanism with the backend janus server
- session.dart - This file is the heart of the whole plugin. All the janus.js calls are mapped in this file with same nomenclature. Some of the code inside the files are commented with // FIX ME to take care of the flutter requirements. A lot of code inside this file is not required as those are browser specific which will be cleaned at later date when all the tests are working properly.
- plugin.dart - This file defines the template plugin which is initialised when a webrtc session is set. In janus.js this is defined a dictionary one time for websocet and one time for the http. This has been moved to seperate file to provide a template strucutre and also to enable static type checking in flutter.
- callbacks.dart - This file defines the template callbacks which are used in janus.js. A single point definition of the callback structure enables better code checking in flutter.

## Status

| Feature         | Support | Well Tested |
| --------------- | ------- | ----------- |
| WebSocket       | Yes     | Yes         |
| Rest/Http API   | Yes     | Yes         |
| Echotest Plugin | Yes     | No          |

## Getting Started

Clone the repository and then update the janus server url in the examples/lib/janus_demo_echo.dart file. Build and you should be able to run the janus.js echotest example.

## Road Ahead

- I will be porting the other janus examples also to create one to one mapping with janus.js
- Test out the plugin on desktop
- Clean up the code base to remove the browser specific code
- Set up development cycle to match janus.js

## Test & Bugs

The code is ready to use but will have some bug, please open issue when you spot any issue or bugs.

## Dependencies

- [flutter-webrtc](https://github.com/flutter-webrtc/flutter-webrtc)
