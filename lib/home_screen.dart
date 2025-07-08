import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:intl/intl.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:permission_handler/permission_handler.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import 'auth_service.dart';
import 'sign_in_screen.dart';
import 'theme_provider.dart';
import 'package:geolocator/geolocator.dart';
import 'map_screen.dart'; // Make sure you have this file created

class ChatMessage {
  final String text;
  final DateTime timestamp;
  final bool isUserMessage;

  ChatMessage({
    required this.text,
    required this.timestamp,
    this.isUserMessage = true,
  });
}

class HomeScreen extends StatefulWidget {
  final User user;

  const HomeScreen({super.key, required this.user});

  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _chatController = TextEditingController();
  final List<ChatMessage> _messages = [];
  final ScrollController _scrollController = ScrollController();
  late stt.SpeechToText _speech;
  bool _isListening = false;
  bool _speechInitialized = false;
  bool _isApiConnected = false;
  bool _isLoadingResponse = false;
  String _apiStatusMessage = 'Connecting to Gemini API...';
  static const String _geminiApiKey = 'AIzaSyAzBmu6ofkVA49UuOmjaj_dC-va8uI1Wsw'; // Replace with your actual API key

  @override
  void initState() {
    super.initState();
    _speech = stt.SpeechToText();
    _initializeSpeech();
    _checkApiConnection();
    // Add welcome message with username only
    setState(() {
      _messages.add(ChatMessage(
        text: 'Hi ${widget.user.email?.split('@')[0] ?? 'User'}, how can I assist you today?',
        timestamp: DateTime.now(),
        isUserMessage: false,
      ));
    });
    // Auto-scroll to welcome message
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _initializeSpeech() async {
    print('Initializing speech recognition...');
    PermissionStatus status = await Permission.microphone.status;
    if (!status.isGranted) {
      status = await Permission.microphone.request();
      if (!status.isGranted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Microphone permission denied")),
        );
        return;
      }
    }

    bool available = await _speech.initialize(
      onStatus: (val) {
        print('Speech status: $val');
        if (val == 'done' || val == 'notListening') {
          setState(() => _isListening = false);
        }
      },
      onError: (val) {
        print('Speech error: $val');
        setState(() => _isListening = false);
      },
    );
    if (available) {
      setState(() => _speechInitialized = true);
      print('Speech initialized successfully');
    } else {
      print('Speech initialization failed');
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Speech recognition not available")),
      );
    }
  }

  Future<void> _checkApiConnection() async {
    try {
      const apiUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$_geminiApiKey';

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": "Hello"}
              ]
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        setState(() {
          _isApiConnected = true;
          _apiStatusMessage = 'Gemini API connected';
        });
      } else {
        setState(() {
          _isApiConnected = false;
          _apiStatusMessage = 'API connection failed: ${response.statusCode}';
        });
      }
    } catch (e) {
      setState(() {
        _isApiConnected = false;
        _apiStatusMessage = 'API connection error: ${e.toString()}';
      });
    }
  }

  Future<void> _sendToGemini(String message) async {
    if (!_isApiConnected) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("API not connected")),
      );
      return;
    }

    setState(() {
      _isLoadingResponse = true;
    });

    try {
      const apiUrl = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$_geminiApiKey';

      final response = await http.post(
        Uri.parse(apiUrl),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "contents": [
            {
              "parts": [
                {"text": message}
              ]
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final responseData = jsonDecode(response.body);
        final geminiResponse = responseData['candidates'][0]['content']['parts'][0]['text'];

        setState(() {
          _messages.add(ChatMessage(
            text: geminiResponse,
            timestamp: DateTime.now(),
            isUserMessage: false,
          ));
        });

        // Save the chat to Firestore
        await AuthService().saveChatMessage(
          userId: widget.user.uid,
          message: message,
          response: geminiResponse,
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("API error: ${response.statusCode}")),
        );
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: ${e.toString()}")),
      );
    } finally {
      setState(() {
        _isLoadingResponse = false;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  void _sendMessage() {
    String message = _chatController.text.trim();
    if (message.isNotEmpty) {
      setState(() {
        _messages.add(ChatMessage(
          text: message,
          timestamp: DateTime.now(),
        ));
      });
      _chatController.clear();
      _sendToGemini(message);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      });
    }
  }

  Future<void> _startListening() async {
    print('Mic button clicked - Starting listening');
    if (!_speechInitialized) {
      await _initializeSpeech();
      if (!_speechInitialized) {
        print('Speech not initialized, aborting');
        return;
      }
    }

    if (!_isListening) {
      bool available = await _speech.initialize(
        onStatus: (val) {
          print('Speech status: $val');
          if (val == 'done' || val == 'notListening') {
            setState(() => _isListening = false);
          }
        },
        onError: (val) {
          print('Speech error: $val');
          setState(() => _isListening = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Speech error: $val")),
          );
        },
      );
      if (available) {
        setState(() => _isListening = true);
        print('Listening started');
        _speech.listen(
          onResult: (val) {
            print('Result received - Words: "${val.recognizedWords}", Final: ${val.finalResult}');
            setState(() {
              _chatController.text = val.recognizedWords;
              if (val.recognizedWords.isEmpty) {
                print('No words recognized yet');
              }
              if (val.finalResult) {
                print('Final result: "${val.recognizedWords}"');
                _isListening = false;
                _speech.stop();
                if (val.recognizedWords.isNotEmpty) {
                  _sendMessage();
                } else {
                  print('No final words to send');
                }
              }
            });
          },
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 5),
          localeId: "en_US",
          partialResults: true,
        );
      } else {
        setState(() => _isListening = false);
        print('Failed to start listening');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Failed to start speech recognition")),
        );
      }
    } else {
      _stopListening();
    }
  }

  void _stopListening() {
    setState(() => _isListening = false);
    _speech.stop();
    print('Listening stopped');
  }

  Future<void> _signOut() async {
    try {
      await AuthService().signOut();
      if (mounted) {
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => SignInScreen()),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Sign out failed: ${e.toString()}"),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  @override
  void dispose() {
    _chatController.dispose();
    _scrollController.dispose();
    _speech.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final isDarkMode = themeProvider.themeMode == ThemeMode.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Chat'),
        elevation: 2,
        backgroundColor: isDarkMode ? Colors.black : Colors.white,
        actions: [
          IconButton(
            icon: Icon(Icons.brightness_6,
                color: isDarkMode ? Colors.white : Colors.black),
            onPressed: () {
              themeProvider.toggleTheme(!isDarkMode);
            },
          ),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'signout') {
                await _signOut();
              }
            },
            itemBuilder: (BuildContext context) => [
              PopupMenuItem(
                enabled: false,
                child: Row(
                  children: [
                    if (widget.user.photoURL != null)
                      CircleAvatar(
                        backgroundImage: NetworkImage(widget.user.photoURL!),
                        radius: 15,
                      )
                    else
                      CircleAvatar(
                        radius: 15,
                        child: Text(
                          widget.user.displayName?.substring(0, 1).toUpperCase() ?? "U",
                          style: TextStyle(
                              color: isDarkMode ? Colors.white : Colors.black),
                        ),
                      ),
                    const SizedBox(width: 10),
                    Text(
                      widget.user.displayName ?? widget.user.email ?? "User",
                      style: TextStyle(
                          color: isDarkMode ? Colors.white : Colors.black),
                    ),
                  ],
                ),
              ),
              const PopupMenuDivider(),
              PopupMenuItem<String>(
                value: 'signout',
                child: Row(
                  children: [
                    Icon(Icons.exit_to_app,
                        color: isDarkMode ? Colors.white : Colors.black),
                    const SizedBox(width: 10),
                    Text('Sign Out',
                        style: TextStyle(
                            color: isDarkMode ? Colors.white : Colors.black)),
                  ],
                ),
              ),
            ],
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0),
              child: Row(
                children: [
                  if (widget.user.photoURL != null)
                    CircleAvatar(
                      backgroundImage: NetworkImage(widget.user.photoURL!),
                      radius: 15,
                    )
                  else
                    CircleAvatar(
                      radius: 15,
                      backgroundColor: isDarkMode ? Colors.grey[800] : Colors.grey[200],
                      child: Text(
                        widget.user.displayName?.substring(0, 1).toUpperCase() ?? "U",
                        style: TextStyle(
                            color: isDarkMode ? Colors.white : Colors.black),
                      ),
                    ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                image: DecorationImage(
                  image: AssetImage('assets/background.png'),
                  fit: BoxFit.cover,
                ),
              ),
            ),
          ),
          Positioned.fill(
            child: Container(
              color: Colors.black.withOpacity(0.3),
            ),
          ),
          Column(
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 300),
                height: _apiStatusMessage.isNotEmpty ? 40 : 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: _isApiConnected ? Colors.green : Colors.orange,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _apiStatusMessage,
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: _scrollController,
                  padding: const EdgeInsets.all(16.0),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8.0),
                      child: Align(
                        alignment: message.isUserMessage
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Column(
                          crossAxisAlignment: message.isUserMessage
                              ? CrossAxisAlignment.end
                              : CrossAxisAlignment.start,
                          children: [
                            Container(
                              constraints: BoxConstraints(
                                maxWidth: MediaQuery.of(context).size.width * 0.7,
                              ),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16.0,
                                vertical: 10.0,
                              ),
                              decoration: BoxDecoration(
                                color: message.isUserMessage
                                    ? (isDarkMode ? Colors.blue[800] : Colors.blue[200])
                                    : (isDarkMode ? Colors.grey[800] : Colors.white),
                                borderRadius: message.isUserMessage
                                    ? const BorderRadius.only(
                                  topLeft: Radius.circular(16.0),
                                  topRight: Radius.circular(16.0),
                                  bottomLeft: Radius.circular(16.0),
                                  bottomRight: Radius.circular(0.0),
                                )
                                    : const BorderRadius.only(
                                  topLeft: Radius.circular(16.0),
                                  topRight: Radius.circular(16.0),
                                  bottomLeft: Radius.circular(0.0),
                                  bottomRight: Radius.circular(16.0),
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: Colors.black.withOpacity(0.1),
                                    spreadRadius: 1,
                                    blurRadius: 4,
                                    offset: const Offset(0, 2),
                                  ),
                                ],
                              ),
                              child: Text(
                                message.text,
                                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                                  color: isDarkMode ? Colors.white : Colors.black,
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              DateFormat('hh:mm a').format(message.timestamp),
                              style: TextStyle(
                                fontSize: 12,
                                color: isDarkMode ? Colors.grey[300] : Colors.grey[600],
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              if (_isLoadingResponse)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 8.0),
                  child: CircularProgressIndicator(),
                ),
              Container(
                padding: const EdgeInsets.all(16.0),
                decoration: BoxDecoration(
                  color: isDarkMode ? Colors.black.withOpacity(0.7) : Colors.white.withOpacity(0.85),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.1),
                      spreadRadius: 1,
                      blurRadius: 5,
                      offset: const Offset(0, -2),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _chatController,
                        decoration: InputDecoration(
                          hintText: 'Ask me anything...',
                          hintStyle: TextStyle(
                            color: isDarkMode ? Colors.grey[400] : Colors.grey,
                            fontStyle: FontStyle.italic,
                          ),
                          filled: true,
                          fillColor: isDarkMode ? Colors.grey[800] : Colors.grey[200],
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 20.0,
                            vertical: 12.0,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(25.0),
                            borderSide: BorderSide.none,
                          ),
                        ),
                        style: TextStyle(color: isDarkMode ? Colors.white : Colors.black),
                        onSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: 10),
                    IconButton(
                      icon: Image.asset(
                        'assets/hospital_logo.png',
                        width: 24,
                        height: 24,
                      ),
                      onPressed: () async {
                        bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
                        if (!serviceEnabled) {
                          bool? shouldEnable = await showDialog<bool>(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Enable Location'),
                              content: const Text(
                                  'To find nearby hospitals, please enable location services.'),
                              actions: [
                                TextButton(
                                  child: const Text('Cancel'),
                                  onPressed: () => Navigator.of(context).pop(false),
                                ),
                                TextButton(
                                  child: const Text('Enable'),
                                  onPressed: () => Navigator.of(context).pop(true),
                                ),
                              ],
                            ),
                          );

                          if (shouldEnable == true) {
                            await Geolocator.openLocationSettings();
                            serviceEnabled = await Geolocator.isLocationServiceEnabled();
                            if (!serviceEnabled) return;
                          } else {
                            return;
                          }
                        }

                        LocationPermission permission = await Geolocator.checkPermission();
                        if (permission == LocationPermission.denied) {
                          permission = await Geolocator.requestPermission();
                          if (permission == LocationPermission.denied) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Location permissions are required')),
                            );
                            return;
                          }
                        }

                        if (permission == LocationPermission.deniedForever) {
                          await showDialog(
                            context: context,
                            builder: (context) => AlertDialog(
                              title: const Text('Permission Required'),
                              content: const Text(
                                  'Please enable location permissions in app settings.'),
                              actions: [
                                TextButton(
                                  child: const Text('Cancel'),
                                  onPressed: () => Navigator.of(context).pop(),
                                ),
                                TextButton(
                                  child: const Text('Open Settings'),
                                  onPressed: () {
                                    Navigator.of(context).pop();
                                    Geolocator.openAppSettings();
                                  },
                                ),
                              ],
                            ),
                          );
                          return;
                        }

                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => MapScreen(user: widget.user),
                          ),
                        );
                      },
                    ),
                    IconButton(
                      icon: Icon(
                        _isListening ? Icons.mic : Icons.mic_none,
                        color: _isListening ? Colors.red : (isDarkMode ? Colors.white : Colors.black),
                      ),
                      onPressed: _isListening ? _stopListening : _startListening,
                    ),
                    const SizedBox(width: 10),
                    FloatingActionButton(
                      mini: true,
                      onPressed: _sendMessage,
                      elevation: 2,
                      backgroundColor: Colors.blue,
                      child: const Icon(Icons.send, size: 20, color: Colors.white),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}