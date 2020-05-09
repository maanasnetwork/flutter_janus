import 'package:flutter/material.dart';
import 'dart:core';

class NotReady extends StatelessWidget {
  const NotReady({Key key}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: new AppBar(
        title: new Text('Janus Demo : Not Ready'),
      ),
      body: Container(
        child: Align(
            child: Text(
          "Not Ready : Not Implemeneted",
          style: TextStyle(fontSize: 24),
        )),
      ),
    );
  }
}
