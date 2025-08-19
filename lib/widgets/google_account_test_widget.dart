import 'package:flutter/material.dart';
import '../services/google_play_service.dart';

class GoogleAccountTestWidget extends StatefulWidget {
  const GoogleAccountTestWidget({super.key});

  @override
  State<GoogleAccountTestWidget> createState() =>
      _GoogleAccountTestWidgetState();
}

class _GoogleAccountTestWidgetState extends State<GoogleAccountTestWidget> {
  Map<String, dynamic>? _testResults;
  bool _isLoading = false;
  String? _error;

  Future<void> _runTest() async {
    setState(() {
      _isLoading = true;
      _error = null;
      _testResults = null;
    });

    try {
      final results = await GooglePlayService.testAccountRetrieval();
      setState(() {
        _testResults = results;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  Future<void> _checkStatus() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final status = await GooglePlayService.getAccountStatus();
      setState(() {
        _testResults = status;
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _isLoading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Google Account Test'),
        backgroundColor: Colors.blue,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Google Account Retrieval Test',
                      style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'This widget helps test the Google account ID retrieval functionality. '
                      'Use it to debug account access issues.',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _runTest,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Run Account Test'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton(
                    onPressed: _isLoading ? null : _checkStatus,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                    ),
                    child: const Text('Check Status'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_isLoading)
              const Center(
                child: CircularProgressIndicator(),
              )
            else if (_error != null)
              Card(
                color: Colors.red.shade50,
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Error',
                        style: TextStyle(
                          color: Colors.red,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _error!,
                        style: const TextStyle(color: Colors.red),
                      ),
                    ],
                  ),
                ),
              )
            else if (_testResults != null)
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Test Results',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 16),
                      _buildResultRow('Success',
                          _testResults!['success']?.toString() ?? 'N/A'),
                      _buildResultRow('Account ID',
                          _testResults!['accountId']?.toString() ?? 'N/A'),
                      _buildResultRow('Account Type',
                          _testResults!['accountType']?.toString() ?? 'N/A'),
                      _buildResultRow('Is Valid',
                          _testResults!['isValid']?.toString() ?? 'N/A'),
                      if (_testResults!['duration'] != null)
                        _buildResultRow(
                            'Duration', '${_testResults!['duration']}ms'),
                      if (_testResults!['permissionStatus'] != null)
                        _buildResultRow(
                            'Permission Status',
                            _testResults!['permissionStatus']?.toString() ??
                                'N/A'),
                      if (_testResults!['canProceedWithPurchase'] != null)
                        _buildResultRow(
                            'Can Purchase',
                            _testResults!['canProceedWithPurchase']
                                    ?.toString() ??
                                'N/A'),
                      if (_testResults!['recommendation'] != null)
                        _buildResultRow(
                            'Recommendation',
                            _testResults!['recommendation']?.toString() ??
                                'N/A'),
                      if (_testResults!['timestamp'] != null)
                        _buildResultRow('Timestamp',
                            _testResults!['timestamp']?.toString() ?? 'N/A'),
                    ],
                  ),
                ),
              ),
            const Spacer(),
            Card(
              color: Colors.orange.shade50,
              child: const Padding(
                padding: EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Troubleshooting Tips',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Colors.orange,
                      ),
                    ),
                    SizedBox(height: 8),
                    Text(
                      '• If you get "PERMISSION_PENDING", grant account access when prompted\n'
                      '• If you get "NO_GOOGLE_ACCOUNT", add a Google account in device settings\n'
                      '• If you get "DEVICE_..." ID, the app will work but with limited features\n'
                      '• Check that Google Play Services is up to date',
                      style: TextStyle(fontSize: 14),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(
              '$label:',
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontFamily: 'monospace'),
            ),
          ),
        ],
      ),
    );
  }
}






