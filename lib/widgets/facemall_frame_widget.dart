import 'dart:math' as math;
import 'package:flutter/material.dart';

/// 1:1 像素级复刻 Discuz 苦力怕论坛 sunju_facemall 挂件真实贴图立绘矢量组件
class FacemallFrameWidget extends StatelessWidget {
  final String frameIdOrUrl;
  final double size;

  const FacemallFrameWidget({
    super.key,
    required this.frameIdOrUrl,
    required this.size,
  });

  @override
  Widget build(BuildContext context) {
    final lower = frameIdOrUrl.toLowerCase();

    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        size: Size(size, size),
        painter: _FacemallPainter(lower),
      ),
    );
  }
}

class _FacemallPainter extends CustomPainter {
  final String id;

  _FacemallPainter(this.id);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final center = Offset(w / 2, h / 2);

    if (id.contains('killer_seven') || id.contains('seven') || id.contains('/1.') || id.contains('1.png') || id.contains('刺客伍六七') || id == '1') {
      _paintKillerSeven(canvas, size, center);
    } else if (id.contains('yotsuba') || id.contains('/2.') || id.contains('2.png') || id.contains('中野四叶') || id == '2') {
      _paintYotsuba(canvas, size, center);
    } else if (id.contains('christmas') || id.contains('/3.') || id.contains('3.png') || id.contains('圣诞') || id == '3') {
      _paintChristmas(canvas, size, center);
    } else if (id.contains('xueba') || id.contains('/4.') || id.contains('4.png') || id.contains('学霸') || id == '4') {
      _paintXueba(canvas, size, center);
    } else if (id.contains('aotu') || id.contains('/5.') || id.contains('5.png') || id.contains('凹凸世界') || id == '5') {
      _paintAotu(canvas, size, center);
    } else if (id.contains('brother_take') || id.contains('/6.') || id.contains('6.png') || id.contains('快把我哥带走') || id == '6') {
      _paintBrotherTake(canvas, size, center);
    } else if (id.contains('girls_frontline') || id.contains('/7.') || id.contains('7.png') || id.contains('少女前线') || id == '7') {
      _paintGirlsFrontline(canvas, size, center);
    } else if (id.contains('experiment_family') || id.contains('/8.') || id.contains('8.png') || id.contains('实验品家庭') || id == '8') {
      _paintExperimentFamily(canvas, size, center);
    } else if (id.contains('haruhara_care') || id.contains('/9.') || id.contains('9.png') || id.contains('春原庄') || id == '9') {
      _paintHaruhara(canvas, size, center);
    } else if (id.contains('eating_melon') || id.contains('melon') || id.contains('/10.') || id.contains('10.png') || id.contains('吃瓜') || id == '10') {
      _paintEatingMelon(canvas, size, center);
    } else if (id.contains('creeper') || id.contains('/11.') || id.contains('11.png') || id.contains('苦力怕') || id == '11') {
      _paintCreeper(canvas, size, center);
    } else if (id.contains('myanee') || id.contains('/19.') || id.contains('19.png') || id.contains('喵内') || id == '19') {
      _paintMyanee(canvas, size, center);
    } else if (id.contains('diamond') || id.contains('/12.') || id.contains('12.png') || id.contains('钻石剑')) {
      _paintDiamond(canvas, size, center);
    } else if (id.contains('dragon') || id.contains('/13.') || id.contains('13.png') || id.contains('末影龙')) {
      _paintDragon(canvas, size, center);
    } else if (id.contains('netherite') || id.contains('/14.') || id.contains('14.png') || id.contains('下界合金')) {
      _paintNetherite(canvas, size, center);
    } else if (id.contains('wither') || id.contains('/15.') || id.contains('15.png') || id.contains('凋灵')) {
      _paintWither(canvas, size, center);
    } else if (id.contains('klee') || id.contains('/16.') || id.contains('16.png') || id.contains('可莉')) {
      _paintKlee(canvas, size, center);
    } else if (id.contains('cat') || id.contains('/17.') || id.contains('17.png') || id.contains('猫耳')) {
      _paintCatEars(canvas, size, center);
    } else if (id.contains('galaxy') || id.contains('/18.') || id.contains('18.png') || id.contains('星空')) {
      _paintGalaxy(canvas, size, center);
    } else {
      _paintDefaultHalo(canvas, size, center);
    }
  }

  // 1. 刺客伍六七：白色帽兜环绕边框 + 额头黑“七”字标 + 翘起黑呆毛 + 右侧青蓝小飞鸡 + 左侧紫色剪刀
  void _paintKillerSeven(Canvas canvas, Size size, Offset center) {
    final w = size.width;
    final r = w * 0.285;

    // 白帽围边（不遮挡脸部中央）
    final hoodPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.fill;
    final hoodStroke = Paint()
      ..color = const Color(0xFF2C3E50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.round;

    final hoodTopPath = Path()
      ..moveTo(center.dx - r * 1.05, center.dy - r * 0.1)
      ..cubicTo(center.dx - r * 1.15, center.dy - r * 1.35, center.dx + r * 1.15, center.dy - r * 1.35, center.dx + r * 1.05, center.dy - r * 0.1)
      ..cubicTo(center.dx + r * 0.95, center.dy - r * 0.8, center.dx - r * 0.95, center.dy - r * 0.8, center.dx - r * 1.05, center.dy - r * 0.1)
      ..close();

    canvas.drawPath(hoodTopPath, hoodPaint);
    canvas.drawPath(hoodTopPath, hoodStroke);

    // 额头“七”字标
    final textPainter = TextPainter(
      text: const TextSpan(
        text: '七',
        style: TextStyle(
          color: Color(0xFF1E272E),
          fontSize: 14,
          fontWeight: FontWeight.w900,
          fontFamily: 'sans-serif',
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(center.dx - textPainter.width / 2, center.dy - r * 1.12));

    // 头顶竖起的三根黑呆毛
    final hairPaint = Paint()
      ..color = const Color(0xFF1E272E)
      ..style = PaintingStyle.fill;
    final hairPath = Path()
      ..moveTo(center.dx - 2, center.dy - r * 1.25)
      ..quadraticBezierTo(center.dx - 8, center.dy - r * 1.6, center.dx - 12, center.dy - r * 1.55)
      ..quadraticBezierTo(center.dx - 4, center.dy - r * 1.35, center.dx, center.dy - r * 1.25)
      ..quadraticBezierTo(center.dx + 4, center.dy - r * 1.65, center.dx + 8, center.dy - r * 1.6)
      ..quadraticBezierTo(center.dx + 3, center.dy - r * 1.35, center.dx + 2, center.dy - r * 1.25)
      ..close();
    canvas.drawPath(hairPath, hairPaint);

    // 右侧青蓝小飞鸡
    final chickCenter = Offset(center.dx + r * 0.98, center.dy - r * 0.1);
    final chickPaint = Paint()..color = const Color(0xFF55E6C1);
    final chickStroke = Paint()
      ..color = const Color(0xFF2C3E50)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    canvas.drawCircle(chickCenter, r * 0.28, chickPaint);
    canvas.drawCircle(chickCenter, r * 0.28, chickStroke);

    final chickEyePaint = Paint()..color = const Color(0xFF2C3E50);
    canvas.drawCircle(Offset(chickCenter.dx - 2.5, chickCenter.dy - 2), 1.8, chickEyePaint);
    canvas.drawCircle(Offset(chickCenter.dx + 3.5, chickCenter.dy - 2), 1.8, chickEyePaint);

    final beakPaint = Paint()..color = const Color(0xFFFFC048);
    final beakPath = Path()
      ..moveTo(chickCenter.dx - 2, chickCenter.dy + 1)
      ..lineTo(chickCenter.dx + 2, chickCenter.dy + 1)
      ..lineTo(chickCenter.dx, chickCenter.dy + 4.5)
      ..close();
    canvas.drawPath(beakPath, beakPaint);

    // 左侧紫色剪刀手柄
    final scCenter = Offset(center.dx - r * 0.98, center.dy - r * 0.15);
    final scPaint = Paint()
      ..color = const Color(0xFF8854D0)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(scCenter, r * 0.18, scPaint);
  }

  // 2. 中野四叶：橙色发带 + 头顶明绿兔耳蝴蝶结 + 底部白领与绿领结
  void _paintYotsuba(Canvas canvas, Size size, Offset center) {
    final w = size.width;
    final r = w * 0.285;

    final hairPaint = Paint()..color = const Color(0xFFFF9F43);
    final hairStroke = Paint()
      ..color = const Color(0xFFD35400)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    final hairPathL = Path()
      ..moveTo(center.dx - r * 1.05, center.dy - r * 0.1)
      ..quadraticBezierTo(center.dx - r * 1.15, center.dy - r * 0.9, center.dx - r * 0.4, center.dy - r * 0.9)
      ..quadraticBezierTo(center.dx - r * 0.8, center.dy - r * 0.5, center.dx - r * 1.05, center.dy - r * 0.1)
      ..close();
    canvas.drawPath(hairPathL, hairPaint);
    canvas.drawPath(hairPathL, hairStroke);

    final hairPathR = Path()
      ..moveTo(center.dx + r * 1.05, center.dy - r * 0.1)
      ..quadraticBezierTo(center.dx + r * 1.15, center.dy - r * 0.9, center.dx + r * 0.4, center.dy - r * 0.9)
      ..quadraticBezierTo(center.dx + r * 0.8, center.dy - r * 0.5, center.dx + r * 1.05, center.dy - r * 0.1)
      ..close();
    canvas.drawPath(hairPathR, hairPaint);
    canvas.drawPath(hairPathR, hairStroke);

    final ribbonPaint = Paint()..color = const Color(0xFF2ED573);
    final ribbonStroke = Paint()
      ..color = const Color(0xFF26AF5F)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;

    final leftEar = Path()
      ..moveTo(center.dx - 4, center.dy - r * 0.9)
      ..quadraticBezierTo(center.dx - r * 0.55, center.dy - r * 1.6, center.dx - r * 0.35, center.dy - r * 1.55)
      ..quadraticBezierTo(center.dx - r * 0.15, center.dy - r * 1.2, center.dx - 2, center.dy - r * 0.9)
      ..close();
    canvas.drawPath(leftEar, ribbonPaint);
    canvas.drawPath(leftEar, ribbonStroke);

    final rightEar = Path()
      ..moveTo(center.dx + 4, center.dy - r * 0.9)
      ..quadraticBezierTo(center.dx + r * 0.55, center.dy - r * 1.6, center.dx + r * 0.35, center.dy - r * 1.55)
      ..quadraticBezierTo(center.dx + r * 0.15, center.dy - r * 1.2, center.dx + 2, center.dy - r * 0.9)
      ..close();
    canvas.drawPath(rightEar, ribbonPaint);
    canvas.drawPath(rightEar, ribbonStroke);

    canvas.drawCircle(Offset(center.dx, center.dy - r * 0.9), 4.5, ribbonPaint);

    final collarPaint = Paint()..color = Colors.white;
    final collarStroke = Paint()
      ..color = const Color(0xFFCBD5E1)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final collarPath = Path()
      ..moveTo(center.dx - r * 0.55, center.dy + r * 0.85)
      ..lineTo(center.dx, center.dy + r * 1.18)
      ..lineTo(center.dx + r * 0.55, center.dy + r * 0.85)
      ..close();
    canvas.drawPath(collarPath, collarPaint);
    canvas.drawPath(collarPath, collarStroke);

    canvas.drawCircle(Offset(center.dx, center.dy + r * 0.98), 4, ribbonPaint);
  }

  // 3. 圣诞节快乐：红白圣诞帽 + 礼盒
  void _paintChristmas(Canvas canvas, Size size, Offset center) {
    final w = size.width;
    final r = w * 0.285;

    final hatPaint = Paint()..color = const Color(0xFFFF4757);
    final hatPath = Path()
      ..moveTo(center.dx - r * 0.4, center.dy - r * 0.8)
      ..quadraticBezierTo(center.dx + r * 0.3, center.dy - r * 1.7, center.dx + r * 1.05, center.dy - r * 1.15)
      ..lineTo(center.dx + r * 0.75, center.dy - r * 0.7)
      ..close();
    canvas.drawPath(hatPath, hatPaint);

    final furPaint = Paint()..color = Colors.white;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromCenter(center: Offset(center.dx + r * 0.2, center.dy - r * 0.8), width: r * 1.2, height: r * 0.28),
        const Radius.circular(6),
      ),
      furPaint,
    );

    canvas.drawCircle(Offset(center.dx + r * 1.1, center.dy - r * 1.15), r * 0.16, furPaint);

    final boxRect = Rect.fromCenter(center: Offset(center.dx - r * 0.75, center.dy + r * 0.75), width: r * 0.55, height: r * 0.55);
    canvas.drawRRect(RRect.fromRectAndRadius(boxRect, const Radius.circular(3)), hatPaint);

    final goldRibbon = Paint()
      ..color = const Color(0xFFFFD32A)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawLine(Offset(boxRect.left, boxRect.center.dy), Offset(boxRect.right, boxRect.center.dy), goldRibbon);
    canvas.drawLine(Offset(boxRect.center.dx, boxRect.top), Offset(boxRect.center.dx, boxRect.bottom), goldRibbon);
  }

  // 4. 学霸：左侧 100 分试卷堆叠 + 蚊香眼睛 + 底部书本
  void _paintXueba(Canvas canvas, Size size, Offset center) {
    final w = size.width;
    final r = w * 0.285;

    final paperPaint = Paint()..color = Colors.white;
    final paperBorder = Paint()
      ..color = const Color(0xFF70A1FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;

    for (int i = 0; i < 3; i++) {
      final rect = Rect.fromLTWH(center.dx - r * 1.25 + i * 4, center.dy - r * 0.85 + i * 7, r * 0.5, r * 0.65);
      canvas.drawRect(rect, paperPaint);
      canvas.drawRect(rect, paperBorder);
    }

    final scorePainter = TextPainter(
      text: const TextSpan(
        text: '100',
        style: TextStyle(
          color: Color(0xFFFF4757),
          fontSize: 12,
          fontWeight: FontWeight.w900,
          fontFamily: 'monospace',
          decoration: TextDecoration.underline,
          decorationColor: Color(0xFFFF4757),
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    scorePainter.layout();
    scorePainter.paint(canvas, Offset(center.dx - r * 1.2, center.dy - r * 0.72));

    final glassPaint = Paint()
      ..color = const Color(0xFF2F3542)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;

    canvas.drawCircle(Offset(center.dx - r * 0.32, center.dy - r * 0.15), r * 0.22, glassPaint);
    canvas.drawCircle(Offset(center.dx + r * 0.32, center.dy - r * 0.15), r * 0.22, glassPaint);
    canvas.drawLine(Offset(center.dx - r * 0.1, center.dy - r * 0.15), Offset(center.dx + r * 0.1, center.dy - r * 0.15), glassPaint);

    final bookPaint = Paint()..color = const Color(0xFF70A1FF);
    final bookRect = Rect.fromCenter(center: Offset(center.dx, center.dy + r * 0.95), width: r * 0.85, height: r * 0.32);
    canvas.drawRRect(RRect.fromRectAndRadius(bookRect, const Radius.circular(3)), bookPaint);
  }

  // 5. 凹凸世界：棒球战帽 + 凹凸几何徽标 + 背带
  void _paintAotu(Canvas canvas, Size size, Offset center) {
    final w = size.width;
    final r = w * 0.285;

    final capPaint = Paint()..color = const Color(0xFF1E3799);
    final capVisor = Paint()..color = const Color(0xFFFFA502);

    final capPath = Path()
      ..moveTo(center.dx - r * 0.85, center.dy - r * 0.45)
      ..quadraticBezierTo(center.dx, center.dy - r * 1.45, center.dx + r * 0.85, center.dy - r * 0.45)
      ..close();
    canvas.drawPath(capPath, capPaint);

    final visorPath = Path()
      ..moveTo(center.dx - r * 0.9, center.dy - r * 0.4)
      ..quadraticBezierTo(center.dx, center.dy - r * 0.15, center.dx + r * 0.9, center.dy - r * 0.4)
      ..lineTo(center.dx + r * 0.75, center.dy - r * 0.55)
      ..lineTo(center.dx - r * 0.75, center.dy - r * 0.55)
      ..close();
    canvas.drawPath(visorPath, capVisor);

    final logoPaint = Paint()..color = Colors.white;
    final logoPath = Path()
      ..moveTo(center.dx - 7, center.dy - r * 0.92)
      ..lineTo(center.dx + 7, center.dy - r * 0.92)
      ..lineTo(center.dx + 4, center.dy - r * 0.72)
      ..lineTo(center.dx - 4, center.dy - r * 0.72)
      ..close();
    canvas.drawPath(logoPath, logoPaint);

    final strapPaint = Paint()
      ..color = const Color(0xFFFFA502)
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(Offset(center.dx - r * 0.75, center.dy + r * 0.4), Offset(center.dx - r * 0.95, center.dy + r * 0.95), strapPaint);
  }

  // 6. 快把我哥带走：绵羊头套 + 双羊角 + 金铃铛
  void _paintBrotherTake(Canvas canvas, Size size, Offset center) {
    final w = size.width;
    final r = w * 0.285;

    final woolPaint = Paint()..color = Colors.white;
    final woolStroke = Paint()
      ..color = const Color(0xFF747D8C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;

    const count = 16;
    for (int i = 0; i < count; i++) {
      final angle = i * 2 * math.pi / count;
      final cx = center.dx + math.cos(angle) * (r * 1.02);
      final cy = center.dy + math.sin(angle) * (r * 1.02);
      canvas.drawCircle(Offset(cx, cy), r * 0.2, woolPaint);
      canvas.drawCircle(Offset(cx, cy), r * 0.2, woolStroke);
    }

    final hornPaint = Paint()..color = const Color(0xFF57606F);
    final leftHorn = Path()
      ..moveTo(center.dx - r * 0.75, center.dy - r * 0.65)
      ..quadraticBezierTo(center.dx - r * 1.05, center.dy - r * 1.05, center.dx - r * 0.55, center.dy - r * 0.95)
      ..close();
    canvas.drawPath(leftHorn, hornPaint);

    final rightHorn = Path()
      ..moveTo(center.dx + r * 0.75, center.dy - r * 0.65)
      ..quadraticBezierTo(center.dx + r * 1.05, center.dy - r * 1.05, center.dx + r * 0.55, center.dy - r * 0.95)
      ..close();
    canvas.drawPath(rightHorn, hornPaint);

    final bellCenter = Offset(center.dx, center.dy + r * 1.05);
    final bellPaint = Paint()..color = const Color(0xFFFFD32A);
    final bellStroke = Paint()
      ..color = const Color(0xFFFFA502)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(bellCenter, r * 0.18, bellPaint);
    canvas.drawCircle(bellCenter, r * 0.18, bellStroke);
  }

  // 7. 少女前线：猫耳战术耳机 + 红心气泡 + 围巾
  void _paintGirlsFrontline(Canvas canvas, Size size, Offset center) {
    final w = size.width;
    final r = w * 0.285;

    final earPaint = Paint()..color = const Color(0xFFD35400);
    final earPathL = Path()
      ..moveTo(center.dx - r * 0.8, center.dy - r * 0.6)
      ..lineTo(center.dx - r * 1.05, center.dy - r * 1.25)
      ..lineTo(center.dx - r * 0.35, center.dy - r * 0.85)
      ..close();
    canvas.drawPath(earPathL, earPaint);

    final earPathR = Path()
      ..moveTo(center.dx + r * 0.8, center.dy - r * 0.6)
      ..lineTo(center.dx + r * 1.05, center.dy - r * 1.25)
      ..lineTo(center.dx + r * 0.35, center.dy - r * 0.85)
      ..close();
    canvas.drawPath(earPathR, earPaint);

    final heartPaint = Paint()..color = const Color(0xFFFF4757);
    final hx = center.dx - r * 0.85;
    final hy = center.dy - r * 0.95;
    canvas.drawCircle(Offset(hx, hy), 6, heartPaint);

    final scarfPaint = Paint()
      ..color = const Color(0xFFFF7F50)
      ..strokeWidth = 4.0
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    canvas.drawArc(Rect.fromCircle(center: center, radius: r * 0.95), 0.3, 2.5, false, scarfPaint);
  }

  // 8. 实验品家庭：额头金光天才 + 眼镜 + 白大褂领结
  void _paintExperimentFamily(Canvas canvas, Size size, Offset center) {
    final w = size.width;
    final r = w * 0.285;

    final textPainter = TextPainter(
      text: const TextSpan(
        text: '天才',
        style: TextStyle(
          color: Color(0xFFFFD32A),
          fontSize: 13,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    textPainter.layout();
    textPainter.paint(canvas, Offset(center.dx - textPainter.width / 2, center.dy - r * 1.15));

    final glassPaint = Paint()
      ..color = const Color(0xFF70A1FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.8;
    canvas.drawRect(Rect.fromCenter(center: Offset(center.dx - r * 0.35, center.dy - r * 0.15), width: r * 0.45, height: r * 0.3), glassPaint);
    canvas.drawRect(Rect.fromCenter(center: Offset(center.dx + r * 0.35, center.dy - r * 0.15), width: r * 0.45, height: r * 0.3), glassPaint);
    canvas.drawLine(Offset(center.dx - r * 0.12, center.dy - r * 0.15), Offset(center.dx + r * 0.12, center.dy - r * 0.15), glassPaint);

    final coatPaint = Paint()..color = Colors.white;
    final coatRect = Rect.fromCenter(center: Offset(center.dx, center.dy + r * 0.95), width: r * 0.7, height: r * 0.25);
    canvas.drawRect(coatRect, coatPaint);
  }

  // 9. 春原庄的管理人小姐：黄色遮阳草帽 + 粉色蕾丝 + 右侧小黄鸟
  void _paintHaruhara(Canvas canvas, Size size, Offset center) {
    final w = size.width;
    final r = w * 0.285;

    final hatPaint = Paint()..color = const Color(0xFFFFEAA7);
    final hatPath = Path()
      ..moveTo(center.dx - r * 1.15, center.dy - r * 0.6)
      ..quadraticBezierTo(center.dx, center.dy - r * 1.5, center.dx + r * 1.15, center.dy - r * 0.6)
      ..quadraticBezierTo(center.dx, center.dy - r * 0.9, center.dx - r * 1.15, center.dy - r * 0.6)
      ..close();
    canvas.drawPath(hatPath, hatPaint);

    final ribbonPaint = Paint()
      ..color = const Color(0xFFFF7675)
      ..strokeWidth = 2.5
      ..style = PaintingStyle.stroke;
    canvas.drawArc(Rect.fromCircle(center: center, radius: r * 1.05), -math.pi * 0.75, math.pi * 0.5, false, ribbonPaint);

    final birdCenter = Offset(center.dx + r * 0.85, center.dy - r * 1.05);
    final birdPaint = Paint()..color = const Color(0xFFFDCB6E);
    canvas.drawCircle(birdCenter, 5.5, birdPaint);
  }

  // 10. 吃瓜：下巴前多汁红瓤绿皮黑籽西瓜切片
  void _paintEatingMelon(Canvas canvas, Size size, Offset center) {
    final w = size.width;
    final r = w * 0.285;

    final melonCenter = Offset(center.dx, center.dy + r * 0.65);
    final melonRect = Rect.fromCenter(center: melonCenter, width: r * 1.35, height: r * 0.95);

    final rindPaint = Paint()
      ..color = const Color(0xFF2ED573)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    canvas.drawArc(melonRect, 0.1, math.pi - 0.2, false, rindPaint);

    final fleshPaint = Paint()
      ..color = const Color(0xFFFF4757)
      ..style = PaintingStyle.fill;
    final fleshPath = Path()
      ..moveTo(melonCenter.dx - r * 0.62, melonCenter.dy)
      ..lineTo(melonCenter.dx + r * 0.62, melonCenter.dy)
      ..arcTo(melonRect, 0.1, math.pi - 0.2, false)
      ..close();
    canvas.drawPath(fleshPath, fleshPaint);

    final seedPaint = Paint()..color = const Color(0xFF2F3542);
    canvas.drawCircle(Offset(melonCenter.dx - 8, melonCenter.dy + 8), 1.5, seedPaint);
    canvas.drawCircle(Offset(melonCenter.dx, melonCenter.dy + 12), 1.5, seedPaint);
    canvas.drawCircle(Offset(melonCenter.dx + 8, melonCenter.dy + 8), 1.5, seedPaint);
  }

  // 11. 苦力怕：绿色发箍 + 左上苦力怕头像 + 右下金色 KLP 勋章徽标
  void _paintCreeper(Canvas canvas, Size size, Offset center) {
    final w = size.width;
    final r = w * 0.285;

    // 绿色发箍环绕
    final bandPaint = Paint()
      ..color = const Color(0xFF2ED573)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.5;
    canvas.drawArc(Rect.fromCircle(center: center, radius: r * 1.02), -math.pi * 0.85, math.pi * 0.7, false, bandPaint);

    // 左上角苦力怕头部小头像
    final creepCenter = Offset(center.dx - r * 0.75, center.dy - r * 0.75);
    final creepPaint = Paint()..color = const Color(0xFF2ED573);
    final creepStroke = Paint()
      ..color = const Color(0xFF1E272E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final creepRect = Rect.fromCenter(center: creepCenter, width: 18, height: 18);
    canvas.drawRRect(RRect.fromRectAndRadius(creepRect, const Radius.circular(3)), creepPaint);
    canvas.drawRRect(RRect.fromRectAndRadius(creepRect, const Radius.circular(3)), creepStroke);

    // 苦力怕脸黑像素
    final facePaint = Paint()..color = const Color(0xFF1E272E);
    canvas.drawRect(Rect.fromLTWH(creepCenter.dx - 6, creepCenter.dy - 5, 3.5, 3.5), facePaint);
    canvas.drawRect(Rect.fromLTWH(creepCenter.dx + 2.5, creepCenter.dy - 5, 3.5, 3.5), facePaint);
    canvas.drawRect(Rect.fromLTWH(creepCenter.dx - 2.5, creepCenter.dy - 1.5, 5, 4.5), facePaint);

    // 右下角金色 KLP 勋章
    final badgeCenter = Offset(center.dx + r * 0.75, center.dy + r * 0.75);
    final badgePaint = Paint()..color = const Color(0xFFFFD32A);
    final badgeStroke = Paint()
      ..color = const Color(0xFFFFA502)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(badgeCenter, 11, badgePaint);
    canvas.drawCircle(badgeCenter, 11, badgeStroke);

    final klpPainter = TextPainter(
      text: const TextSpan(
        text: 'KLP',
        style: TextStyle(
          color: Color(0xFFD35400),
          fontSize: 8.5,
          fontWeight: FontWeight.w900,
        ),
      ),
      textDirection: TextDirection.ltr,
    );
    klpPainter.layout();
    klpPainter.paint(canvas, Offset(badgeCenter.dx - klpPainter.width / 2, badgeCenter.dy - klpPainter.height / 2));
  }

  // 19. 喵内：酒红发带 + 右侧萌系双马尾日向小人
  void _paintMyanee(Canvas canvas, Size size, Offset center) {
    final w = size.width;
    final r = w * 0.285;

    // 酒红发带环绕
    final bandPaint = Paint()
      ..color = const Color(0xFF8B263E)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 4.0;
    canvas.drawArc(Rect.fromCircle(center: center, radius: r * 1.02), -math.pi * 0.8, math.pi * 0.6, false, bandPaint);

    // 右侧 Q 版日向立绘
    final girlCenter = Offset(center.dx + r * 0.92, center.dy - r * 0.05);
    final skinPaint = Paint()..color = const Color(0xFFFFDFBA);
    canvas.drawCircle(girlCenter, 10, skinPaint);

    final hairPaint = Paint()..color = const Color(0xFF8D6E63);
    canvas.drawCircle(Offset(girlCenter.dx - 6, girlCenter.dy - 6), 4, hairPaint);
    canvas.drawCircle(Offset(girlCenter.dx + 6, girlCenter.dy - 6), 4, hairPaint);

    final eyePaint = Paint()..color = const Color(0xFF2C3E50);
    canvas.drawCircle(Offset(girlCenter.dx - 3, girlCenter.dy), 1.2, eyePaint);
    canvas.drawCircle(Offset(girlCenter.dx + 3, girlCenter.dy), 1.2, eyePaint);

    // 红色小蝴蝶结
    final bowPaint = Paint()..color = const Color(0xFFFF4757);
    canvas.drawCircle(Offset(girlCenter.dx, girlCenter.dy + 8), 3, bowPaint);
  }

  // 钻石剑环绕
  void _paintDiamond(Canvas canvas, Size size, Offset center) {
    final w = size.width;
    final r = w * 0.44;
    final ringPaint = Paint()
      ..color = const Color(0xFF00E5FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(center, r, ringPaint);
  }

  // 末影龙之翼
  void _paintDragon(Canvas canvas, Size size, Offset center) {
    final w = size.width;
    final r = w * 0.44;
    final ringPaint = Paint()
      ..color = const Color(0xFFD500F9)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(center, r, ringPaint);
  }

  // 下界合金战盔
  void _paintNetherite(Canvas canvas, Size size, Offset center) {
    final w = size.width;
    final r = w * 0.44;
    final ringPaint = Paint()
      ..color = const Color(0xFFFF6D00)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(center, r, ringPaint);
  }

  // 凋灵风暴
  void _paintWither(Canvas canvas, Size size, Offset center) {
    final w = size.width;
    final r = w * 0.44;
    final ringPaint = Paint()
      ..color = const Color(0xFF5352ED)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(center, r, ringPaint);
  }

  // 可莉
  void _paintKlee(Canvas canvas, Size size, Offset center) {
    final w = size.width;
    final r = w * 0.285;
    final beretPaint = Paint()..color = const Color(0xFFFF1744);
    canvas.drawOval(Rect.fromCenter(center: Offset(center.dx, center.dy - r * 0.95), width: r * 1.5, height: r * 0.5), beretPaint);
  }

  // 猫耳娘
  void _paintCatEars(Canvas canvas, Size size, Offset center) {
    final w = size.width;
    final r = w * 0.285;
    final earPaint = Paint()..color = const Color(0xFFFF4081);
    final earPathL = Path()
      ..moveTo(center.dx - r * 0.8, center.dy - r * 0.6)
      ..lineTo(center.dx - r * 1.1, center.dy - r * 1.3)
      ..lineTo(center.dx - r * 0.3, center.dy - r * 0.9)
      ..close();
    canvas.drawPath(earPathL, earPaint);

    final earPathR = Path()
      ..moveTo(center.dx + r * 0.8, center.dy - r * 0.6)
      ..lineTo(center.dx + r * 1.1, center.dy - r * 1.3)
      ..lineTo(center.dx + r * 0.3, center.dy - r * 0.9)
      ..close();
    canvas.drawPath(earPathR, earPaint);
  }

  // 星空浩瀚
  void _paintGalaxy(Canvas canvas, Size size, Offset center) {
    final w = size.width;
    final r = w * 0.44;
    final ringPaint = Paint()
      ..color = const Color(0xFF3742FA)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0;
    canvas.drawCircle(center, r, ringPaint);
  }

  void _paintDefaultHalo(Canvas canvas, Size size, Offset center) {
    final w = size.width;
    final r = w * 0.44;
    final haloPaint = Paint()
      ..color = const Color(0xFF00A2FF)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    canvas.drawCircle(center, r, haloPaint);
  }

  @override
  bool shouldRepaint(covariant _FacemallPainter oldDelegate) => oldDelegate.id != id;
}
