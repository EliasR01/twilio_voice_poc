import 'dart:async';
import 'dart:io';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:twilio_voice/twilio_voice.dart';
import 'package:twilio_voice_example/screens/ui_call_screen.dart';

import 'api.dart';
import 'utils.dart';

extension IterableExtension<E> on Iterable<E> {
  /// Extension on [Iterable]'s [firstWhere] that returns null if no element is found instead of throwing an exception.
  E? firstWhereOrNull(bool Function(E element) test, {E Function()? orElse}) {
    for (E element in this) {
      if (test(element)) return element;
    }
    return (orElse == null) ? null : orElse();
  }
}

enum RegistrationMethod {
  env,
  local;

  static RegistrationMethod? fromString(String? value) {
    if (value == null) return null;
    return RegistrationMethod.values
        .firstWhereOrNull((element) => element.name == value);
  }

  static RegistrationMethod? loadFromEnvironment() {
    const value = String.fromEnvironment("REGISTRATION_METHOD");
    return fromString(value);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final app = App(
      registrationMethod:
          RegistrationMethod.loadFromEnvironment() ?? RegistrationMethod.env);
  await Firebase.initializeApp();
  return runApp(MaterialApp(home: app));
}

class App extends StatefulWidget {
  final RegistrationMethod registrationMethod;

  const App({super.key, this.registrationMethod = RegistrationMethod.local});

  @override
  State<App> createState() => _AppState();
}

class _AppState extends State<App> {
  String userId = "+17069792493";

  /// Flag showing if TwilioVoice plugin has been initialised
  bool twilioInit = false;

  /// Flag showing registration status (for registering or re-registering on token change)
  var authRegistered = false;

  /// Flag showing if incoming call dialog is showing
  var showingIncomingCallDialog = false;

  //#region #region Register with Twilio
  void register() async {
    printDebug("Registering...");
    bool success = await _registerLocal();

    printDebug("Success? $success");

    if (success) {
      setState(() {
        twilioInit = true;
      });
    }
  }

  /// Registers [accessToken] with TwilioVoice plugin, acquires a device token from FirebaseMessaging and registers with TwilioVoice plugin.
  Future<bool> _registerAccessToken(String accessToken) async {
    try {
      printDebug("voip-registering access token");

      String? androidToken;
      if (Platform.isAndroid) {
        // Get device token for Android only
        androidToken = await FirebaseMessaging.instance.getToken();
        printDebug("androidToken is ${androidToken!}");
      }
      final result = await TwilioVoice.instance
          .setTokens(accessToken: accessToken, deviceToken: androidToken);

      printDebug("Result initializing access token: $result");

      await TwilioVoice.instance.registerPhoneAccount();

      return result ?? false;
    } catch (err) {
      printDebug("Got error: $err");
    }

    return false;
  }

  //#region #region Register with local provider
  /// Use this method to register with a local token generator
  /// To access this, run with `--dart-define=REGISTRATION_METHOD=local`
  Future<bool> _registerLocal() async {
    final result = await generateLocalAccessToken();
    if (result == null) {
      printDebug("Failed to register with local token generator");
      return false;
    }
    return _registerAccessToken(result);
  }

  //#endregion

  /// Use this method to register with a firebase token generator
  /// To access this, run with `--dart-define=REGISTRATION_METHOD=firebase`
  //#endregion

  //#endregion

  @override
  void initState() {
    super.initState();

    TwilioVoice.instance.setOnDeviceTokenChanged((token) {
      printDebug("voip-device token changed");
      if (!kIsWeb) {
        register();
      }
    });

    listenForEvents();
    register();

    const partnerId = "alicesId";
    TwilioVoice.instance.registerClient(partnerId, "Alice");
    // TwilioVoice.instance.requestReadPhoneStatePermission();
    // TwilioVoice.instance.requestMicAccess();
    // TwilioVoice.instance.requestCallPhonePermission();
  }

  /// Listen for call events
  void listenForEvents() {
    TwilioVoice.instance.callEventsListener.listen((event) async {
      printDebug("voip-onCallStateChanged $event");

      switch (event) {
        case CallEvent.incoming:
          // applies to web only
          if (kIsWeb || Platform.isAndroid) {
            final activeCall = TwilioVoice.instance.call.activeCall;
            if (activeCall != null &&
                activeCall.callDirection == CallDirection.incoming) {
              _showWebIncomingCallDialog();
            }
          }
          break;
        case CallEvent.ringing:
          final activeCall = TwilioVoice.instance.call.activeCall;
          if (activeCall != null) {
            final customData = activeCall.customParams;
            if (customData != null) {
              printDebug("voip-customData $customData");
            }
          }
          break;
        case CallEvent.connected:
          final id = await TwilioVoice.instance.call.getSid();

          // await streamCall(id ?? "");

          break;
        case CallEvent.callEnded:
        case CallEvent.declined:
        case CallEvent.answer:
          if (kIsWeb || Platform.isAndroid) {
            final nav = Navigator.of(context);
            if (nav.canPop() && showingIncomingCallDialog) {
              nav.pop();
              showingIncomingCallDialog = false;
            }
          }
          break;
        default:
          break;
      }
    });
  }

  /// Place a call to [clientIdentifier]
  Future<void> _onPerformCall(String clientIdentifier) async {
    if (!await (TwilioVoice.instance.hasMicAccess())) {
      printDebug("request mic access");
      TwilioVoice.instance.requestMicAccess();
      return;
    }
    printDebug("starting call to $clientIdentifier");

    TwilioVoice.instance.call.logLocalEventEntries([""]);

    final result = await TwilioVoice.instance.call.place(
        to: clientIdentifier,
        from: userId,
        extraOptions: {
          "statusCallback":
              "https://f27d-186-14-251-51.ngrok-free.app/status-callback"
        });

    printDebug("Result: $result");
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Plugin example app"),
        actions: [
          _LogoutAction(
            onSuccess: () {
              setState(() {
                twilioInit = false;
              });
            },
            onFailure: (error) {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text("Error"),
                  content: Text("Failed to unregister from calls: $error"),
                ),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: SingleChildScrollView(
                child: UICallScreen(
                  userId: userId,
                  onPerformCall: _onPerformCall,
                ),
              )),
        ),
      ),
    );
  }

  /// Show incoming call dialog for web and Android
  void _showWebIncomingCallDialog() async {
    showingIncomingCallDialog = true;
    final activeCall = TwilioVoice.instance.call.activeCall!;
    final action = await showIncomingCallScreen(context, activeCall);
    if (action == true) {
      printDebug("accepting call");
      TwilioVoice.instance.call.answer();
    } else if (action == false) {
      printDebug("rejecting call");
      TwilioVoice.instance.call.hangUp();
    } else {
      printDebug("no action");
    }
  }

  Future<bool?> showIncomingCallScreen(
      BuildContext context, ActiveCall activeCall) async {
    if (!kIsWeb && !Platform.isAndroid) {
      printDebug("showIncomingCallScreen only for web");
      return false;
    }

    // show accept/reject incoming call screen dialog
    return showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text("Incoming Call"),
          content: Text("Incoming call from ${activeCall.from}"),
          actions: [
            TextButton(
              child: const Text("Accept"),
              onPressed: () {
                Navigator.of(context).pop(true);
              },
            ),
            TextButton(
              child: const Text("Reject"),
              onPressed: () {
                Navigator.of(context).pop(false);
              },
            ),
          ],
        );
      },
    );
  }
}

class _LogoutAction extends StatelessWidget {
  final void Function()? onSuccess;
  final void Function(String error)? onFailure;

  const _LogoutAction({Key? key, this.onSuccess, this.onFailure})
      : super(key: key);

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
        onPressed: () async {
          final result = await TwilioVoice.instance.unregister();
          if (result == true) {
            onSuccess?.call();
          } else {
            onFailure?.call("Failed to unregister");
          }
        },
        label: const Text("Logout", style: TextStyle(color: Colors.white)),
        icon: const Icon(Icons.logout, color: Colors.white));
  }
}
