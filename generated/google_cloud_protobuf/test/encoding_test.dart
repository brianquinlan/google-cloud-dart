// Copyright 2025 Google LLC
//
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
//     https://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

import 'package:google_cloud_protobuf/protobuf.dart';
import 'package:google_cloud_protobuf/src/encoding.dart';
import 'package:test/test.dart';

final class TestEnum extends ProtoEnum {
  static const one = TestEnum('ONE');
  static const two = TestEnum('TWO');

  const TestEnum(super.value);

  factory TestEnum.fromJson(String json) => TestEnum(json);

  @override
  String toString() => 'TestEnum.$value';
}

final class TestMessage extends ProtoMessage {
  static const String fullyQualifiedName = 'testMessage';

  final String? message;

  TestMessage({this.message}) : super(fullyQualifiedName);

  factory TestMessage.fromJson(Map<String, dynamic> json) =>
      TestMessage(message: json['message'] as String?);

  @override
  Object toJson() => {if (message != null) 'message': message};

  @override
  String toString() =>
      'TestMessage(${[if (message != null) 'message=$message'].join(",")})';
}

void main() {
  group('bytes', () {
    test('decode', () {
      final bytes = decodeBytes('AQID')!;
      expect(stringify(bytes), '1,2,3');
    });

    test('encode', () {
      final bytes = Uint8List.fromList([1, 2, 3]);
      expect(encodeBytes(bytes), 'AQID');
    });

    test('decode null', () {
      expect(decodeBytes(null), isNull);
    });

    test('encode null', () {
      expect(encodeBytes(null), isNull);
    });

    test('encode empty', () {
      final bytes = Uint8List.fromList([]);
      expect(encodeBytes(bytes), '');
    });

    test('decode empty', () {
      final bytes = decodeBytes('AQID')!;
      final actual = bytes.map((item) => '$item').join(',');
      expect(actual, '1,2,3');
    });

    test('decode simple', () {
      final bytes = decodeBytes('bG9yZW0gaXBzdW0=')!;
      final actual = bytes.map((item) => '$item').join(',');
      // "lorem ipsum"
      expect(actual, '108,111,114,101,109,32,105,112,115,117,109');
    });

    test('decode complex', () {
      final bytes = decodeBytes('YWJjMTIzIT8kKiYoKSctPUB+')!;
      final actual = bytes.map((item) => '$item').join(',');
      expect(actual, '97,98,99,49,50,51,33,63,36,42,38,40,41,39,45,61,64,126');
    });
  });

  group('double', () {
    test('decode', () {
      expect(decodeDouble(1), 1);
      expect(decodeDouble(1.1), 1.1);
    });

    test('encode', () {
      expect(encodeDouble(1), 1);
      expect(encodeDouble(1.1), 1.1);
    });

    test('decode null', () {
      expect(decodeDouble(null), isNull);
    });

    test('encode null', () {
      expect(encodeDouble(null), isNull);
    });

    test('decode special strings', () {
      expect(decodeDouble('NaN'), isNaN);
      expect(decodeDouble('Infinity'), double.infinity);
      expect(decodeDouble('-Infinity'), double.negativeInfinity);
    });

    test('encode special strings', () {
      expect(encodeDouble(double.nan), 'NaN');
      expect(encodeDouble(double.infinity), 'Infinity');
      expect(encodeDouble(double.negativeInfinity), '-Infinity');
    });

    test('decode invalid strings', () {
      expect(() => decodeDouble('1.0'), throwsFormatException);
    });
  });

  group('int64', () {
    test('decode', () {
      expect(decodeInt64('1'), 1);
      expect(decodeInt64(1), 1);
    });

    test('encode', () {
      expect(encodeInt64(1), '1');
    });

    test('decode null', () {
      expect(decodeInt64(null), isNull);
    });

    test('encode null', () {
      expect(encodeInt64(null), isNull);
    });
  });

  group('enum', () {
    test('decode', () {
      final actual = decodeEnum(
        const TestEnum('ONE').toJson(),
        TestEnum.fromJson,
      );
      expect(actual, TestEnum.one);
    });

    test('encode', () {
      expect(TestEnum.one.toJson(), 'ONE');
    });

    test('decode null', () {
      expect(decodeEnum(null, TestEnum.fromJson), isNull);
    });
  });

  group('message', () {
    test('decode', () {
      final actual = decode({'message': 'Hello World'}, TestMessage.fromJson);
      expect(
        actual,
        isA<TestMessage>().having((o) => o.message, 'message', 'Hello World'),
      );
    });

    test('encode', () {
      expect(TestMessage(message: 'Hello World').toJson(), {
        'message': 'Hello World',
      });
    });

    test('decode null', () {
      expect(decode(null, TestMessage.fromJson), isNull);
    });
  });

  group('list', () {
    test('decode enum', () {
      expect(decodeListEnum(encodeList([TestEnum.one]), TestEnum.fromJson), [
        TestEnum.one,
      ]);
    });

    test('encode enum', () {
      expect(encodeList([TestEnum.one]), ['ONE']);
    });

    test('decode bytes', () {
      final actual = decodeListBytes(
        encodeListBytes([
          Uint8List.fromList([1]),
          Uint8List.fromList([1, 2]),
          Uint8List.fromList([1, 2, 3]),
        ]),
      );

      expect(actual, hasLength(3));

      expect(stringify(actual![0]), '1');
      expect(stringify(actual[1]), '1,2');
      expect(stringify(actual[2]), '1,2,3');
    });

    test('encode bytes', () {
      expect(
        encodeListBytes([
          Uint8List.fromList([1, 2, 3]),
        ]),
        ['AQID'],
      );
    });

    test('decode double', () {
      final actual = decodeListDouble(['NaN', 'Infinity', '-Infinity', 1.0, 1]);

      expect(actual, [
        isNaN,
        ...<double>[double.infinity, double.negativeInfinity, 1.0, 1],
      ]);
    });

    test('decode message', () {
      final actual = decodeListMessage(
        encodeList([TestMessage(message: 'Hello World')]),
        TestMessage.fromJson,
      );
      expect(actual!, hasLength(1));
      expect(
        actual[0],
        isA<TestMessage>().having((o) => o.message, 'message', 'Hello World'),
      );
    });

    test('encode message', () {
      expect(encodeList([TestMessage(message: 'Hello World')]), [
        {'message': 'Hello World'},
      ]);
    });

    test('decode null', () {
      expect(decodeListDouble(null), isNull);
      expect(decodeListEnum(null, TestEnum.fromJson), isNull);
      expect(decodeListMessage(null, TestMessage.fromJson), isNull);
      expect(decodeListBytes(null), isNull);
    });

    test('encode null', () {
      expect(encodeList(null), isNull);
      expect(encodeListBytes(null), isNull);
    });
  });

  group('map', () {
    test('decode enum', () {
      final actual = decodeMapEnum<String, TestEnum>(
        encodeMap({
          'one': TestEnum.one,
          'two': TestEnum.two,
          'three': TestEnum.one,
        }),
        TestEnum.fromJson,
      );

      expect(actual, isMap);
      expect(actual, hasLength(3));
      expect(actual, containsPair('one', TestEnum.one));
      expect(actual, containsPair('two', TestEnum.two));
      expect(actual, containsPair('three', TestEnum.one));
    });

    test('encode enum', () {
      expect(encodeMap({'one': TestEnum.one}), {'one': 'ONE'});
    });

    test('decode bytes', () {
      final actual = decodeMapBytes<int>(
        encodeMapBytes({
          1: Uint8List.fromList([1, 2]),
          2: Uint8List.fromList([1, 2, 3, 4]),
        }),
      );
      expect(actual, isMap);
      expect(stringify(actual![1]!), '1,2');
    });

    test('encode bytes', () {
      expect(
        encodeMapBytes({
          1: Uint8List.fromList([1, 2, 3]),
        }),
        {1: 'AQID'},
      );
    });

    test('decode message', () {
      final actual = decodeMapMessage<String, TestMessage>(
        encodeMap({
          'one': TestMessage(message: 'Hello'),
          'two': TestMessage(message: 'World'),
        }),
        TestMessage.fromJson,
      );
      expect(actual, isMap);
      expect(actual, hasLength(2));
      expect(
        actual,
        containsPair(
          'one',
          isA<TestMessage>().having((o) => o.message, 'message', 'Hello'),
        ),
      );
      expect(
        actual,
        containsPair(
          'two',
          isA<TestMessage>().having((o) => o.message, 'message', 'World'),
        ),
      );
    });

    test('encode message', () {
      expect(encodeMap({'one': TestMessage(message: 'Hello')}), {
        'one': {'message': 'Hello'},
      });
    });

    test('decode null', () {
      expect(decodeMapEnum<String, TestEnum>(null, TestEnum.fromJson), isNull);
      expect(decodeMapBytes<int>(null), isNull);
      expect(
        decodeMapMessage<String, TestMessage>(null, TestMessage.fromJson),
        isNull,
      );
    });

    test('encode null', () {
      expect(encodeMap<String>(null), isNull);
      expect(encodeMapBytes<int>(null), isNull);
    });
  });
}

String stringify(Uint8List list) => list.map((i) => '$i').join(',');
