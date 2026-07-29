import AuthenticationServices
import Flutter
import UIKit

@main
@objc class AppDelegate: FlutterAppDelegate, FlutterImplicitEngineDelegate {
  private var oauthBrowserBridge: OAuthBrowserBridge?

  override func application(
    _ application: UIApplication,
    didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]?
  ) -> Bool {
    return super.application(application, didFinishLaunchingWithOptions: launchOptions)
  }

  func didInitializeImplicitFlutterEngine(_ engineBridge: FlutterImplicitEngineBridge) {
    GeneratedPluginRegistrant.register(with: engineBridge.pluginRegistry)
    oauthBrowserBridge = OAuthBrowserBridge(
      binaryMessenger: engineBridge.applicationRegistrar.messenger()
    )
  }
}

private final class OAuthBrowserBridge: NSObject,
  ASWebAuthenticationPresentationContextProviding
{
  private static let channelName = "com.nanvon.cctrace.mobile/oauth_browser"
  private static let allowedAuthorizeHosts = Set(["auth.openai.com", "claude.com"])
  private static let cancelledLoginErrorCode = 1

  private let channel: FlutterMethodChannel
  private var session: ASWebAuthenticationSession?
  private var activeSessionID: UUID?
  private var programmaticClosures = Set<UUID>()

  init(binaryMessenger: FlutterBinaryMessenger) {
    channel = FlutterMethodChannel(
      name: Self.channelName,
      binaryMessenger: binaryMessenger
    )
    super.init()
    channel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
  }

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "open":
      guard
        let arguments = call.arguments as? [String: Any],
        let urlValue = arguments["url"] as? String,
        let url = URL(string: urlValue),
        url.scheme == "https",
        let host = url.host,
        Self.allowedAuthorizeHosts.contains(host)
      else {
        result(
          FlutterError(
            code: "INVALID_ARGUMENT",
            message: "Authorize URL is not allowed.",
            details: nil
          )
        )
        return
      }
      open(url, result: result)
    case "close":
      closeActiveSession(programmatically: true)
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func open(_ url: URL, result: @escaping FlutterResult) {
    closeActiveSession(programmatically: true)

    let sessionID = UUID()
    let nextSession = ASWebAuthenticationSession(
      url: url,
      callbackURLScheme: nil
    ) { [weak self] callbackURL, error in
      DispatchQueue.main.async {
        self?.handleCompletion(
          sessionID: sessionID,
          callbackURLReceived: callbackURL != nil,
          error: error
        )
      }
    }
    nextSession.presentationContextProvider = self

    session = nextSession
    activeSessionID = sessionID
    guard nextSession.start() else {
      session = nil
      activeSessionID = nil
      result(
        FlutterError(
          code: "SESSION_START_FAILED",
          message: "Authentication browser session could not start.",
          details: nil
        )
      )
      return
    }

    result(nil)
  }

  private func handleCompletion(
    sessionID: UUID,
    callbackURLReceived: Bool,
    error: Error?
  ) {
    if programmaticClosures.remove(sessionID) != nil {
      return
    }
    guard activeSessionID == sessionID else {
      return
    }

    session = nil
    activeSessionID = nil

    if callbackURLReceived {
      channel.invokeMethod(
        "browserFailed",
        arguments: ["category": "callback intercepted by browser session"]
      )
      return
    }

    let errorCode = (error as? NSError)?.code
    if errorCode == Self.cancelledLoginErrorCode {
      channel.invokeMethod("browserCancelled", arguments: nil)
    } else {
      channel.invokeMethod(
        "browserFailed",
        arguments: ["category": "browser session failed"]
      )
    }
  }

  private func closeActiveSession(programmatically: Bool) {
    guard let activeSessionID, let session else {
      return
    }
    if programmatically {
      programmaticClosures.insert(activeSessionID)
    }
    self.session = nil
    self.activeSessionID = nil
    session.cancel()
  }

  func presentationAnchor(
    for session: ASWebAuthenticationSession
  ) -> ASPresentationAnchor {
    let windows = UIApplication.shared.connectedScenes
      .compactMap { $0 as? UIWindowScene }
      .flatMap(\.windows)
    return windows.first(where: \.isKeyWindow) ?? ASPresentationAnchor()
  }
}
