library new_version;

import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:html/parser.dart' show parse;
import 'package:http/http.dart' as http;
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

/// Information about the app's current version, and the most recent version
/// available in the Apple App Store or Google Play Store.
class VersionStatus {
  /// The current version of the app.
  final String localVersion;

  /// The most recent version of the app in the store.
  final String storeVersion;

  /// A link to the app store page where the app can be updated.
  final String appStoreLink;

  /// True if the there is a more recent version of the app in the store.
  bool get canUpdate => localVersion.compareTo(storeVersion).isNegative;

  VersionStatus._({
    required this.localVersion,
    required this.storeVersion,
    required this.appStoreLink,
  });
}

class NewVersion {
  /// An optional value that can override the default packageName when
  /// attempting to reach the Apple App Store. This is useful if your app has
  /// a different package name in the App Store.
  final String? iOSId;

  /// An optional value that can override the default packageName when
  /// attempting to reach the Google Play Store. This is useful if your app has
  /// a different package name in the Play Store.
  final String? androidId;

  /// Only affects iOS App Store lookup: The two-letter country code for the store you want to search.
  /// Provide a value here if your app is only available outside the US.
  /// For example: US. The default is US.
  /// See http://en.wikipedia.org/wiki/ ISO_3166-1_alpha-2 for a list of ISO Country Codes.
  final String? iOSAppStoreCountry;

  NewVersion({
    this.androidId,
    this.iOSId,
    this.iOSAppStoreCountry,
  });

  /// This checks the version status, then displays a platform-specific alert
  /// with buttons to dismiss the update alert, or go to the app store.
  showAlertIfNecessary(
      {required BuildContext context,
      required String dialogText,
      required String dialogTitle,
      required Function dismissAction,
      required String dismissButtonText,
      required String updateButtonText}) async {
    final VersionStatus? versionStatus = await getVersionStatus();
    if (versionStatus != null && versionStatus.canUpdate) {
      showUpdateDialog(
          context: context,
          versionStatus: versionStatus,
          dialogText: dialogText,
          dialogTitle: dialogTitle,
          dismissAction: dismissAction,
          dismissButtonText: dismissButtonText,
          updateButtonText: updateButtonText);
    }
  }


  /// This checks the version status and returns the information. This is useful
  /// if you want to display a custom alert, or use the information in a different
  /// way.
  Future<VersionStatus?> getVersionStatus() async {
    PackageInfo packageInfo = await PackageInfo.fromPlatform();
    if (Platform.isIOS) {
      return _getiOSStoreVersion(packageInfo);
    } else if (Platform.isAndroid) {
      return _getAndroidStoreVersion(packageInfo);
    } else {
      debugPrint(
          'The target platform "${Platform.operatingSystem}" is not yet supported by this package.');
    }
  }

  /// iOS info is fetched by using the iTunes lookup API, which returns a
  /// JSON document.
  Future<VersionStatus?> _getiOSStoreVersion(PackageInfo packageInfo) async {
    final id = iOSId ?? packageInfo.packageName;
    final parameters = {"bundleId": "$id"};
    if (iOSAppStoreCountry != null) {
      parameters.addAll({"country": iOSAppStoreCountry!});
    }
    var uri = Uri.https("itunes.apple.com", "/lookup", parameters);
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      debugPrint('Can\'t find an app in the App Store with the id: $id');
      return null;
    }
    final jsonObj = json.decode(response.body);
    return VersionStatus._(
      localVersion: packageInfo.version,
      storeVersion: jsonObj['results'][0]['version'],
      appStoreLink: jsonObj['results'][0]['trackViewUrl'],
    );
  }

  /// Android info is fetched by parsing the html of the app store page.
  Future<VersionStatus?> _getAndroidStoreVersion(
      PackageInfo packageInfo) async {
    final id = androidId ?? packageInfo.packageName;
    final uri =
        Uri.https("play.google.com", "/store/apps/details", {"id": "$id"});
    final response = await http.get(uri);
    if (response.statusCode != 200) {
      debugPrint('Can\'t find an app in the Play Store with the id: $id');
      return null;
    }
    final document = parse(response.body);
    final elements = document.getElementsByClassName('hAyfc');
    final versionElement = elements.firstWhere(
      (elm) => elm.querySelector('.BgcNfc')!.text == 'Current Version',
    );
    return VersionStatus._(
      localVersion: packageInfo.version,
      storeVersion: versionElement.querySelector('.htlgb')!.text,
      appStoreLink: uri.toString(),
    );
  }

  /// Shows the user a platform-specific alert about the app update. The user
  /// can dismiss the alert or proceed to the app store.
  ///
  /// To change the appearance and behavior of the update dialog, you can
  /// optionally provide [dialogTitle], [dialogText], [updateButtonText],
  /// [dismissButtonText], and [dismissAction] parameters.
  void showUpdateDialog({
    required BuildContext context,
    required VersionStatus versionStatus,
    String dialogTitle = 'Update Available',
    String? dialogText,
    String updateButtonText = 'Update',
    String dismissButtonText = 'Maybe Later',
    VoidCallback? dismissAction,
  }) async {
    final dialogTitleWidget = Text(dialogTitle);
    final dialogTextWidget = Text(
      dialogText ??
          'You can now update this app from ${versionStatus.localVersion} to ${versionStatus.storeVersion}',
    );
    final updateButtonTextWidget = Text(updateButtonText);
    final dismissButtonTextWidget = Text(dismissButtonText);
    dismissAction =
        dismissAction ?? () => Navigator.of(context, rootNavigator: true).pop();
    final updateAction = () {
      _launchAppStore(versionStatus.appStoreLink);
      Navigator.of(context, rootNavigator: true).pop();
    };

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return Platform.isAndroid
            ? AlertDialog(
                title: dialogTitleWidget,
                content: dialogTextWidget,
                actions: <Widget>[
                  TextButton(
                    child: dismissButtonTextWidget,
                    onPressed: dismissAction,
                  ),
                  TextButton(
                    child: updateButtonTextWidget,
                    onPressed: updateAction,
                  ),
                ],
              )
            : CupertinoAlertDialog(
                title: dialogTitleWidget,
                content: dialogTextWidget,
                actions: <Widget>[
                  CupertinoDialogAction(
                    child: dismissButtonTextWidget,
                    onPressed: dismissAction,
                  ),
                  CupertinoDialogAction(
                    child: updateButtonTextWidget,
                    onPressed: updateAction,
                  ),
                ],
              );
      },
    );
  }

  /// Launches the Apple App Store or Google Play Store page for the app.
  void _launchAppStore(String appStoreLink) async {
    debugPrint(appStoreLink);
    if (await canLaunch(appStoreLink)) {
      await launch(appStoreLink);
    } else {
      throw 'Could not launch appStoreLink';
    }
  }
}
