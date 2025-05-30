import 'dart:convert';
import 'dart:developer';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:file_picker/file_picker.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';

// Global variable to store the prompt
String prompt = "";

void main() async {
  await dotenv.load(fileName: ".env");
  await Supabase.initialize(
    url: dotenv.env['SUPABASE_URL']!,
    anonKey: dotenv.env['SUPABASE_ANON_KEY']!,
  );
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Invoice to PO',
      theme: ThemeData(
        primarySwatch: Colors.blue,
        visualDensity: VisualDensity.adaptivePlatformDensity,
        fontFamily: 'Roboto',
      ),
      home: const MyHomePage(),
      debugShowCheckedModeBanner: false,
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  Uint8List? _fileBytes;
  String? _fileName;
  Map<String, dynamic>? extractedData;
  bool _isUploading = false;
  bool _isEditing = false;
  String _conversionType = "Invoice to PO";
  final Map<String, TextEditingController> _controllers = {};
  final List<List<TextEditingController>> _tableControllers = [];
  List<String> _columnHeaders = [];

  @override
  void initState() {
    super.initState();
    // Initialize controllers for each field
    _controllers['po_number'] = TextEditingController();
    _controllers['delivery_date'] = TextEditingController();
    _controllers['supplier_name'] = TextEditingController();
    _controllers['supplier_location'] = TextEditingController();
    _controllers['ship_to_name'] = TextEditingController();
    _controllers['ship_to_address'] = TextEditingController();
    _controllers['total_amount'] = TextEditingController();
  }

  // Function to pick a file from the device
  Future<void> _pickFile() async {
    try {
      FilePickerResult? result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'png', 'jpeg'],
      );

      if (result != null) {
        setState(() {
          _fileBytes = result.files.first.bytes;
          _fileName = result.files.first.name;
        });
      }
    } catch (e) {
      log("Error picking file: $e");
    }
  }

  // Function to process the selected file
  Future<void> _processFile() async {
    try {
      if (_conversionType == "Invoice to PO") {
        await _invoiceToPo();
      } else {
        await _poToInvoice();
      }
    } catch (e) {
      log("Error processing file: $e");
    }
  }

  // Function to convert invoice to PO
  Future<void> _invoiceToPo() async {
    try {
      prompt =
          "Extract structured details from the invoice image and return only a JSON response. "
          "Ensure the JSON follows this format exactly: "
          "{ "
          "   'po_number': '...', "
          "   'delivery_date': '...', "
          "   'supplier_details': {'name': '...', 'location': '...'}, "
          "   'ship_to': {'name': '...', 'address': '...'}, "
          "   'items': [ "
          "       {'item_name': '...', 'uom': '...', 'quantity': ..., 'unit_price': ..., 'total': ...} "
          "   ], "
          "   'total_amount': ... "
          "} "
          "If any field is missing, use 'n/a' as the value. "
          "Do not include explanations, introductions, or anything other than valid JSON output.";
      await _uploadFile();
    } catch (e) {
      log("Error converting invoice to PO: $e");
    }
  }

  // Function to convert PO to invoice
  Future<void> _poToInvoice() async {
    try {
      prompt =
          "Extract text from this purchase order and format it as an invoice.";
      await _uploadFile();
    } catch (e) {
      log("Error converting PO to invoice: $e");
    }
  }

  // Function to upload the file to the API and get the response
  Future<void> _uploadFile() async {
    String? apiKey;
    try {
      apiKey = dotenv.env['OPENAI_API_KEY'];
      if (apiKey == null || apiKey.isEmpty) {
        log("Error: API key is missing!");
        return;
      }
    } catch (e) {
      log("Error loading API key: $e");
      return;
    }

    if (_fileBytes == null) {
      log("Error: No file selected.");
      return;
    }

    setState(() => _isUploading = true);

    String base64Image = base64Encode(_fileBytes!);
    try {
      var response = await http.post(
        Uri.parse("https://api.openai.com/v1/chat/completions"),
        headers: {
          "Authorization": "Bearer $apiKey",
          "Content-Type": "application/json",
        },
        body: jsonEncode({
          "model": "gpt-4o",
          "messages": [
            {"role": "system", "content": prompt},
            {
              "role": "user",
              "content": [
                {
                  "type": "text",
                  "text": "Extract and return structured JSON data."
                },
                {
                  "type": "image_url",
                  "image_url": {"url": "data:image/png;base64,$base64Image"}
                }
              ],
            }
          ]
        }),
      );

      // Log the raw response body
      log("Response body: ${response.body}");

      if (response.statusCode == 200) {
        // Clean the response body
        String cleanResponse =
            response.body.replaceAll(RegExp(r'```json|```'), '');

        try {
          var data = jsonDecode(cleanResponse);
          setState(() {
            extractedData =
                jsonDecode(data["choices"][0]["message"]["content"].trim());

            // Dynamically extract column headers
            if (extractedData!['items'].isNotEmpty) {
              _columnHeaders = extractedData!['items'][0].keys.toList();
              log("Column headers: $_columnHeaders"); // Debug
            }

            // Load data into controllers for editing
            _controllers['po_number']?.text =
                extractedData?['po_number'] ?? 'n/a';
            _controllers['delivery_date']?.text =
                extractedData?['delivery_date'] ?? 'n/a';
            _controllers['supplier_name']?.text =
                extractedData?['supplier_details']['name'] ?? 'n/a';
            _controllers['supplier_location']?.text =
                extractedData?['supplier_details']['location'] ?? 'n/a';
            _controllers['ship_to_name']?.text =
                extractedData?['ship_to']['name'] ?? 'n/a';
            _controllers['ship_to_address']?.text =
                extractedData?['ship_to']['address'] ?? 'n/a';
            _controllers['total_amount']?.text =
                extractedData?['total_amount'].toString() ?? 'n/a';

            // Initialize table controllers
            _tableControllers.clear();
            for (var item in extractedData!['items']) {
              var rowControllers = _columnHeaders.map((header) {
                return TextEditingController(text: item[header].toString());
              }).toList();
              _tableControllers.add(rowControllers);
            }
          });
        } catch (e) {
          log("Error parsing JSON response: $e");
        }
      } else {
        log("Error: Received status code ${response.statusCode}");
      }
    } catch (e) {
      log("Error uploading file: $e");
    }

    setState(() => _isUploading = false);
  }

  // Function to toggle edit mode
  void _toggleEditMode() {
    setState(() {
      _isEditing = !_isEditing;
      if (!_isEditing) {
        // Save edited data back to extractedData
        extractedData?['po_number'] = _controllers['po_number']?.text;
        extractedData?['delivery_date'] = _controllers['delivery_date']?.text;
        extractedData?['supplier_details']['name'] =
            _controllers['supplier_name']?.text;
        extractedData?['supplier_details']['location'] =
            _controllers['supplier_location']?.text;
        extractedData?['ship_to']['name'] = _controllers['ship_to_name']?.text;
        extractedData?['ship_to']['address'] =
            _controllers['ship_to_address']?.text;
        extractedData?['total_amount'] =
            double.tryParse(_controllers['total_amount']?.text ?? '0');

        // Save table data
        for (int i = 0; i < _tableControllers.length; i++) {
          for (int j = 0; j < _columnHeaders.length; j++) {
            extractedData?['items'][i][_columnHeaders[j]] =
                _tableControllers[i][j].text;
          }
        }
      }
    });
  }

  // Function to save the extracted data to the database
  Future<void> _saveToDb() async {
    if (extractedData == null) return;

    try {
      final supabase = Supabase.instance.client;
      final response = await supabase.from('PO details').insert([
        {
          'PO_id': extractedData!['po_number'],
          'supplier_details': {
            'name': extractedData!['supplier_details']['name'],
            'location': extractedData!['supplier_details']['location'],
            'delivery_date': extractedData!['delivery_date'],
          },
          'ship_to': {
            'name': extractedData!['ship_to']['name'],
            'address': extractedData!['ship_to']['address'],
          },
          'items': extractedData!['items'],
          'total_amount': extractedData!['total_amount'],
        }
      ]).select('PO_id');

      if (response.isNotEmpty) {
        log("Invoice Saved! PO Id: ${response[0]['PO_id']}");
      }
    } catch (e) {
      log("Error saving to DB: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Invoice <-> Purchase Order Converter"),
        actions: [
          IconButton(
            icon: Icon(_isEditing ? Icons.save : Icons.edit),
            onPressed: _toggleEditMode,
          ),
        ],
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                DropdownButton<String>(
                  value: _conversionType,
                  onChanged: (String? newValue) {
                    setState(() => _conversionType = newValue!);
                  },
                  items: ["Invoice to PO", "PO to Invoice"].map((String value) {
                    return DropdownMenuItem<String>(
                      value: value,
                      child: Text(value),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                if (_fileName != null)
                  Text('Selected File: $_fileName',
                      style: const TextStyle(fontSize: 16)),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  icon: const Icon(Icons.upload_file),
                  label: const Text("Select File"),
                  onPressed: _pickFile,
                ),
                const SizedBox(height: 20),
                if (_fileBytes != null)
                  _isUploading
                      ? const CircularProgressIndicator()
                      : ElevatedButton.icon(
                          icon: const Icon(Icons.cloud_upload),
                          label: const Text("Upload & Process"),
                          onPressed: _processFile,
                        ),
                const SizedBox(height: 20),
                if (extractedData != null)
                  Column(
                    children: [
                      TextField(
                        controller: _controllers['po_number'],
                        decoration: InputDecoration(labelText: "PO Number"),
                        readOnly: !_isEditing,
                      ),
                      TextField(
                        controller: _controllers['delivery_date'],
                        decoration: InputDecoration(labelText: "Delivery Date"),
                        readOnly: !_isEditing,
                      ),
                      const SizedBox(height: 10),
                      const Text("Supplier Details:",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      TextField(
                        controller: _controllers['supplier_name'],
                        decoration: InputDecoration(labelText: "Name"),
                        readOnly: !_isEditing,
                      ),
                      TextField(
                        controller: _controllers['supplier_location'],
                        decoration: InputDecoration(labelText: "Location"),
                        readOnly: !_isEditing,
                      ),
                      const SizedBox(height: 20),
                      const Text("Ship To:",
                          style: TextStyle(fontWeight: FontWeight.bold)),
                      TextField(
                        controller: _controllers['ship_to_name'],
                        decoration: InputDecoration(labelText: "Name"),
                        readOnly: !_isEditing,
                      ),
                      TextField(
                        controller: _controllers['ship_to_address'],
                        decoration: InputDecoration(labelText: "Address"),
                        readOnly: !_isEditing,
                      ),
                      const SizedBox(height: 20),
                      const Text("Items:",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      DataTable(
                        columns: _columnHeaders.map((header) {
                          return DataColumn(
                            label: Text(header,
                                style: TextStyle(fontWeight: FontWeight.bold)),
                          );
                        }).toList(),
                        rows: List.generate(_tableControllers.length, (index) {
                          return DataRow(
                            cells: _columnHeaders.map((header) {
                              return DataCell(TextField(
                                controller: _tableControllers[index]
                                    [_columnHeaders.indexOf(header)],
                                readOnly: !_isEditing,
                              ));
                            }).toList(),
                          );
                        }),
                      ),
                      const SizedBox(height: 20),
                      const Text("Total Amount:",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold)),
                      TextField(
                        controller: _controllers['total_amount'],
                        decoration: InputDecoration(labelText: "Total Amount"),
                        readOnly: !_isEditing,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 20),
                      ElevatedButton.icon(
                        icon: const Icon(Icons.save),
                        label: const Text("Save to DB"),
                        onPressed: _saveToDb,
                      ),
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
