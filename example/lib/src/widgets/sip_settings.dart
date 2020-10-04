import 'dart:convert';
import 'package:flutter/material.dart';
import 'my_text_form_field.dart';
import '../utils/shared_preferences.dart';

class SipSettingsForm extends StatefulWidget {
  @override
  _SipSettingsFormState createState() => _SipSettingsFormState();
}

class _SipSettingsFormState extends State<SipSettingsForm> {
  final _formKey = GlobalKey<FormState>();
  Map<String, dynamic> sipSettings = {};

  @override
  initState() {
    super.initState();
    // initSettings();
  }

  initSettings() async {
    String _settings = await JanusSharedPreferences.getSipSettings();
    sipSettings = jsonDecode(_settings);
  }

  @override
  Widget build(BuildContext context) {
    final halfMediaWidth = MediaQuery.of(context).size.width / 2.0;

    return new Scaffold(
        appBar: new AppBar(
          title: new Text("Sip Settings"),
        ),
        body: Form(
          key: _formKey,
          child: Column(
            children: <Widget>[
              MyTextFormField(
                hintText: 'Sip Server',
                validator: (String value) {
                  if (value.isEmpty) {
                    return 'Enter Sip Server';
                  }
                  return null;
                },
                onSaved: (String value) {
                  sipSettings['sip_server'] = value;
                },
                initialValue: sipSettings['sip_server'],
              ),
              MyTextFormField(
                hintText: 'Sip Username',
                validator: (String value) {
                  if (value.isEmpty) {
                    return 'Enter Sip Username';
                  }
                  return null;
                },
                onSaved: (String value) {
                  sipSettings['sip_username'] = value;
                },
                initialValue: sipSettings['sip_username'],
              ),
              MyTextFormField(
                hintText: 'Sip Password',
                validator: (String value) {
                  if (value.isEmpty) {
                    return 'Enter Sip Password';
                  }
                  return null;
                },
                onSaved: (String value) {
                  sipSettings['sip_password'] = value;
                },
                initialValue: sipSettings['sip_password'],
              ),
              MyTextFormField(
                hintText: 'Display Name',
                validator: (String value) {
                  if (value.isEmpty) {
                    return 'Enter Display Name';
                  }
                  return null;
                },
                onSaved: (String value) {
                  sipSettings['display_name'] = value;
                },
                initialValue: sipSettings['display_name'],
              ),
              RaisedButton(
                color: Colors.blueAccent,
                onPressed: () async {
                  if (_formKey.currentState.validate()) {
                    _formKey.currentState.save();
                    await JanusSharedPreferences.setSipSettings(
                        jsonEncode(sipSettings));
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
