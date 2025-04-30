import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../pdfViewer.dart';
import 'package:webview_flutter/webview_flutter.dart';
import '../api_service.dart';
import 'api_serviceJP.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:fluttertoast/fluttertoast.dart';
import '../auto_update.dart';
import 'package:http/http.dart' as http;
import 'dart:io';
import 'package:unique_identifier/unique_identifier.dart';

class SoftwareWebViewScreenJP extends StatefulWidget {
  final int linkID;

  SoftwareWebViewScreenJP({required this.linkID});

  @override
  _SoftwareWebViewScreenState createState() => _SoftwareWebViewScreenState();
}

class _SoftwareWebViewScreenState extends State<SoftwareWebViewScreenJP> with WidgetsBindingObserver {
  late final WebViewController _controller;
  final ApiService apiService = ApiService();
  final ApiServiceJP apiServiceJP = ApiServiceJP();
  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();
  String? _webUrl;
  String? _profilePictureUrl;
  String? _firstName;
  String? _surName;
  String? _idNumber;
  bool _isLoading = true;
  int? _currentLanguageFlag;
  double _progress = 0;
  String? _phOrJp;
  bool _isPhCountryPressed = false;
  bool _isJpCountryPressed = false;
  bool _isCountryDialogShowing = false;
  bool _isCountryLoadingPh = false;
  bool _isCountryLoadingJp = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    _initializeWebViewController();
    _fetchAndLoadUrl();
    _loadCurrentLanguageFlag();
    _loadPhOrJp();
    _fetchDeviceInfo();

    _checkForUpdates();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      // Only check for updates if we're not already in the middle of an update
      if (!AutoUpdate.isUpdating) {
        _checkForUpdates();
      }
    }
  }

  void _initializeWebViewController() {
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageStarted: (String url) {
            setState(() {
              _isLoading = true;
              _progress = 0;
            });
          },
          onProgress: (int progress) {
            setState(() {
              _progress = progress / 100;
            });
          },
          onPageFinished: (String url) {
            setState(() {
              _isLoading = false;
              _progress = 1;
            });
          },
        ),
      );
  }

  Future<void> _checkForUpdates() async {
    try {
      await AutoUpdate.checkForUpdate(context);
    } catch (e) {
      // Handle error if update check fails
      debugPrint('Update check failed: $e');
    }
  }
  Future<void> _fetchDeviceInfo() async {
    try {
      String? deviceId = await UniqueIdentifier.serial;
      if (deviceId == null) {
        throw Exception(
          _currentLanguageFlag == 2
              ? "デバイスIDを取得できません"
              : "Unable to get device ID",
        );
      }
      final deviceResponse = await apiServiceJP.checkDeviceId(deviceId);
      if (deviceResponse['success'] == true && deviceResponse['idNumber'] != null) {
        // Store the IDNumber in SharedPreferences
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('IDNumberJP', deviceResponse['idNumber']);

        setState(() {
          _idNumber = deviceResponse['idNumber'];
        });
        await _fetchProfile(_idNumber!);
      }
    } catch (e) {
      print("Error fetching device info: $e");
    }
  }
  Future<void> _fetchAndLoadUrl() async {
    try {
      String url = await apiServiceJP.fetchSoftwareLink(widget.linkID);
      if (mounted) {
        setState(() {
          _webUrl = url;
        });
        _controller.loadRequest(Uri.parse(url));
      }
    } catch (e) {
      debugPrint("Error fetching link: $e");
      // If fetching fails, try to load the last known URL
      if (_webUrl != null) {
        _controller.loadRequest(Uri.parse(_webUrl!));
      }
    }
  }

  Future<void> _loadPhOrJp() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _phOrJp = prefs.getString('phorjp');
    });
  }

  Future<void> _fetchProfile(String idNumber) async {
    try {
      final profileData = await apiServiceJP.fetchProfile(idNumber);
      if (profileData["success"] == true) {
        String profilePictureFileName = profileData["picture"];

        String primaryUrl = "${ApiServiceJP.apiUrls[0]}V4/11-A%20Employee%20List%20V2/profilepictures/$profilePictureFileName";
        bool isPrimaryUrlValid = await _isImageAvailable(primaryUrl);

        String fallbackUrl = "${ApiServiceJP.apiUrls[1]}V4/11-A%20Employee%20List%20V2/profilepictures/$profilePictureFileName";
        bool isFallbackUrlValid = await _isImageAvailable(fallbackUrl);
        final prefs = await SharedPreferences.getInstance();
        await prefs.setInt('languageFlagJP', profileData["languageFlag"]);
        setState(() {
          _firstName = profileData["firstName"];
          _surName = profileData["surName"];
          _profilePictureUrl = isPrimaryUrlValid ? primaryUrl : isFallbackUrlValid ? fallbackUrl : null;
          _currentLanguageFlag = profileData["languageFlag"] ?? _currentLanguageFlag ?? 2;
        });
      }
    } catch (e) {
      print("Error fetching profile: $e");
    }
  }

  Future<bool> _isImageAvailable(String url) async {
    try {
      final response = await http.head(Uri.parse(url)).timeout(Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }


  Future<void> _loadCurrentLanguageFlag() async {
    SharedPreferences prefs = await SharedPreferences.getInstance();
    setState(() {
      _currentLanguageFlag = prefs.getInt('languageFlagJP');
    });
  }

  Future<void> _updateLanguageFlag(int flag) async {
    if (_idNumber != null) {
      setState(() {
        _currentLanguageFlag = flag;
      });
      try {
        await apiServiceJP.updateLanguageFlag(_idNumber!, flag);
        SharedPreferences prefs = await SharedPreferences.getInstance();
        await prefs.setInt('languageFlagJP', flag);

        String? currentUrl = await _controller.currentUrl();
        if (currentUrl != null) {
          _controller.loadRequest(Uri.parse(currentUrl));
        } else {
          _controller.reload();
        }
      } catch (e) {
        print("Error updating language flag: $e");
      }
    }
  }

  Future<void> _updatePhOrJp(String value) async {
    if ((value == 'ph' && _isCountryLoadingPh) || (value == 'jp' && _isCountryLoadingJp)) {
      return;
    }

    setState(() {
      if (value == 'ph') {
        _isCountryLoadingPh = true;
        _isPhCountryPressed = true;
      } else {
        _isCountryLoadingJp = true;
        _isJpCountryPressed = true;
      }
    });

    await Future.delayed(Duration(milliseconds: 100));

    try {
      String? deviceId = await UniqueIdentifier.serial;
      if (deviceId == null) {
        _showCountryLoginDialog(context, value);
        return;
      }

      // Get the appropriate service based on the selected country
      dynamic service = value == "jp" ? apiServiceJP : apiService;

      // Check device ID for the selected country
      final deviceResponse = await service.checkDeviceId(deviceId);

      if (deviceResponse['success'] != true || deviceResponse['idNumber'] == null) {
        _showCountryLoginDialog(context, value);
        return;
      }

      // If registered, proceed with the update
      SharedPreferences prefs = await SharedPreferences.getInstance();
      await prefs.setString('phorjp', value);
      setState(() {
        _phOrJp = value;
      });

      if (value == "ph") {
        Navigator.pushReplacementNamed(context, '/webView');
      } else if (value == "jp") {
        Navigator.pushReplacementNamed(context, '/webViewJP');
      }
    } catch (e) {
      print("Error updating country preference: $e");
      Fluttertoast.showToast(
        msg: _currentLanguageFlag == 2
            ? "デバイス登録の確認中にエラーが発生しました: ${e.toString()}"
            : "Error checking device registration: ${e.toString()}",
        toastLength: Toast.LENGTH_LONG,
        gravity: ToastGravity.BOTTOM,
      );
    } finally {
      setState(() {
        if (value == 'ph') {
          _isCountryLoadingPh = false;
          _isPhCountryPressed = false;
        } else {
          _isCountryLoadingJp = false;
          _isJpCountryPressed = false;
        }
      });
    }
  }

  void _showCountryLoginDialog(BuildContext context, String country) {
    if (_isCountryDialogShowing) return;

    _isCountryDialogShowing = true;

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          title: Row(
            children: [
              Image.asset(
                country == 'ph' ?  'assets/images/philippines.png' :  'assets/images/japan.png',
                width: 26,
                height: 26,
              ),
              SizedBox(width: 8),
              Text(
                _currentLanguageFlag == 2 ? "ログインが必要です" : "Login Required",
                overflow: TextOverflow.ellipsis,
                softWrap: false,
                style: TextStyle(fontSize: 20),
              ),
            ],
          ),
          content: Text(
            country == 'ph'
                ? (_currentLanguageFlag == 2
                ? "まずARK LOG PHアプリにログインしてください"
                : "Please login to ARK LOG PH App first")
                : (_currentLanguageFlag == 2
                ? "まずARK LOG JPアプリにログインしてください"
                : "Please login to ARK LOG JP App first"),
          ),
          actions: [
            TextButton(
              child: Text("OK"),
              onPressed: () {
                Navigator.of(context).pop();
                _isCountryDialogShowing = false;
              },
            ),
          ],
        );
      },
    ).then((_) {
      _isCountryDialogShowing = false;
    });
  }
  Future<bool> _onWillPop() async {
    if (await _controller.canGoBack()) {
      _controller.goBack();
      return false;
    } else {
      return true;
    }
  }
  Future<void> _showInputMethodPicker() async {
    try {
      if (Platform.isAndroid) {
        const MethodChannel channel = MethodChannel('input_method_channel');
        await channel.invokeMethod('showInputMethodPicker');
      } else {
        Fluttertoast.showToast(
          msg: "Keyboard selection is only available on Android",
          toastLength: Toast.LENGTH_SHORT,
          gravity: ToastGravity.BOTTOM,
        );
      }
    } catch (e) {
      debugPrint("Error showing input method picker: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        key: _scaffoldKey,
        resizeToAvoidBottomInset: false,
        appBar: PreferredSize(
          preferredSize: Size.fromHeight(kToolbarHeight - 20),
          child: SafeArea(
            child: AppBar(
              backgroundColor: Color(0xFF3452B4),
              centerTitle: true,
              toolbarHeight: kToolbarHeight - 20,
              leading: IconButton(
                padding: EdgeInsets.zero,
                iconSize: 30,
                icon: Icon(
                  Icons.settings,
                  color: Colors.white,
                ),
                onPressed: () {
                  _scaffoldKey.currentState?.openDrawer();
                },
              ),
              title: _idNumber != null
                  ? Text(
                "ID: $_idNumber",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                  letterSpacing: 0.5,
                  shadows: [
                    Shadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 2,
                      offset: Offset(1, 1),
                    ),
                  ],
                ),
              )
                  : null,
              actions: [
                IconButton(
                  padding: EdgeInsets.zero,
                  iconSize: 25,
                  icon: Container(
                    width: 25,
                    height: 25,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.red,
                    ),
                    child: Icon(
                      Icons.close,
                      color: Colors.white,
                      size: 25,
                    ),
                  ),
                  onPressed: () {
                    if (Platform.isIOS) {
                      exit(0);
                    } else {
                      SystemNavigator.pop();
                    }
                  },
                ),
              ],
            ),
          ),
        ),
        drawer: SizedBox(
          width: MediaQuery.of(context).size.width * 0.70,
          child: Drawer(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.zero,
            ),
            child: SafeArea(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Container(
                            width: double.infinity,
                            color: Color(0xFF2053B3),
                            padding: EdgeInsets.only(top: 50, bottom: 20),
                            child: Column(
                              children: [
                                Align(
                                  alignment: Alignment.center,
                                  child: CircleAvatar(
                                    radius: 50,
                                    backgroundColor: Colors.white,
                                    backgroundImage: _profilePictureUrl != null
                                        ? NetworkImage(_profilePictureUrl!)
                                        : null,
                                    child: _profilePictureUrl == null
                                        ? FlutterLogo(size: 60)
                                        : null,
                                  ),
                                ),
                                SizedBox(height: 10),
                                Text(
                                  _firstName != null && _surName != null
                                      ? "$_firstName $_surName"
                                      : _currentLanguageFlag == 2
                                      ? "ユーザー名"
                                      : "User Name",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    overflow: TextOverflow.ellipsis,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(height: 5),
                                if (_idNumber != null)
                                  Text(
                                    "ID: $_idNumber",
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w500,  // Medium weight
                                      letterSpacing: 0.5,          // Slightly spaced out letters
                                      shadows: [
                                        Shadow(
                                          color: Colors.black.withOpacity(0.2),
                                          blurRadius: 2,
                                          offset: Offset(1, 1),
                                        ),
                                      ],
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          SizedBox(height: 10),
                          Padding(
                            padding: EdgeInsets.symmetric(
                              horizontal: _currentLanguageFlag == 2 ? 35.0 : 16.0,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  _currentLanguageFlag == 2
                                      ? '言語'
                                      : 'Language',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(width: 25),
                                GestureDetector(
                                  onTap: () => _updateLanguageFlag(1),
                                  child: Column(
                                    children: [
                                      Image.asset(
                                        'assets/images/americanFlag.gif',
                                        width: 40,
                                        height: 40,
                                      ),
                                      if (_currentLanguageFlag == 1)
                                        Container(
                                          height: 2,
                                          width: 40,
                                          color: Colors.blue,
                                        ),
                                    ],
                                  ),
                                ),
                                SizedBox(width: 30),
                                GestureDetector(
                                  onTap: () => _updateLanguageFlag(2),
                                  child: Column(
                                    children: [
                                      Image.asset(
                                        'assets/images/japaneseFlag.gif',
                                        width: 40,
                                        height: 40,
                                      ),
                                      if (_currentLanguageFlag == 2)
                                        Container(
                                          height: 2,
                                          width: 40,
                                          color: Colors.blue,
                                        ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 20),
                          Padding(
                            padding: const EdgeInsets.only(left: 16.0),
                            child: Row(
                              children: [
                                Text(
                                  _currentLanguageFlag == 2
                                      ? 'キーボード'
                                      : 'Keyboard',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(width: 15), // Adjust this value as needed
                                IconButton(
                                  icon: Icon(Icons.keyboard, size: 28),
                                  iconSize: 28,
                                  onPressed: () {
                                    _showInputMethodPicker();
                                  },
                                ),
                              ],
                            ),
                          ),
                          SizedBox(height: 20),
                          Padding(
                            padding: EdgeInsets.only(
                              left: _currentLanguageFlag == 2 ? 46.0 : 30.0,
                            ),
                            child: Row(
                              children: [
                                Text(
                                  _currentLanguageFlag == 2
                                      ? '手引き'
                                      : 'Manual',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                SizedBox(width: 15),
                                IconButton(
                                  icon: Icon(Icons.menu_book, size: 28),
                                  iconSize: 28,
                                  onPressed: () async {
                                    if (_idNumber == null || _currentLanguageFlag == null) return;

                                    try {
                                      final manualUrl = await apiService.fetchManualLink(widget.linkID, _currentLanguageFlag!);
                                      final fileName = 'manual_${widget.linkID}_${_currentLanguageFlag}.pdf';

                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (context) => PDFViewerScreen(
                                            pdfUrl: manualUrl,
                                            fileName: fileName,
                                            languageFlag: _currentLanguageFlag!, // Add this line
                                          ),
                                        ),
                                      );
                                    } catch (e) {
                                      Fluttertoast.showToast(
                                        msg: _currentLanguageFlag == 2
                                            ? "マニュアルの読み込み中にエラーが発生しました: ${e.toString()}"
                                            : "Error loading manual: ${e.toString()}",
                                        toastLength: Toast.LENGTH_LONG,
                                        gravity: ToastGravity.BOTTOM,
                                      );

                                    }
                                  },
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Row(
                      children: [
                        Text(
                          _currentLanguageFlag == 2
                              ? '国'
                              : 'Country',
                          style: TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(width: 25),
                        GestureDetector(
                          onTapDown: (_) => setState(() => _isPhCountryPressed = true),
                          onTapUp: (_) => setState(() => _isPhCountryPressed = false),
                          onTapCancel: () => setState(() => _isPhCountryPressed = false),
                          onTap: () => _updatePhOrJp("ph"),
                          child: AnimatedContainer(
                            duration: Duration(milliseconds: 100),
                            transform: Matrix4.identity()..scale(_isPhCountryPressed ? 0.95 : 1.0),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Image.asset(
                                  'assets/images/philippines.png',
                                  width: 40,
                                  height: 40,
                                ),
                                // Subtle reload icon (only visible when PH is active and not loading)
                                if (_phOrJp == "ph" && !_isCountryLoadingPh)
                                  Opacity(
                                    opacity: 0.6, // Make it subtle
                                    child: Icon(Icons.refresh, size: 20, color: Colors.white),
                                  ),
                                // Loading indicator
                                if (_isCountryLoadingPh)
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                      strokeWidth: 2,
                                    ),
                                  ),
                                // Underline
                                if (_phOrJp == "ph")
                                  Positioned(
                                    bottom: 0,
                                    child: Container(
                                      height: 2,
                                      width: 40,
                                      color: Colors.blue,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                        SizedBox(width: 30),
                        GestureDetector(
                          onTapDown: (_) => setState(() => _isJpCountryPressed = true),
                          onTapUp: (_) => setState(() => _isJpCountryPressed = false),
                          onTapCancel: () => setState(() => _isJpCountryPressed = false),
                          onTap: () => _updatePhOrJp("jp"),
                          child: AnimatedContainer(
                            duration: Duration(milliseconds: 100),
                            transform: Matrix4.identity()..scale(_isJpCountryPressed ? 0.95 : 1.0),
                            child: Stack(
                              alignment: Alignment.center,
                              children: [
                                Image.asset(
                                  'assets/images/japan.png',
                                  width: 40,
                                  height: 40,
                                ),
                                // Subtle reload icon (only visible when JP is active and not loading)
                                if (_phOrJp == "jp" && !_isCountryLoadingJp)
                                  Opacity(
                                    opacity: 0.6, // Make it subtle
                                    child: Icon(Icons.refresh, size: 20, color: Colors.white),
                                  ),
                                // Loading indicator
                                if (_isCountryLoadingJp)
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                                      strokeWidth: 2,
                                    ),
                                  ),
                                // Underline
                                if (_phOrJp == "jp")
                                  Positioned(
                                    bottom: 0,
                                    child: Container(
                                      height: 2,
                                      width: 40,
                                      color: Colors.blue,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        body: SafeArea(
          child: Stack(
            children: [
              if (_webUrl != null)
                WebViewWidget(controller: _controller),
              if (_isLoading)
                LinearProgressIndicator(
                  value: _progress,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                ),
            ],
          ),
        ),
      ),
    );
  }
}