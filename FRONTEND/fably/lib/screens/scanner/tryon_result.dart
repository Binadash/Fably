import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data'; // For handling image bytes
import 'package:fably/utils/globals.dart';
import 'package:fably/utils/requests.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

class VirtualTryOnResultPage extends StatefulWidget {
  final File? inputImage;
  final String id;

  const VirtualTryOnResultPage({super.key, this.inputImage, required this.id});

  @override
  _VirtualTryOnResultPageState createState() => _VirtualTryOnResultPageState();
}

class _VirtualTryOnResultPageState extends State<VirtualTryOnResultPage> {
  Uint8List? resultImageBytes; // To store the image bytes from the backend
  bool isLoading = false;
  String? errorMessage;
  String image_url = "";
  String vton_id = "";
  String loadingMessage = 'Uploading Images';
  Timer? _timer;
  Timer? _timeoutTimer;

  @override
  void initState() {
    super.initState();
    _fetchTryOnResult();
  }

  void _showMessage(String message) {
    print(message);
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // start sending post requests
  void startSendingPostRequests(Duration interval) {
    _timer = Timer.periodic(interval, (Timer timer) async {
      await sendPostRequest();
    });

    // Start timeout timer to stop periodic requests after the given timeout
    Duration timeout = Duration(minutes: 2);
    _timeoutTimer = Timer(timeout, () {
      _timer?.cancel(); // Stop the periodic timer
      print("Stopped sending requests after ${timeout.inSeconds} seconds.");
    });
  }

  // Stop sending requests
  void stopSendingPostRequests() {
    _timer?.cancel();
  }

  // The POST request logic
  Future<void> sendPostRequest() async {
    final requests = BackendRequests();

    try {
      final response = await requests.postRequest("vton/fetch_url/", body: {
        "vton_id": vton_id,
        "item_id": widget.id,
      });

      if (response.statusCode == 200) {
        if (response.body == "processing") {
          setState(() {
            loadingMessage = "Generating Image. This might take a few minuites";
          });
        } else {
          setState(() {
            image_url = response.body;
            isLoading = false;
            loadingMessage = "Image generated successfully";
          });
          stopSendingPostRequests();
        }
        //_showMessage('POST request successful: ${response.body}');
      } else {
        print('Failed to send POST request: ${response.statusCode}');
      }
    } catch (error) {
      print('Error occurred while sending POST request: $error');
    }
  }

  String compressImageToBase64(Uint8List imageBytes,
      {/*int maxWidth = 800, int maxHeight = 800,*/ int quality = 85}) {
    try {
      // Decode the image bytes
      img.Image? image = img.decodeImage(imageBytes);
      if (image == null) {
        throw Exception('Invalid image data');
      }

      // Resize the image if it exceeds the max dimensions
      /*if (image.width > maxWidth || image.height > maxHeight) {
        image = img.copyResize(image, width: maxWidth, height: maxHeight);
      }*/

      // Compress the image with the specified quality
      final compressedImageBytes = img.encodeJpg(image, quality: quality);

      // Convert the compressed image to Base64
      final base64String = base64Encode(compressedImageBytes);

      return base64String;
    } catch (e) {
      throw Exception('Error compressing and encoding image: $e');
    }
  }

  Future<void> _fetchTryOnResult() async {
    if (widget.inputImage == null) {
      setState(() {
        errorMessage = "No image provided for try-on.";
      });
      return;
    }

    setState(() {
      isLoading = true;
      errorMessage = null;
    });

    // temporarily display the input image as the result image
    widget.inputImage!.readAsBytes().then((bytes) {
      setState(() {
        resultImageBytes = bytes;
      });
    }).catchError((error) {
      setState(() {
        errorMessage = "Failed to load image: $error";
      });
    });

    // --------------------------------------------------------

    final imageFile = widget.inputImage;
    final requests = BackendRequests();

    if (imageFile == null) {
      _showMessage('Please select an image');
      return;
    }

    // Convert image to Base64
    final bytes = await imageFile.readAsBytes();
    //final base64Image = compressImageToBase64(bytes);
    final base64Image = base64Encode(bytes);
    String debugMode = "$tryOnDebugMode";
    print("debugMode = $debugMode");

    // JSON payload
    final payload = {
      "item_id": widget.id, // Example ID
      "image": base64Image,
      "debug": debugMode,
    };

    // Send POST request
    final response = await requests.postRequest(
      'virtual_try_on_v2',
      body: payload,
    );

    // Handle the response
    if (response.statusCode == 201) {
      // Debug Mode
      _showMessage('Upload successful: ${response.body}');
      setState(() {
        image_url = response.body;
        isLoading = false;
      });
    } else if (response.statusCode == 200) {
      _showMessage('Upload successful');
      setState(() {
        vton_id = response.body;
      });
      startSendingPostRequests(Duration(seconds: 1));
      //image_url = response.body;
    } else {
      setState(() {
        errorMessage = "Oops! Something went wrong!";
        isLoading = false;
      });
      if (response.body == "TryOn Limit reached") {
        setState(() {
          errorMessage = "Looks like you have exceeded your Virtual Try-On limit";
        });
      }
      _showMessage('Upload failed: ${response.body}');
    }
    /*setState(() {
      isLoading = false;
    });*/
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop(); // Navigate back to the previous screen
          },
        ),
        backgroundColor: Colors.black,
        title: const Text(
          "Virtual Try-On Result",
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        centerTitle: true, // Centers the title
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Center(
          child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: isLoading
                  ? <Widget>[
                      // Loading Screen
                      const SizedBox(height: 20),
                      Text(
                        loadingMessage,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                            fontSize: 20 /*, fontWeight: FontWeight.bold*/),
                      ),
                    ]
                  : errorMessage != null
                      ? <Widget>[
                          Text(
                            errorMessage!,
                            textAlign: TextAlign.center,
                            style: TextStyle(
                              color: const Color.fromARGB(255, 255, 255, 255),
                              fontSize: 18,
                              fontWeight: FontWeight.bold
                            ),
                          )
                        ]
                      : image_url != ""
                          ? <Widget>[
                              Image.network(
                                  image_url) // Display the received image
                            ]
                          : <Widget>[Text('No result to display.')]),
        ),
      ),
    );
  }
}
