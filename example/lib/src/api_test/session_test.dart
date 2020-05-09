import 'package:flutter/material.dart';
import 'dart:core';

import 'package:flutterjanus/src/callbacks.dart';
import 'package:flutterjanus/src/janus.dart';
import 'package:flutterjanus/src/session.dart';

/// Janus test

class JanusSessionTest extends StatefulWidget {
  static String tag = 'janus_session_test';

  @override
  _JanusSessionTestState createState() => _JanusSessionTestState();
}

class _JanusSessionTestState extends State<JanusSessionTest> {
  int _counter = 0;
  String _text;
  void _incrementCounter() {
    setState(() {
      _counter++;

      // Janus test
      Janus.init(
          options: {"debug": "vdebug"},
          callback: () => {_text = "Janus Init Callback: Janus initialised."});
      GatewayCallbacks gatewayCallbacks = GatewayCallbacks();
      gatewayCallbacks.server = "http://fusion.minelytics.in:8088/janus";
      Session session = Session(gatewayCallbacks);
      Janus.log(session);
      // Janus.log(Callbacks.error.runtimeType);
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
