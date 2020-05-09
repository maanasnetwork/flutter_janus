import 'package:flutter/material.dart';
import 'dart:core';

import 'package:flutterjanus/src/callbacks.dart';
import 'package:flutterjanus/src/janus.dart';

/// Janus test

class JanusTest extends StatefulWidget {
  static String tag = 'janus_test';

  @override
  _JanusTestState createState() => _JanusTestState();
}

class _JanusTestState extends State<JanusTest> {
  int _counter = 0;
  String _text;
  void _incrementCounter() {
    setState(() {
      _counter++;

      // Janus test
      Janus.init(
          options: {"debug": "vdebug"},
          callback: () => {_text = "Janus Init Callback: Janus initialised."});
      GatewayCallbacks httpCallbacks = GatewayCallbacks();
      httpCallbacks.success = (data) => {Janus.log(data)};
      Janus.httpAPICall("http://fusion.minelytics.in:8088/janus/info",
          {"verb": "get"}, httpCallbacks);
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("Janus Test"),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Text(
              '$_text',
            ),
            Text(
              '$_counter',
              style: Theme.of(context).textTheme.headline4,
            ),
          ],
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _incrementCounter,
        tooltip: 'Increment',
        child: Icon(Icons.add),
      ),
      // This trailing comma makes auto-formatting nicer for build methods.
    );
  }
}
