import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

class ProfileScreen extends StatelessWidget {
  final User user;

  ProfileScreen({required this.user});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text('Profile'),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (user.photoURL != null)
              CircleAvatar(
                backgroundImage: NetworkImage(user.photoURL!),
                radius: 50,
              ),
            SizedBox(height: 20),
            Text('Name: ${user.displayName ?? "Not provided"}'),
            SizedBox(height: 10),
            Text('Email: ${user.email ?? "Not provided"}'),
            SizedBox(height: 20),
            ElevatedButton(
              onPressed: () {
                // Add functionality to update profile
                print("Update profile");
              },
              child: Text('Update Profile'),
            ),
          ],
        ),
      ),
    );
  }
}