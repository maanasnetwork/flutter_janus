import 'dart:core';

import 'package:flutter/material.dart';

import 'src/api_test/api_test_menu.dart';
import 'src/route_item.dart';
import 'src/janus/menu.dart';

void main() => runApp(new MyApp());

class MyApp extends StatefulWidget {
  @override
  _MyAppState createState() => new _MyAppState();
}

enum DialogDemoAction {
  cancel,
  connect,
}

class _MyAppState extends State<MyApp> {
  List<RouteItem> items;
  // SharedPreferences _prefs;

  @override
  initState() {
    super.initState();
    _initItems();
  }

  _buildRow(context, item) {
    return ListBody(children: <Widget>[
      ListTile(
        title: Text(item.title),
        onTap: () => item.push(context),
        trailing: Icon(Icons.arrow_right),
      ),
      Divider()
    ]);
  }

  @override
  Widget build(BuildContext context) {
    return new MaterialApp(
      home: new Scaffold(
          appBar: new AppBar(
            title: new Text('Flutter-Janus'),
          ),
          body: new ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.all(0.0),
              itemCount: items.length,
              itemBuilder: (context, i) {
                return _buildRow(context, items[i]);
              })),
    );
  }

  _initItems() {
    items = <RouteItem>[
      RouteItem(
          title: 'API Tests',
          subtitle: 'API Tests.',
          push: (BuildContext context) {
            Navigator.push(
                context,
                new MaterialPageRoute(
                    builder: (BuildContext context) => new ApiTestMenu()));
          }),
      RouteItem(
          title: 'Janus Demos',
          subtitle: 'Janus Demos.',
          push: (BuildContext context) {
            Navigator.push(
                context,
                new MaterialPageRoute(
                    builder: (BuildContext context) => new JanusDemoMenu()));
          }),
    ];
  }
}
