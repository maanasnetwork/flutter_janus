import 'package:flutter/material.dart';
import 'my_text_form_field.dart';
import '../utils/shared_preferences.dart';

class JanusSettingsForm extends StatefulWidget {
  @override
  _JanusSettingsFormState createState() => _JanusSettingsFormState();
}

class _JanusSettingsFormState extends State<JanusSettingsForm> {
  final _formKey = GlobalKey<FormState>();
  String janusServer;
  String apiKey;

  @override
  initState() {
    super.initState();
    // initSettings();
  }

  initSettings() async {
    janusServer = await JanusSharedPreferences.getJanusServer();
    apiKey = await JanusSharedPreferences.getApiKey();
  }

  @override
  Widget build(BuildContext context) {
    final halfMediaWidth = MediaQuery.of(context).size.width / 2.0;

    return new Scaffold(
        appBar: new AppBar(
          title: new Text("Janus Settings"),
        ),
        body: Form(
          key: _formKey,
          child: Column(
            children: <Widget>[
              MyTextFormField(
                hintText: 'Janus Server',
                validator: (String value) {
                  if (value.isEmpty) {
                    return 'Enter Janus Server';
                  }
                  return null;
                },
                onSaved: (String value) async {
                  await JanusSharedPreferences.setJanusServer(value);
                },
                initialValue: janusServer,
              ),
              MyTextFormField(
                hintText: 'Api Key',
                validator: (String value) {
                  if (value.isEmpty) {
                    return null;
                  }
                  return null;
                },
                onSaved: (String value) async {
                  await JanusSharedPreferences.setApiKey(value);
                },
                initialValue: apiKey,
              ),
              RaisedButton(
                color: Colors.blueAccent,
                onPressed: () {
                  if (_formKey.currentState.validate()) {
                    _formKey.currentState.save();
                    Navigator.of(context).pop();
                  }
                },
                child: Text(
                  'Save',
                  style: TextStyle(
                    color: Colors.white,
                  ),
                ),
              )
            ],
          ),
        ));
  }
}
