import 'package:flutter/material.dart';
import 'dart:core';
import '../route_item.dart';
import 'not_ready.dart';
import 'janus_demo_echo.dart';

typedef void RouteCallback(BuildContext context);

final List<RouteItem> items = <RouteItem>[
  RouteItem(
      title: 'Echo Test',
      subtitle: 'A simple Echo Test demo, with knobs to control the bitrate.',
      push: (BuildContext context) {
        Navigator.push(
            context,
            new MaterialPageRoute(
                builder: (BuildContext context) => new JanusEcho()));
      }),
  RouteItem(
      title: 'Streaming',
      subtitle:
          'A media Streaming demo, with sample live and on-demand streams.',
      push: (BuildContext context) {
        Navigator.push(
            context,
            new MaterialPageRoute(
                builder: (BuildContext context) => new NotReady()));
      }),
  RouteItem(
      title: 'Video Call',
      subtitle:
          'A Video Call demo, a bit like AppRTC but with media passing through Janus.',
      push: (BuildContext context) {
        Navigator.push(
            context,
            new MaterialPageRoute(
                builder: (BuildContext context) => new NotReady()));
      }),
  RouteItem(
      title: 'SIP Gateway',
      subtitle:
          'A SIP Gateway demo, allowing you to register at a SIP server and start/receive calls.',
      push: (BuildContext context) {
        Navigator.push(
            context,
            new MaterialPageRoute(
                builder: (BuildContext context) => new NotReady()));
      }),
  RouteItem(
      title: 'Video Room',
      subtitle:
          'A videoconferencing demo, allowing you to join a video room with up to six users.',
      push: (BuildContext context) {
        Navigator.push(
            context,
            new MaterialPageRoute(
                builder: (BuildContext context) => new NotReady()));
      }),
  RouteItem(
      title: 'Audio Room',
      subtitle:
          'An audio mixing/bridge demo, allowing you join an Audio Room room.',
      push: (BuildContext context) {
        Navigator.push(
            context,
            new MaterialPageRoute(
                builder: (BuildContext context) => new NotReady()));
      }),
  RouteItem(
      title: 'Text Room',
      subtitle: 'A text room demo, using DataChannels only.',
      push: (BuildContext context) {
        Navigator.push(
            context,
            new MaterialPageRoute(
                builder: (BuildContext context) => new NotReady()));
      }),
  RouteItem(
      title: 'Voice Mail',
      subtitle:
          'A simple audio recorder demo, returning an .opus file after 10 seconds.',
      push: (BuildContext context) {
        Navigator.push(
            context,
            new MaterialPageRoute(
                builder: (BuildContext context) => new NotReady()));
      }),
  RouteItem(
      title: 'Recorder / Playout',
      subtitle:
          'A demo to record audio/video messages, and subsequently replay them through WebRTC.',
      push: (BuildContext context) {
        Navigator.push(
            context,
            new MaterialPageRoute(
                builder: (BuildContext context) => new NotReady()));
      }),
  RouteItem(
      title: 'Screen Sharing',
      subtitle:
          'A webinar-like screen sharing session, based on the Video Room plugin.',
      push: (BuildContext context) {
        Navigator.push(
            context,
            new MaterialPageRoute(
                builder: (BuildContext context) => new NotReady()));
      }),
];

class JanusDemoMenu extends StatefulWidget {
  static String tag = 'janus_menu';
  @override
  _JanusDemoMenuState createState() => _JanusDemoMenuState();
}

class _JanusDemoMenuState extends State<JanusDemoMenu> {
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
          title: new Text('Janus Demo'),
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
