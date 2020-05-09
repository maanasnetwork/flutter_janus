import 'package:flutter/material.dart';
import 'dart:core';

import 'loopback_sample.dart';
import 'get_user_media_sample.dart';
import 'data_channel_sample.dart';

import 'janus_test.dart';
import 'session_test.dart';
import '../route_item.dart';

typedef void RouteCallback(BuildContext context);

final List<RouteItem> items = <RouteItem>[
  RouteItem(
      title: 'GetUserMedia Test',
      subtitle: 'getUserMediaTest',
      push: (BuildContext context) {
        Navigator.push(
            context,
            new MaterialPageRoute(
                builder: (BuildContext context) => new GetUserMediaSample()));
      }),
  RouteItem(
      title: 'LoopBack Sample',
      subtitle: 'loopBackSample',
      push: (BuildContext context) {
        Navigator.push(
            context,
            new MaterialPageRoute(
                builder: (BuildContext context) => new LoopBackSample()));
      }),
  RouteItem(
      title: 'DataChannel Test',
      subtitle: 'dataChannelTest',
      push: (BuildContext context) {
        Navigator.push(
            context,
            new MaterialPageRoute(
                builder: (BuildContext context) => new DataChannelSample()));
      }),
  RouteItem(
      title: 'Janus Test',
      subtitle: 'janusTest',
      push: (BuildContext context) {
        Navigator.push(
            context,
            new MaterialPageRoute(
                builder: (BuildContext context) => new JanusTest()));
      }),
  RouteItem(
      title: 'Janus Session Test',
      subtitle: 'janusSessionTest',
      push: (BuildContext context) {
        Navigator.push(
            context,
            new MaterialPageRoute(
                builder: (BuildContext context) => new JanusSessionTest()));
      }),
  RouteItem(
      title: 'Janus Plugin Test',
      subtitle: 'janusPluginTest',
      push: (BuildContext context) {
        Navigator.push(
            context,
            new MaterialPageRoute(
                builder: (BuildContext context) => new JanusSessionTest()));
      }),
];

class ApiTestMenu extends StatefulWidget {
  static String tag = 'api_test';
  @override
  _ApiTestMenuState createState() => new _ApiTestMenuState();
}

class _ApiTestMenuState extends State<ApiTestMenu> {
  // GlobalKey<FormState> _formKey = new GlobalKey<FormState>();
  @override
  initState() {
    super.initState();
  }

  @override
  deactivate() {
    super.deactivate();
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
    return new Scaffold(
        appBar: new AppBar(
          title: new Text('API Tests'),
        ),
        body: new ListView.builder(
            shrinkWrap: true,
            padding: const EdgeInsets.all(0.0),
            itemCount: items.length,
            itemBuilder: (context, i) {
              return _buildRow(context, items[i]);
            }));
  }
}
