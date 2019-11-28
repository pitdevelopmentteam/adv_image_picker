import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:adv_image_picker/adv_image_picker.dart';
import 'package:adv_image_picker/components/toast.dart';
import 'package:adv_image_picker/models/result_item.dart';
import 'package:adv_image_picker/pages/gallery.dart';
import 'package:adv_image_picker/pages/result.dart';
import 'package:adv_image_picker/plugins/adv_future_builder.dart';
import 'package:adv_image_picker/plugins/adv_image_picker_plugin.dart';
import 'package:basic_components/components/adv_button.dart';
import 'package:basic_components/components/adv_column.dart';
import 'package:basic_components/components/adv_loading_with_barrier.dart';
import 'package:basic_components/components/adv_visibility.dart';
import 'package:camera/camera.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter_exif_rotation/flutter_exif_rotation.dart';
import 'package:path_provider/path_provider.dart';

class CameraFlutterPage extends StatefulWidget {
  final bool allowMultiple;
  final bool enableGallery;
  final int maxSize;

  CameraFlutterPage({bool allowMultiple, bool enableGallery, this.maxSize})
      : assert(maxSize == null || maxSize >= 0),
        this.allowMultiple = allowMultiple ?? true,
        this.enableGallery = enableGallery ?? true;
  @override
  _CameraFlutterPageState createState() => _CameraFlutterPageState();
}

void logError(String code, String message) =>
    print('${AdvImagePicker.error}: $code\n${AdvImagePicker.errorMessage}: $message');

class _CameraFlutterPageState extends State<CameraFlutterPage> with WidgetsBindingObserver {
  List<CameraDescription> cameras;
  int indexCameras = 0;
  CameraController controller;
  String imagePath;


  @override
  void initState()  {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // App state changed before we got the chance to initialize.
    if (controller == null || !controller.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      controller?.dispose();
    } else if (state == AppLifecycleState.resumed) {
      if (controller != null) {
        onNewCameraSelected(controller.description);
      }
    }
  }

  final GlobalKey<ScaffoldState> _scaffoldKey = GlobalKey<ScaffoldState>();

  @override
  Widget build(BuildContext context) {
    return AdvFutureBuilder(futureExecutor: init, widgetBuilder: (context) =>Scaffold(
      appBar: AppBar(
        title: Text(
          AdvImagePicker.takePicture,
          style: TextStyle(color: Colors.black87),
        ),
        centerTitle: true,
        elevation: 0.0,
        backgroundColor: Colors.white,
        iconTheme: IconThemeData(color: Colors.black87),
      ),
      bottomSheet: Container(
          height: 80.0,
          padding: EdgeInsets.symmetric(horizontal: 32.0, vertical: 8.0),
          color: Colors.white,
          child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                AdvButton.custom(
                  child: AdvColumn(divider: ColumnDivider(4.0), children: [
                    Text(AdvImagePicker.rotate),
                    Icon(Icons.switch_camera),
                  ]),
                  buttonSize: ButtonSize.small,
                  primaryColor: Colors.white,
                  accentColor: Colors.black87,
                  onPressed: () {
                    if(controller!=null){
                      if(indexCameras < cameras.length-1){
                        indexCameras++;
                      } else {
                        indexCameras = 0;
                      }
                      onNewCameraSelected(cameras[indexCameras]);
                    }
//
                  },
                ),
                Container(
                    margin: EdgeInsets.only(bottom: 8.0),
                    child: Text(
                      AdvImagePicker.photo,
                      style: TextStyle(fontWeight: FontWeight.w700, fontSize: 12.0),
                    )),
                AdvVisibility(
                  visibility:
                  widget.enableGallery ? VisibilityFlag.visible : VisibilityFlag.invisible,
                  child: AdvButton.custom(
                    child: AdvColumn(divider: ColumnDivider(4.0), children: [
                      Text(AdvImagePicker.gallery),
                      Icon(Icons.photo_album),
                    ]),
                    buttonSize: ButtonSize.small,
                    primaryColor: Colors.white,
                    accentColor: Colors.black87,
                    onPressed: () async {
                      if (Platform.isIOS) {
                        bool hasPermission = await AdvImagePickerPlugin.getIosStoragePermission();
                        if (!hasPermission) {
                          Toast.showToast(context, "Permission denied");
                          return null;
                        } else {
                          goToGallery();
                        }
                      } else {
                        goToGallery();
                      }
                    },
                  ),
                ),
              ])),
      key: _scaffoldKey,
      body: Container(child:_buildWidget() , color:Colors.white,),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
      floatingActionButton: FloatingActionButton(
        elevation: 0.0,
        onPressed:
        controller != null && controller.value.isInitialized
            ? onTakePictureButtonPressed
            : null,

        backgroundColor: AdvImagePicker.primaryColor,
        highlightElevation: 0.0,
        child: Container(
          width: 30.0,
          height: 30.0,
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.all(Radius.circular(30.0))),
        ),
      ),
    ),);
  }

  goToGallery() {
    Navigator.push(
        context,
        MaterialPageRoute(
            builder: (BuildContext context) =>
                GalleryPage(
                  allowMultiple: widget.allowMultiple,
                  maxSize: widget.maxSize,
                )));
  }

  String timestamp() => DateTime.now().millisecondsSinceEpoch.toString();

  void showInSnackBar(String message) {
    _scaffoldKey.currentState.showSnackBar(SnackBar(content: Text(message)));
  }

  Widget _buildWidget() {
    return AdvLoadingWithBarrier(
        content: (BuildContext context) => _cameraPreviewWidget(),
        processingContent: (BuildContext context) => Container(),
        isProcessing: controller == null || !controller.value.isInitialized);
  }

  Widget _cameraPreviewWidget() {
    if (controller == null) {
      return const Text(
        'Prepare',
        style: TextStyle(
          color: Colors.white,
          fontSize: 24.0,
          fontWeight: FontWeight.w900,
        ),
      );
    } else {
      return ClipRect(child: OverflowBox(child: AspectRatio(
        aspectRatio: controller.value.aspectRatio,
        child: CameraPreview(controller),
      ),));
    }
  }

  void onNewCameraSelected(CameraDescription cameraDescription) async {
    if (controller != null) {
      await controller.dispose();
    }
    controller = CameraController(
      cameraDescription,
      ResolutionPreset.medium,
      enableAudio: false,
    );

    // If the controller is updated then update the UI.
    controller.addListener(() {
      if (mounted) setState(() {});
      if (controller.value.hasError) {
        showInSnackBar('Camera error ${controller.value.errorDescription}');
      }
    });

    try {
      await controller.initialize();
    } on CameraException catch (e) {
      _showCameraException(e);
    }

    if (mounted) {
      setState(() {});
    }
  }

  void onTakePictureButtonPressed() {
    takePicture().then((String filePath) async{
      if (filePath == null) return;
      ByteData bytes = await _readFileByte(filePath);
      Navigator.push(
          context,
          MaterialPageRoute(
              builder: (BuildContext context) =>
                  ResultPage([ResultItem("", filePath, data: bytes)])));
    });
  }

  Future<ByteData> _readFileByte(String filePath) async {
    Uri myUri = Uri.parse(filePath);
    File imageFile = new File.fromUri(myUri);
    imageFile = await FlutterExifRotation.rotateAndSaveImage(path: imageFile.path);
    Uint8List bytes;
    await imageFile.readAsBytes().then((value) {
      bytes = Uint8List.fromList(value);
      print('reading of bytes is completed');
    }).catchError((onError) {
      print('Exception Error while reading audio from path:' + onError.toString());
    });
    return bytes.buffer.asByteData();
  }

  Future<String> takePicture() async {
    if (!controller.value.isInitialized) {
      showInSnackBar('Error: select a camera first.');
      return null;
    }
    final Directory extDir = await getApplicationDocumentsDirectory();
    final String dirPath = '${extDir.path}/Pictures/flutter_test';
    await Directory(dirPath).create(recursive: true);
    final String filePath = '$dirPath/${timestamp()}.jpg';

    if (controller.value.isTakingPicture) {
      // A capture is already pending, do nothing.
      return null;
    }

    try {
      await controller.takePicture(filePath);
    } on CameraException catch (e) {
      _showCameraException(e);
      return null;
    }
    return filePath;
  }

  void _showCameraException(CameraException e) {
    logError(e.code, e.description);
    showInSnackBar('Error: ${e.code}\n${e.description}');
  }

  Future<bool> init(BuildContext context) async{
    try {
      cameras = await availableCameras();
      onNewCameraSelected(cameras[0]);
    } on CameraException catch (e) {
      logError(e.code, e.description);
    }

    return true;
  }


}
