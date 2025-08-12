import 'dart:convert';
import 'dart:io';

import 'package:flet/flet.dart';
import 'package:flet_webview/src/utils/webview.dart';
import 'package:flutter/material.dart';
import 'package:webview_flutter/webview_flutter.dart';

class WebviewMobileAndMac extends StatefulWidget {
  final Control control;
  final FletControlBackend backend;
  final Color? bgcolor;

  const WebviewMobileAndMac(
      {super.key, required this.control, required this.backend, this.bgcolor});

  @override
  State<WebviewMobileAndMac> createState() => _WebviewMobileAndMacState();
}

class _WebviewMobileAndMacState extends State<WebviewMobileAndMac> {
  late WebViewController controller;
  bool _isLoading = true;
  bool _isInitialized = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _initializeWebView();
    
    // Fallback timeout to prevent infinite loading
    Future.delayed(const Duration(seconds: 10), () {
      if (mounted && _isLoading && _errorMessage == null) {
        setState(() {
          _isLoading = false;
          _errorMessage = "WebView loading timeout (10 seconds)";
        });
      }
    });
  }

  Future<void> _initializeWebView() async {
    try {
      // Platform-specific initialization with null safety
      var params = const PlatformWebViewControllerCreationParams();
      controller = WebViewController.fromPlatformCreationParams(params);

      var preventLink = widget.control.attrString("preventLink")?.trim();
      
      // Set background color with null check
      try {
        Color bgColor = widget.bgcolor ?? Colors.white;
        await controller.setBackgroundColor(bgColor);
      } catch (e) {
        debugPrint('Error setting background color: $e');
      }

      // Enable JavaScript with error handling
      try {
        await controller.setJavaScriptMode(JavaScriptMode.unrestricted);
      } catch (e) {
        debugPrint('Error setting JavaScript mode: $e');
      }

      // Set navigation delegate with comprehensive null checks
      try {
        await controller.setNavigationDelegate(
          NavigationDelegate(
            onProgress: (int progress) {
              try {
                debugPrint('WebViewControl is loading (progress : $progress%)');
                widget.backend.triggerControlEvent(
                    widget.control.id, "progress", progress.toString());
                
                if (progress == 100 && mounted) {
                  setState(() {
                    _isLoading = false;
                    _errorMessage = null;
                  });
                }
              } catch (e) {
                debugPrint('Error in onProgress: $e');
              }
            },
            onUrlChange: (UrlChange url) {
              try {
                debugPrint('WebViewControl URL changed: ${url.url}');
                widget.backend.triggerControlEvent(
                    widget.control.id, "url_change", url.url ?? "");
              } catch (e) {
                debugPrint('Error in onUrlChange: $e');
              }
            },
            onPageStarted: (String url) {
              try {
                debugPrint('WebViewControl page started loading: $url');
                if (mounted) {
                  setState(() {
                    _isLoading = true;
                    _errorMessage = null;
                  });
                }
                widget.backend
                    .triggerControlEvent(widget.control.id, "page_started", url);
              } catch (e) {
                debugPrint('Error in onPageStarted: $e');
              }
            },
            onPageFinished: (String url) {
              try {
                debugPrint('WebViewControl page finished loading: $url');
                if (mounted) {
                  setState(() {
                    _isLoading = false;
                    _errorMessage = null;
                  });
                }
                widget.backend
                    .triggerControlEvent(widget.control.id, "page_ended", url);
              } catch (e) {
                debugPrint('Error in onPageFinished: $e');
              }
            },
            onWebResourceError: (WebResourceError error) {
              try {
                String errorDesc = error.description ?? "Unknown error";
                int errorCode = error.errorCode ?? -1;
                String errorType = error.errorType?.name ?? "Unknown";
                
                debugPrint('WebView error: $errorDesc');
                if (mounted) {
                  setState(() {
                    _isLoading = false;
                    _errorMessage = "WebView Resource Error: $errorDesc\nError Code: $errorCode\nError Type: $errorType";
                  });
                }
                widget.backend.triggerControlEvent(widget.control.id,
                    "web_resource_error", "WebView error: $errorDesc");
              } catch (e) {
                debugPrint('Error in onWebResourceError: $e');
              }
            },
            onNavigationRequest: (NavigationRequest request) {
              try {
                if (preventLink != null && request.url.startsWith(preventLink)) {
                  return NavigationDecision.prevent;
                }
                return NavigationDecision.navigate;
              } catch (e) {
                debugPrint('Error in onNavigationRequest: $e');
                return NavigationDecision.navigate;
              }
            },
          ),
        );
      } catch (e) {
        debugPrint('Error setting navigation delegate: $e');
        if (mounted) {
          setState(() {
            _errorMessage = "Failed to set navigation delegate: $e";
            _isLoading = false;
          });
        }
        return;
      }

      // Mark as initialized before loading content
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }

      // Load the initial URL with comprehensive error handling
      try {
        String? urlString = widget.control.attrString("url");
        if (urlString == null || urlString.isEmpty) {
          urlString = "https://flet.dev";
        }
        
        var method = parseLoadRequestMethod(
            widget.control.attrString("method"), LoadRequestMethod.get);
        if (method == null) {
          method = LoadRequestMethod.get;
        }
        
        debugPrint('Loading URL: $urlString with method: $method');
        Uri? uri = Uri.tryParse(urlString);
        if (uri == null) {
          throw Exception("Invalid URL: $urlString");
        }
        
        await controller.loadRequest(uri, method: method);
      } catch (e) {
        debugPrint('Error loading initial URL: $e');
        if (mounted) {
          setState(() {
            _errorMessage = "Failed to load URL: $e";
            _isLoading = false;
          });
        }
        
        // Fallback to a simple HTML page with error
        try {
          await controller.loadHtmlString(
            '<html><body><h1>WebView Error</h1><p>URL loading failed: $e</p><p>Platform: macOS</p></body></html>'
          );
          if (mounted) {
            setState(() {
              _isLoading = false;
            });
          }
        } catch (htmlError) {
          debugPrint('Error loading fallback HTML: $htmlError');
          if (mounted) {
            setState(() {
              _errorMessage = "Critical WebView Error: Cannot load URL or HTML content\nOriginal error: $e\nHTML error: $htmlError";
            });
          }
        }
      }

      // Set listeners with individual error handling
      _setEventListeners();

      // Subscribe to backend methods
      _subscribeToBackendMethods();

    } catch (e) {
      debugPrint('Error initializing WebView: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isInitialized = true;
          _errorMessage = "WebView initialization failed: $e\nPlatform: ${Platform.operatingSystem}\nThis might be a macOS WebView compatibility issue.";
        });
      }
    }
  }

  void _setEventListeners() {
    // Set scroll position change listener
    try {
      controller.setOnScrollPositionChange((ScrollPositionChange position) {
        try {
          widget.backend.triggerControlEvent(
              widget.control.id,
              "scroll",
              jsonEncode({
                "x": (position.x ?? 0).toString(),
                "y": (position.y ?? 0).toString(),
              }));
        } catch (e) {
          debugPrint('Error in scroll listener: $e');
        }
      });
    } catch (e) {
      debugPrint('Error setting scroll listener: $e');
    }

    // Set console message listener
    try {
      controller.setOnConsoleMessage((JavaScriptConsoleMessage message) {
        try {
          widget.backend.triggerControlEvent(
              widget.control.id,
              "console_message",
              jsonEncode({
                "message": message.message ?? "",
                "level": message.level?.name ?? "unknown",
              }));
        } catch (e) {
          debugPrint('Error in console message listener: $e');
        }
      });
    } catch (e) {
      debugPrint('Error setting console listener: $e');
    }

    // Set JavaScript alert dialog listener
    try {
      controller.setOnJavaScriptAlertDialog(
          (JavaScriptAlertDialogRequest request) async {
        try {
          widget.backend.triggerControlEvent(
              widget.control.id,
              "javascript_alert_dialog",
              jsonEncode({
                "message": request.message ?? "",
                "url": request.url ?? "",
              }));
        } catch (e) {
          debugPrint('Error in JS alert listener: $e');
        }
      });
    } catch (e) {
      debugPrint('Error setting JS alert listener: $e');
    }
  }

  void _subscribeToBackendMethods() {
    widget.backend.subscribeMethods(widget.control.id,
        (methodName, args) async {
      try {
        switch (methodName) {
          case "reload":
            await controller.reload();
            break;
          case "can_go_back":
            bool canGoBack = await controller.canGoBack();
            return canGoBack.toString();
          case "can_go_forward":
            bool canGoForward = await controller.canGoForward();
            return canGoForward.toString();
          case "go_back":
            if (await controller.canGoBack()) {
              await controller.goBack();
            }
            break;
          case "go_forward":
            if (await controller.canGoForward()) {
              await controller.goForward();
            }
            break;
          case "enable_zoom":
            await controller.enableZoom(true);
            break;
          case "disable_zoom":
            await controller.enableZoom(false);
            break;
          case "clear_cache":
            await controller.clearCache();
            break;
          case "clear_local_storage":
            await controller.clearLocalStorage();
            break;
          case "get_current_url":
            String? currentUrl = await controller.currentUrl();
            return currentUrl ?? "";
          case "get_title":
            String? title = await controller.getTitle();
            return title ?? "";
          case "get_user_agent":
            String? userAgent = await controller.getUserAgent();
            return userAgent ?? "";
          case "load_file":
            var path = args?["path"];
            if (path != null) {
              await controller.loadFile(path);
            }
            break;
          case "load_html":
            var html = args?["value"];
            if (html != null) {
              String? baseUrl = args?["base_url"];
              await controller.loadHtmlString(html, baseUrl: baseUrl);
            }
            break;
          case "load_request":
            var url = args?["url"];
            if (url != null) {
              var method = parseLoadRequestMethod(
                  args?["method"], LoadRequestMethod.get) ?? LoadRequestMethod.get;
              Uri? uri = Uri.tryParse(url);
              if (uri != null) {
                await controller.loadRequest(uri, method: method);
              }
            }
            break;
          case "run_javascript":
            var javascript = args?["value"];
            if (javascript != null) {
              await controller.runJavaScript(javascript);
            }
            break;
          case "scroll_to":
            var x = parseInt(args?["x"]);
            var y = parseInt(args?["y"]);
            if (x != null && y != null) {
              await controller.scrollTo(x, y);
            }
            break;
          case "scroll_by":
            var x = parseInt(args?["x"]);
            var y = parseInt(args?["y"]);
            if (x != null && y != null) {
              await controller.scrollBy(x, y);
            }
            break;
          case "set_javascript_mode":
            var value = parseBool(args?["value"]);
            if (value != null) {
              await controller.setJavaScriptMode(
                  value ? JavaScriptMode.unrestricted : JavaScriptMode.disabled);
            }
            break;
        }
      } catch (e) {
        debugPrint('Error in backend method $methodName: $e');
      }
      return null;
    });
  }

  @override
  Widget build(BuildContext context) {
    debugPrint("WebViewControl build: ${widget.control.id}");

    // Show error message if there's an error
    if (_errorMessage != null) {
      return Container(
        padding: const EdgeInsets.all(16.0),
        color: Colors.red.shade50,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline,
              color: Colors.red.shade700,
              size: 48,
            ),
            const SizedBox(height: 16),
            Text(
              "WebView Error",
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: Colors.red.shade700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _errorMessage!,
              style: TextStyle(
                fontSize: 14,
                color: Colors.red.shade600,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () {
                setState(() {
                  _errorMessage = null;
                  _isLoading = true;
                  _isInitialized = false;
                });
                _initializeWebView();
              },
              child: const Text("Retry"),
            ),
          ],
        ),
      );
    }

    if (!_isInitialized) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return Stack(
      children: [
        WebViewWidget(controller: controller),
        if (_isLoading)
          Container(
            color: Colors.white.withOpacity(0.8),
            child: const Center(
              child: CircularProgressIndicator(),
            ),
          ),
      ],
    );
  }
}
