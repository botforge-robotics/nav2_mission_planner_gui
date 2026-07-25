import 'package:flutter_test/flutter_test.dart';
import 'package:ros2_api/ros2_api.dart';
import 'package:std_msgs/msg.dart';

final ros2 = Ros2(url: 'ws://localhost:9090');
void main() {
  group('Topic Publisher Tests', () {
    setUp(() async {
      ros2.connect();
      await Future.delayed(const Duration(seconds: 2));
    });

    tearDown(() async {
      await ros2.close();
      await Future.delayed(const Duration(seconds: 1));
    });

    test('Publishes messages to /chatter topic', () async {
      const testMessageCount = 5;
      var messagesPublished = 0;

      final publisher = Publisher<StringMessage>(
        name: '/chatter',
        type: StringMessage().fullType,
        ros2: ros2,
      );

      for (int i = 0; i < testMessageCount; i++) {
        await Future.delayed(const Duration(milliseconds: 500));
        publisher.publish(StringMessage(data: 'Test message $i'));
        messagesPublished++;
      }

      expect(messagesPublished, testMessageCount);
      await publisher.shutdown();
    }, timeout: const Timeout(Duration(seconds: 10)));
  });
}
