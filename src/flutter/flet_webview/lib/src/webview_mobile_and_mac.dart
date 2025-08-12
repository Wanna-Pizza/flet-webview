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
      // Platform-specific initialization
      var params = const PlatformWebViewControllerCreationParams();
      controller = WebViewController.fromPlatformCreationParams(params);

      var preventLink = widget.control.attrString("preventLink")?.trim();
      
      // Set background color first
      if (widget.bgcolor != null) {
        await controller.setBackgroundColor(widget.bgcolor!);
      } else {
        await controller.setBackgroundColor(Colors.white);
      }

      // Enable JavaScript
      await controller.setJavaScriptMode(JavaScriptMode.unrestricted);

      // Set navigation delegate
      await controller.setNavigationDelegate(
        NavigationDelegate(
          onProgress: (int progress) {
            debugPrint('WebViewControl is loading (progress : $progress%)');
            widget.backend.triggerControlEvent(
                widget.control.id, "progress", progress.toString());
            
            if (progress == 100 && mounted) {
              setState(() {
                _isLoading = false;
                _errorMessage = null;
              });
            }
          },
          onUrlChange: (UrlChange url) {
            debugPrint('WebViewControl URL changed: ${url.url}');
            widget.backend.triggerControlEvent(
                widget.control.id, "url_change", url.url ?? "");
          },
          onPageStarted: (String url) {
            debugPrint('WebViewControl page started loading: $url');
            if (mounted) {
              setState(() {
                _isLoading = true;
                _errorMessage = null;
              });
            }
            widget.backend
                .triggerControlEvent(widget.control.id, "page_started", url);
          },
          onPageFinished: (String url) {
            debugPrint('WebViewControl page finished loading: $url');
            if (mounted) {
              setState(() {
                _isLoading = false;
                _errorMessage = null;
              });
            }
            widget.backend
                .triggerControlEvent(widget.control.id, "page_ended", url);
          },
          onWebResourceError: (WebResourceError error) {
            debugPrint('WebView error: ${error.description}');
            if (mounted) {
              setState(() {
                _isLoading = false;
                _errorMessage = "WebView Resource Error: ${error.description}\nError Code: ${error.errorCode}\nError Type: ${error.errorType?.name ?? 'Unknown'}";
              });
            }
            widget.backend.triggerControlEvent(widget.control.id,
                "web_resource_error", "WebView error: ${error.description}");
          },
          onNavigationRequest: (NavigationRequest request) {
            if (preventLink != null && request.url.startsWith(preventLink)) {
              return NavigationDecision.prevent;
            }
            return NavigationDecision.navigate;
          },
        ),
      );

      // Mark as initialized before loading content
      if (mounted) {
        setState(() {
          _isInitialized = true;
        });
      }

      // Load the initial URL
      try {
        final url = widget.control.attrString("url", "https://flet.dev")!;
        final method = parseLoadRequestMethod(
            widget.control.attrString("method"), LoadRequestMethod.get)!;
        
        debugPrint('Loading URL: $url with method: $method');
        await controller.loadRequest(Uri.parse(url), method: method);
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
            '<html><body><h1>WebView Error</h1><p>URL loading failed: $e</p></body></html>'
          );
        } catch (htmlError) {
          debugPrint('Error loading fallback HTML: $htmlError');
          if (mounted) {
            setState(() {
              _errorMessage = "Critical WebView Error: Cannot load URL or HTML content\nOriginal error: $e\nHTML error: $htmlError";
            });
          }
        }
      }

      // Set scroll position change listener
      try {
        await controller.setOnScrollPositionChange((ScrollPositionChange position) {
          widget.backend.triggerControlEvent(
              widget.control.id,
              "scroll",
              jsonEncode({
                "x": position.x.toString(),
                "y": position.y.toString(),
              }));
        });
      } catch (e) {
        debugPrint('Error setting scroll listener: $e');
      }

      // Set console message listener
      try {
        await controller.setOnConsoleMessage((JavaScriptConsoleMessage message) {
          widget.backend.triggerControlEvent(
              widget.control.id,
              "console_message",
              jsonEncode({
                "message": message.message,
                "level": message.level.name,
              }));
        });
      } catch (e) {
        debugPrint('Error setting console listener: $e');
      }

      // Set JavaScript alert dialog listener
      try {
        await controller.setOnJavaScriptAlertDialog(
            (JavaScriptAlertDialogRequest request) async {
          widget.backend.triggerControlEvent(
              widget.control.id,
              "javascript_alert_dialog",
              jsonEncode({
                "message": request.message,
                "url": request.url,
              }));
        });
      } catch (e) {
        debugPrint('Error setting JS alert listener: $e');
      }

      // Subscribe to backend methods
      widget.backend.subscribeMethods(widget.control.id,
          (methodName, args) async {
        switch (methodName) {
          case "reload":
            await controller.reload();
            break;
          case "can_go_back":
            return controller.canGoBack().toString();
          case "can_go_forward":
            return controller.canGoForward().toString();
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
            return await controller.currentUrl();
          case "get_title":
            return await controller.getTitle();
          case "get_user_agent":
            return await controller.getUserAgent();
          case "load_file":
            var path = args["path"];
            if (path != null) {
              await controller.loadFile(path);
            }
            break;
          case "load_html":
            var html = args["value"];
            if (html != null) {
              await controller.loadHtmlString(html, baseUrl: args["base_url"]);
            }
            break;
          case "load_request":
            var url = args["url"];
            if (url != null) {
              await controller.loadRequest(Uri.parse(url),
                  method: parseLoadRequestMethod(
                      args["method"], LoadRequestMethod.get)!);
            }
            break;
          case "run_javascript":
            var javascript = args["value"];
            if (javascript != null) {
              await controller.runJavaScript(javascript);
            }
            break;
          case "scroll_to":
            var x = parseInt(args["x"]);
            var y = parseInt(args["y"]);
            if (x != null && y != null) {
              await controller.scrollTo(x, y);
            }
            break;
          case "scroll_by":
            var x = parseInt(args["x"]);
            var y = parseInt(args["y"]);
            if (x != null && y != null) {
              await controller.scrollBy(x, y);
            }
            break;
          case "set_javascript_mode":
            var value = parseBool(args["value"]);
            if (value != null) {
              await controller.setJavaScriptMode(
                  value ? JavaScriptMode.unrestricted : JavaScriptMode.disabled);
            }
            break;
        }
        return null;
      });
    } catch (e) {
      debugPrint('Error initializing WebView: $e');
      if (mounted) {
        setState(() {
          _isLoading = false;
          _isInitialized = true;
          _errorMessage = "WebView initialization failed: $e\nPlatform: ${Platform.operatingSystem}";
        });
      }
    }
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
