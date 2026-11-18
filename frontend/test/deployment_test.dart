import 'package:flutter_test/flutter_test.dart';

import 'package:constructing_mobile/core/config/deployment.dart';

void main() {
  group('DeploymentConfig - estrategia de producto', () {
    test('el desarrollo es mobile-first', () {
      expect(DeploymentConfig.mobileFirstDevelopment, isTrue);
    });

    test('el producto final es una URL web, no una app descargable', () {
      expect(DeploymentConfig.deployAsWebUrl, isTrue);
      expect(DeploymentConfig.skipAppStores, isTrue);
    });
  });
}