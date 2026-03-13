import 'package:flutter/material.dart';

class FormCard extends StatelessWidget {
  double _scaleWidth(BuildContext context, double value) {
    return MediaQuery.of(context).size.width * (value / 750);
  }

  double _scaleHeight(BuildContext context, double value) {
    return MediaQuery.of(context).size.height * (value / 1334);
  }

  double _scaleText(BuildContext context, double value) {
    return _scaleWidth(context, value).clamp(12.0, 42.0);
  }

  @override
  Widget build(BuildContext context) {
    return new Container(
      width: double.infinity,
      height: _scaleHeight(context, 500),
      decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8.0),
          boxShadow: [
            BoxShadow(
                color: Colors.black12,
                offset: Offset(0.0, 15.0),
                blurRadius: 15.0),
            BoxShadow(
                color: Colors.black12,
                offset: Offset(0.0, -10.0),
                blurRadius: 10.0),
          ]),
      child: Padding(
        padding: EdgeInsets.only(left: 16.0, right: 16.0, top: 16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text("Login",
                style: TextStyle(
                    fontSize: _scaleText(context, 45),
                    fontFamily: "Poppins-Bold",
                    letterSpacing: .6)),
            SizedBox(
              height: _scaleHeight(context, 30),
            ),
            Text("Username",
                style: TextStyle(
                    fontFamily: "Poppins-Medium",
                    fontSize: _scaleText(context, 26))),
            TextField(
              decoration: InputDecoration(
                  hintText: "username",
                  hintStyle: TextStyle(color: Colors.grey, fontSize: 12.0)),
            ),
            SizedBox(
              height: _scaleHeight(context, 30),
            ),
            Text("Password",
                style: TextStyle(
                    fontFamily: "Poppins-Medium",
                    fontSize: _scaleText(context, 26))),
            TextField(
              obscureText: true,
              decoration: InputDecoration(
                  hintText: "Password",
                  hintStyle: TextStyle(color: Colors.grey, fontSize: 12.0)),
            ),
            SizedBox(
              height: _scaleHeight(context, 35),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: <Widget>[
                Text(
                  "Forgot Password?",
                  style: TextStyle(
                      color: Colors.blue,
                      fontFamily: "Poppins-Medium",
                      fontSize: _scaleText(context, 28)),
                )
              ],
            )
          ],
        ),
      ),
    );
  }
}
