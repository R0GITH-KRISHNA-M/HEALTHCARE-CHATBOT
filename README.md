---

# 🩺 Healthcare Chatbot App (FLUTTER)

A smart and interactive mobile application built using **Flutter** that serves as a virtual health assistant. This chatbot helps users with medical symptom analysis, general health queries, and finding nearby hospitals — all from their mobile device.

---

## 📖 About

This **Healthcare Chatbot** aims to assist users in understanding their health conditions and locating nearby healthcare facilities. It uses AI-driven natural language processing (NLP) to understand user prompts and provide helpful suggestions, remedies, or advice. Additionally, it supports map-based hospital search and stores chat history securely.

---

## 🔧 Tech Stack

- **Frontend:** Flutter (Cross-platform mobile development)
- **Backend / Auth / DB:** Firebase
  - Firebase Authentication (User login/sign-up)
  - Cloud Firestore (Storing chat messages & user info)
- **APIs Used:**
  - **Gemini API** (Google’s LLM) – for NLP, conversation, and prompt analysis
  - **Google Maps API** – for location-based hospital search and navigation

---

## ✨ Features

- 🔐 **Secure Authentication:** Firebase-based email/password login
- 💬 **AI Chatbot:** Conversational assistant using Gemini API
- 🧠 **Symptom Analysis:** Ask health-related questions and get responses
- 🗺️ **Hospital Finder:** Search for hospitals nearby using Google Maps
- 💾 **Chat History:** All user conversations stored in Firebase

---

## 🚀 Getting Started

### Prerequisites

- Flutter SDK installed
- Firebase project set up (with Firestore and Authentication enabled)
- Gemini API access via Google Cloud
- Google Maps API key

### Clone the Repo

```bash
git clone https://github.com/your-username/healthcare-chatbot.git
cd healthcare-chatbot
````

### Run the App

```bash
flutter pub get
flutter run
```

### Firebase Configuration

1. Add your `google-services.json` (for Android) and/or `GoogleService-Info.plist` (for iOS) to the respective folders.
2. Enable Email/Password sign-in and Firestore in Firebase Console.

---







