import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:frontend/models/commands.dart';
import 'package:frontend/models/data.dart';
import 'package:frontend/models/scheduled_stimulation.dart';
import 'package:logging/logging.dart';

List<Command> _commandsThatRequireDataResponse = [
  Command.startNidaq,
  Command.fetchData,
];

class LokomatFesServerInterface {
  Socket? _socketCommand;
  Socket? _socketData;
  String? _commandAnswer;
  String? _dataAnswer;

  bool _isNidaqConnected = false;
  bool _isRecording = false;
  bool _hasRecorded = false;

  bool _isContinousDataActive = false;
  bool get isContinousDataActive => _isContinousDataActive;
  Data? _continousData;
  Data? get continousData => _continousData;

  List<dynamic>? _schedules;

  bool _isSendingCommand = false;
  bool _isReceivingData = false;

  final _log = Logger('TcpCommunication');

  /// PUBLIC API ///

  ///
  /// Get the singleton instance of the TcpCommunication class.
  static LokomatFesServerInterface get instance => _instance;

  ///
  /// If the communication initialized.
  bool get isInitialized => _socketCommand != null;
  bool get isNidaqConnected => _isNidaqConnected;
  bool get isRecording => _isRecording;
  bool get hasRecorded => _hasRecorded;

  ///
  /// Initialize the communication with the server. If the connection fails,
  /// the function will retry until it succeeds or the number of retries is
  /// reached.
  Future<void> initialize({
    String serverIp = 'localhost',
    int commandPort = 4042,
    int dataPort = 4043,
    int? nbOfRetries,
  }) async {
    if (isInitialized) return;

    _socketCommand = await _connectToServer(
        ipAddress: serverIp,
        port: commandPort,
        nbOfRetries: nbOfRetries,
        hasDataCallback: _listenToCommandAnswer);
    _socketData = await _connectToServer(
        ipAddress: serverIp,
        port: dataPort,
        nbOfRetries: nbOfRetries,
        hasDataCallback: _listenToDataAnswer);
  }

  ///
  /// Send a command to the server. If the command requires parameters, they
  /// can be passed as a list of strings.
  /// Returns true if the command was successfully sent the connexion to
  /// the server is still alive, false otherwise.
  /// If the command was "shutdown" or "quit", the connection is closed. By its
  /// nature, the "shutdown" or "quit" commands will always return false.
  Future<bool> send(Command command, {List<String>? parameters}) async {
    // Check if the command is reserved
    if (command.isReserved) {
      _log.severe('Command $command is reserved and should not be called');
      return false;
    }
    return _send(command, parameters);
  }

  Future<bool> _send(Command command, List<String>? parameters) async {
    if (!isInitialized) {
      _log.severe('Communication not initialized');
      return false;
    }

    await _preSendCommand(command, parameters);

    // Format the command and send the messsage to the server
    String message = "${command.toInt()}:";
    if (parameters != null) {
      message += parameters.join(',');
    }
    await _sendCommand(message);
    _log.info('Sent command: $command');

    // Manage the response from the server
    return await _postSendCommand(command);
  }

  Future<void> _preSendCommand(
      Command command, List<String>? parameters) async {
    // Wait for the server to be ready to receive data in case data are expected
    if (_commandsThatRequireDataResponse.contains(command)) {
      while (_isReceivingData) {
        await Future.delayed(const Duration(milliseconds: 50));
      }
      _isReceivingData = true;
    }

    // Wait for the server to be ready to receive a new command
    while (_isSendingCommand) {
      await Future.delayed(const Duration(milliseconds: 50));
    }
    _isSendingCommand = true;
  }

  Future<void> _sendCommand(String message) async {
    // Construct and send the command
    _commandAnswer = null;
    _socketCommand!.write(message);
    try {
      await _socketCommand!.flush();
    } on SocketException {
      _log.info('Connexion was closed by the server');
      return;
    }
  }

  Future<bool> _postSendCommand(Command command) async {
    switch (command) {
      case Command.quit:
      case Command.shutdown:
        _dispose();
        // Quick exit as the connection now closed
        return false;

      case Command.startNidaq:
        _isNidaqConnected = true;
        _prepareAutomaticDataFetch();
        break;

      case Command.stopNidaq:
        _isNidaqConnected = false;
        _isRecording = false;
        stopAutomaticDataFetch();
        break;

      case Command.startRecording:
        _isRecording = true;
        _hasRecorded = true;
        break;

      case Command.stopRecording:
        _isRecording = false;
        break;

      case Command.availableSchedules:
      case Command.getScheduled:
        _manageFetchedSchedules(command);
        break;

      case Command.fetchData:
        _manageFetchedData();
        break;

      case Command.addSchedule:
      case Command.removeScheduled:
      case Command.startFetchingData:
      case Command.stimulate:
      case Command.plotData:
      case Command.saveData:
        break;
    }

    // Receive acknowledgment from the server
    return await _waitForCommandAnswer();
  }

  Future<bool> _waitForCommandAnswer() async {
    while (_commandAnswer == null) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    final message = _commandAnswer!;
    _log.info('Received command answer: $_commandAnswer');
    _commandAnswer = null;
    _isSendingCommand = false;
    return message == 'OK';
  }

  Future<String> _waitForDataAnswer() async {
    while (_dataAnswer == null) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    final message = _dataAnswer!;
    _log.info('Received data answer');
    _dataAnswer = null;
    _isReceivingData = false;
    return message;
  }

  Future<void> _prepareAutomaticDataFetch() async {
    final answer = jsonDecode(await _waitForDataAnswer());

    _continousData = Data(
        t0: answer['t0'],
        nbNidaqChannels: answer["nidaqNbChannels"],
        nbRehastimChannels: answer["rehastimNbChannels"]);
  }

  Future<bool> startAutomaticDataFetch(
      {required Function() onContinousDataReady}) async {
    if (_continousData == null) {
      _log.severe('Data not initialized');
      return false;
    }

    if (_isContinousDataActive) {
      _log.warning('Automatic data fetch already active');
      return false;
    }

    _continousData!.clear();
    _isContinousDataActive = true;
    await _send(Command.startFetchingData, []);
    _log.info('Automatic data fetch started');

    Timer.periodic(const Duration(milliseconds: 200), (timer) async {
      if (_isNidaqConnected && _isContinousDataActive) {
        await _send(Command.fetchData, []);
        onContinousDataReady();
      } else {
        timer.cancel();
      }
    });
    return true;
  }

  void stopAutomaticDataFetch() {
    _isContinousDataActive = false;
  }

  Future<List<ScheduledStimulation>> fetchScheduledStimulation(
      {required Command command}) async {
    if (command != Command.getScheduled &&
        command != Command.availableSchedules) {
      _log.severe(
          'Command $command should be getScheduled or availableSchedules');
      return [];
    }
    await _send(command, []);
    while (_schedules == null) {
      await Future.delayed(const Duration(milliseconds: 100));
    }
    final schedules = _schedules;
    _schedules = null;
    return [
      for (final schedule in schedules!) ScheduledStimulation.fromJson(schedule)
    ];
  }

  Future<void> _manageFetchedData() async {
    /// This is for online data fetching. We do not mind missing data so just
    /// disregard the error if the data is not received properly

    late final String dataRaw;
    try {
      dataRaw = await _waitForDataAnswer();
    } catch (e) {
      _log.severe('Error while receiving data: $e');
    }

    try {
      _continousData!.appendFromJson(jsonDecode(dataRaw));
    } catch (e) {
      _log.severe('Error while decoding data: $e');
    }

    _log.info('Data received');
  }

  Future<void> _manageFetchedSchedules(Command command) async {
    late final String schedulesRaw;
    try {
      schedulesRaw = await _waitForDataAnswer();
    } catch (e) {
      _log.severe('Error while receiving data: $e');
    }

    _schedules = jsonDecode(schedulesRaw);
    _log.info('Received schedules: $schedulesRaw');
  }

  ///
  /// Close the connection to the server.
  void _dispose() {
    _socketCommand?.close();
    _socketCommand = null;

    _socketData?.close();
    _socketData = null;

    _isSendingCommand = false;
    _isReceivingData = false;

    _continousData = null;
    _isContinousDataActive = false;

    _commandAnswer = null;
    _isNidaqConnected = false;
    _isRecording = false;
    _hasRecorded = false;

    _log.info('Connection closed');
  }

  /// PRIVATE API ///

  ///
  /// Listen to the server's acknowledgment.
  void _listenToCommandAnswer(List<int> data) {
    _commandAnswer = utf8.decode(data);
  }

  void _listenToDataAnswer(List<int> data) {
    final message = utf8.decode(data);
    _dataAnswer = message;
  }

  // Prepare the singleton
  static final LokomatFesServerInterface _instance =
      LokomatFesServerInterface._();
  LokomatFesServerInterface._();

  Future<Socket?> _connectToServer({
    required String ipAddress,
    required int port,
    required int? nbOfRetries,
    required Function(List<int>) hasDataCallback,
  }) async {
    while (nbOfRetries == null || nbOfRetries > 0) {
      try {
        final socket = await Socket.connect(ipAddress, port);
        socket.listen(hasDataCallback);

        return socket;
      } on SocketException {
        final log = Logger('TcpCommunication');
        log.info('Connection failed, retrying...');
        await Future.delayed(const Duration(seconds: 1));
        nbOfRetries = nbOfRetries == null ? null : nbOfRetries - 1;
      }
    }
    return null;
  }
}

class LokomatFesServerInterfaceMock extends LokomatFesServerInterface {
  static LokomatFesServerInterface get newInstance =>
      LokomatFesServerInterfaceMock._();

  static LokomatFesServerInterface get instance => _instance;
  // Prepare the singleton
  static final LokomatFesServerInterface _instance =
      LokomatFesServerInterfaceMock._();
  LokomatFesServerInterfaceMock._() : super._();

  double _mockedT = 0.0;
  bool _isMockInitialized = false;
  @override
  bool get isInitialized => _isMockInitialized;

  @override
  Future<void> initialize(
      {String serverIp = 'localhost',
      int commandPort = 4042,
      int dataPort = 4043,
      int? nbOfRetries}) {
    _isMockInitialized = true;
    return super.initialize(
        serverIp: serverIp,
        commandPort: commandPort,
        dataPort: dataPort,
        nbOfRetries: nbOfRetries);
  }

  @override
  Future<Socket?> _connectToServer({
    required String ipAddress,
    required int port,
    required int? nbOfRetries,
    required Function(List<int>) hasDataCallback,
  }) async {
    return null;
  }

  @override
  Future<void> _sendCommand(String message) async {
    _commandAnswer = 'OK';
    return;
  }

  @override
  Future<void> _prepareAutomaticDataFetch() {
    _mockedT = 0.01;
    _dataAnswer = jsonEncode({
      "t0": 0.1,
      "nidaqNbChannels": 2,
      "rehastimNbChannels": 2,
    });
    return super._prepareAutomaticDataFetch();
  }

  @override
  Future<void> _manageFetchedData() {
    _dataAnswer = jsonEncode({
      "nidaq": {
        "t": [
          [0 + _mockedT, 0.25 + _mockedT, 0.50 + _mockedT, 0.75 + _mockedT],
          [1 + _mockedT, 1.25 + _mockedT, 1.50 + _mockedT, 1.75 + _mockedT],
          [2 + _mockedT, 2.25 + _mockedT, 2.50 + _mockedT, 2.75 + _mockedT]
        ],
        "data": [
          [
            [1.0, 1.1, 1.2, 1.3],
            [-1.0, -1.1, -1.2, -1.3]
          ],
          [
            [1.4, 1.5, 1.6, 1.7],
            [-1.4, -1.5, -1.6, -1.7]
          ],
          [
            [1.8, 1.9, 2.0, 2.1],
            [-1.8, -1.9, -2.0, -2.1]
          ]
        ]
      },
      "rehastim": {
        "data": [
          [
            0.2 + _mockedT,
            2.0,
            [
              {"channel_index": 1, "amplitude": 2},
              {"channel_index": 2, "amplitude": 4}
            ]
          ],
          [
            1.0 + _mockedT,
            3.0,
            [
              {"channel_index": 1, "amplitude": 2},
              {"channel_index": 2, "amplitude": 4}
            ]
          ]
        ]
      },
    });

    _mockedT += 3;
    return super._manageFetchedData();
  }

  @override
  Future<void> _manageFetchedSchedules(Command command) async {
    _schedules = [
      {"name": "schedule1"},
      {"name": "schedule2"},
      {"name": "schedule3"},
    ];
  }

  @override
  void _dispose() {
    _isMockInitialized = false;
    super._dispose();
  }
}
