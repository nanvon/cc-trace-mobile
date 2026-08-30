import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// 带像素容差的 golden 本地比较器。
///
/// 界面文字用 `.SF Pro Text` / `PingFang SC` 系统字体，抗锯齿输出随 macOS
/// 版本与 CI Runner 镜像漂移，默认零容差会把亚可见的边缘噪声（曾出现
/// 0.36% / 1213px）判成失败。真正的布局破坏（缺一行、错位）是数个百分点的
/// 量级，远超这里的阈值，仍会走默认比对抛错。
class _TolerantLocalFileComparator extends LocalFileComparator {
  _TolerantLocalFileComparator(super.testFile);

  /// 单通道差不超过该值视为同一像素；实测环境噪声在每通道 ±2~11。
  static const int _channelEpsilon = 8;

  /// 差异像素占比超过该值（0.5%）才算失败。
  static const double _maxDiffRate = 0.005;

  @override
  Future<bool> compare(Uint8List imageBytes, Uri golden) async {
    if (await _withinTolerance(imageBytes, golden)) {
      return true;
    }
    // 超出容差时退回默认比对，保留标准错误信息和 failures 下的差异图。
    return super.compare(imageBytes, golden);
  }

  Future<bool> _withinTolerance(Uint8List imageBytes, Uri golden) async {
    final Uint8List goldenBytes = Uint8List.fromList(
      await getGoldenBytes(golden),
    );
    final ui.Image rendered = await _decode(imageBytes);
    final ui.Image reference = await _decode(goldenBytes);
    try {
      if (rendered.width != reference.width ||
          rendered.height != reference.height) {
        return false;
      }
      final ByteData renderedBytes = (await rendered.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      final ByteData referenceBytes = (await reference.toByteData(
        format: ui.ImageByteFormat.rawRgba,
      ))!;
      var diffCount = 0;
      final int total = rendered.width * rendered.height;
      for (var i = 0; i < renderedBytes.lengthInBytes; i += 4) {
        var same = true;
        for (var c = 0; c < 4; c++) {
          if ((renderedBytes.getUint8(i + c) - referenceBytes.getUint8(i + c))
                  .abs() >
              _channelEpsilon) {
            same = false;
            break;
          }
        }
        if (!same) {
          diffCount++;
        }
      }
      return diffCount <= total * _maxDiffRate;
    } finally {
      rendered.dispose();
      reference.dispose();
    }
  }

  Future<ui.Image> _decode(Uint8List bytes) async {
    final ui.Codec codec = await ui.instantiateImageCodec(bytes);
    final ui.FrameInfo frame = await codec.getNextFrame();
    return frame.image;
  }
}

Future<void> testExecutable(FutureOr<void> Function() testMain) async {
  final previous = goldenFileComparator;
  if (previous is LocalFileComparator) {
    // 构造函数需要一个测试文件路径来推出基目录，用基目录下的本文件名重建，
    // 得到的 basedir 与默认比较器一致。
    goldenFileComparator = _TolerantLocalFileComparator(
      previous.basedir.resolve('flutter_test_config.dart'),
    );
  }
  await testMain();
}
