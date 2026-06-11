import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_remote_config/firebase_remote_config.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:hive/hive.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'firebase_options.dart';

// ================= 全局色彩美学配置 (Midnight & Ethereal Gold) =================
class AppColors {
  // 核心主色
  static const Color gold = Color(0xFFE8C37C);           // 塔罗奢华暗金
  static const Color mysticPurple = Color(0xFF9E7BFF);   // 灵境神秘紫
  static const Color cyanGlow = Color(0xFF4DEEEA);       // 幽魂青绿（点缀）
  
  // 透明度衍生色
  static const Color goldDim = Color.fromARGB(153, 158, 91, 185);        // 60% 金
  static const Color goldGlow = Color.fromARGB(102, 205, 124, 232);       // 40% 金
  static const Color mysticPurpleDim = Color(0x809E7BFF);// 50% 紫
  
  // 深空背景
  static const Color bgTop = Color.fromARGB(34, 103, 83, 138);          // 穹顶午夜靛蓝
  static const Color bgBottom = Color(0xFF030206);       // 深渊虚无黑
  
  // 玻璃拟态
  static const Color glassBg = Color.fromARGB(160, 80, 50, 110);        // 幽邃紫透底
  static const Color glassBorder = Color.fromARGB(77, 212, 124, 232);    // 30% 金色细边
  
  // 卡牌色系
  static const Color cardBackDark = Color.fromARGB(255, 33, 25, 67);   // 牌背深渊色
  static const Color cardBackLight = Color.fromARGB(255, 157, 7, 171);  // 牌背紫光色

  static const Color pink = Color.fromARGB(134, 150, 1, 150);
  static const Color selectedTile = Color(0xFFE040FB); 
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  // 初始化 Hive 本地数据库
  await Hive.initFlutter();
  Hive.registerAdapter(ReadingRecordAdapter());
  await Hive.openBox<ReadingRecord>('reading_history');

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );
    debugPrint("🔥 Firebase 初始化成功！");
  } catch (e) {
    debugPrint("❌ Firebase 初始化失败: $e");
  }
  runApp(const TarotApp());
}

// ================= 全局音频管理器 =================
class AudioManager {
  static final AudioManager _instance = AudioManager._internal();
  factory AudioManager() => _instance;
  AudioManager._internal() {
    _init();
  }
  late AudioPlayer _bgmPlayer;
  late AudioPlayer _sfxPlayer;
  bool _initialized = false;

  void _init() {
    _bgmPlayer = AudioPlayer();
    _sfxPlayer = AudioPlayer();
    _initialized = true;
  }

  Future<void> playSfx(String path) async {
    if (!_initialized) return;
    try {
      await _sfxPlayer.play(AssetSource(path));
    } catch (e) {
      debugPrint('SFX play error: $e');
    }
  }

  void dispose() {
    _bgmPlayer.dispose();
    _sfxPlayer.dispose();
  }
}

// ================= 升级版粒子背景 =================
class ParticleBackgroundPainter extends CustomPainter {
  final double time;
  ParticleBackgroundPainter(this.time);
  final _rand = Random(42);
  List<_Particle>? _particles;
  
  void _initOnce(Size size) {
    _particles = List.generate(50, (i) {
      return _Particle(
        x: _rand.nextDouble() * size.width,
        y: _rand.nextDouble() * size.height,
        radius: _rand.nextDouble() * 2.5 + 0.5,
        speedX: (_rand.nextDouble() - 0.5) * 0.8,
        speedY: (_rand.nextDouble() - 0.5) * 0.8,
        opacity: _rand.nextDouble() * 0.6 + 0.1,
        trailLength: _rand.nextDouble() * 20 + 10,
      );
    });
  }
  
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    _particles ?? _initOnce(size);
    final paint = Paint()..style = PaintingStyle.fill;
    final trailPaint = Paint()
      ..style = PaintingStyle.fill
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 3);
      
    for (var p in _particles!) {
      double dx = p.x + p.speedX * time * 20;
      double dy = p.y + p.speedY * time * 20;
      dx = dx % size.width;
      dy = dy % size.height;
      if (dx < 0) dx += size.width;
      if (dy < 0) dy += size.height;
      
      trailPaint.color = Color.fromRGBO(158, 123, 255, (p.opacity * 0.3 * (0.7 + 0.3 * sin(time + p.x))).clamp(0.0, 1.0));
      paint.color = Color.fromRGBO(232, 195, 124, (p.opacity * (0.8 + 0.2 * sin(time + p.x))).clamp(0.0, 1.0));
      
      canvas.drawCircle(Offset(dx, dy), p.radius * 1.5, trailPaint);
      canvas.drawCircle(Offset(dx, dy), p.radius, paint);
    }
  }
  @override
  bool shouldRepaint(covariant ParticleBackgroundPainter oldDelegate) => oldDelegate.time != time;
}

class _Particle {
  double x, y, radius, speedX, speedY, opacity, trailLength;
  _Particle({
    required this.x, required this.y, required this.radius,
    required this.speedX, required this.speedY, required this.opacity,
    required this.trailLength,
  });
}

// ================= 光丝背景 + 缓慢魔法阵 =================
class LightThreadsPainter extends CustomPainter {
  final double time;
  LightThreadsPainter(this.time);
  @override
  void paint(Canvas canvas, Size size) {
    if (size.width <= 0 || size.height <= 0) return;

    final paint = Paint()
      ..color = AppColors.mysticPurple.withOpacity(0.12) 
      ..strokeWidth = 1.2
      ..style = PaintingStyle.stroke;
    final path = Path();
    final w = size.width, h = size.height;
    
    for (int i = 0; i < 4; i++) {
      final shift = sin(time * 0.5 + i) * 60;
      path.reset();
      path.moveTo(-20, h * 0.2 + shift);
      path.quadraticBezierTo(w * 0.3, h * 0.4 + shift + 25, w * 0.6, h * 0.3 + shift - 15);
      path.quadraticBezierTo(w * 0.8, h * 0.2 + shift, w + 20, h * 0.5 + shift);
      canvas.drawPath(path, paint);
    }
    for (int i = 0; i < 3; i++) {
      final shift = cos(time * 0.4 + i) * 50;
      path.reset();
      path.moveTo(w * 0.1, h + 20);
      path.quadraticBezierTo(w * 0.4, h * 0.6 + shift, w * 0.5, h * 0.4 + shift);
      path.quadraticBezierTo(w * 0.7, h * 0.2 + shift, w + 20, h * 0.0);
      canvas.drawPath(path, paint);
    }
    
    canvas.save();
    canvas.translate(w / 2, h / 2);
    canvas.rotate(time * 0.15);
    final circlePaint = Paint()
      ..color = AppColors.gold.withOpacity(0.06) 
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(Offset.zero, w * 0.6, circlePaint);
    canvas.drawCircle(Offset.zero, w * 0.55, circlePaint);
    
    final starPaint = Paint()
      ..color = AppColors.gold.withOpacity(0.08) 
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (int i = 0; i < 6; i++) {
      final angle = i * pi / 3 + time * 0.1;
      final dx = cos(angle) * w * 0.5;
      final dy = sin(angle) * w * 0.5;
      canvas.drawLine(Offset.zero, Offset(dx, dy), starPaint);
    }
    canvas.restore();
  }
  @override
  bool shouldRepaint(covariant LightThreadsPainter oldDelegate) => oldDelegate.time != time;
}

class AnimatedBackground extends StatefulWidget {
  final Widget child;
  const AnimatedBackground({Key? key, required this.child}) : super(key: key);
  @override
  _AnimatedBackgroundState createState() => _AnimatedBackgroundState();
}

class _AnimatedBackgroundState extends State<AnimatedBackground> with SingleTickerProviderStateMixin {
  late AnimationController _bgController;
  @override
  void initState() {
    super.initState();
    _bgController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 30),
    )..repeat();
  }
  @override
  void dispose() {
    _bgController.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _bgController,
      builder: (_, __) {
        final t = _bgController.value * 30;
        return Stack(
          children: [
            Positioned.fill(
              child: Container(
                decoration: const BoxDecoration(
                  gradient: RadialGradient(
                    center: Alignment(0.0, -0.4),
                    radius: 1.6,
                    colors: [
                      Color.fromARGB(51, 128, 111, 171),
                      Color.fromARGB(17, 42, 31, 70),
                      Color.fromARGB(0, 40, 40, 40),
                    ],
                    stops: [0.0, 0.5, 1.0],
                  ),
                ),
              ),
            ),
            Positioned.fill(child: CustomPaint(painter: ParticleBackgroundPainter(t))),
            Positioned.fill(child: CustomPaint(painter: LightThreadsPainter(t))),
            widget.child,
          ],
        );
      },
    );
  }
}

// ================= 路由转场动画 =================
Route _createRoute(Widget page, {bool scale = false}) {
  if (scale) {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(parent: animation, curve: Curves.easeInOutCubic);
        return ScaleTransition(
          scale: Tween<double>(begin: 0.85, end: 1.0).animate(curve),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      transitionDuration: const Duration(milliseconds: 500),
    );
  } else {
    return PageRouteBuilder(
      pageBuilder: (context, animation, secondaryAnimation) => page,
      transitionsBuilder: (context, animation, secondaryAnimation, child) {
        final curve = CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
        return SlideTransition(
          position: Tween<Offset>(begin: const Offset(0, 0.1), end: Offset.zero).animate(curve),
          child: FadeTransition(opacity: animation, child: child),
        );
      },
      transitionDuration: const Duration(milliseconds: 500),
    );
  }
}

// ================= 程序入口 =================
class TarotApp extends StatelessWidget {
  const TarotApp({Key? key}) : super(key: key);
  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: '塔罗-灵境 Tarot',
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color.fromARGB(255, 232, 124, 207),
        scaffoldBackgroundColor: Colors.transparent, 
        fontFamily: GoogleFonts.notoSerifSc().fontFamily,
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: GoogleFonts.notoSerifSc(
            color: AppColors.gold,
            fontSize: 22,
            fontWeight: FontWeight.w600,
            letterSpacing: 2,
            shadows: const [
              Shadow(color: AppColors.goldGlow, blurRadius: 10),
            ],
          ),
          iconTheme: const IconThemeData(color: AppColors.gold),
        ),
        textTheme: TextTheme(
          bodyLarge: GoogleFonts.notoSerifSc(color: Colors.white70, fontSize: 16),
          bodyMedium: GoogleFonts.notoSerifSc(color: Colors.white60, fontSize: 14),
        ),
        cardColor: const Color(0xFF161026),
        dialogBackgroundColor: const Color(0xFF1A132F),
      ),
      home: const HomeScreen(),
      debugShowCheckedModeBanner: false,
      builder: (context, child) {
        return Scaffold(
          backgroundColor: AppColors.bgBottom,
          body: AnimatedBackground(child: child!),
        );
      },
    );
  }
}

// ================= 全局语言支持 =================
enum AppLanguage { zh, en, ms }

String tr(AppLanguage lang, String zh, String en, String ms) {
  if (lang == AppLanguage.en) return en;
  if (lang == AppLanguage.ms) return ms;
  return zh;
}

// ================= 数据模型与四大经典牌阵配置 =================

class SpreadConfig {
  final String nameZh, nameEn, nameMs;
  final List<String> positionsZh, positionsEn, positionsMs;
  final String descriptionZh, descriptionEn, descriptionMs;

  SpreadConfig({
    required this.nameZh, required this.nameEn, required this.nameMs,
    required this.positionsZh, required this.positionsEn, required this.positionsMs,
    required this.descriptionZh, required this.descriptionEn, required this.descriptionMs,
  });

  String name(AppLanguage lang) => tr(lang, nameZh, nameEn, nameMs);
  String description(AppLanguage lang) => tr(lang, descriptionZh, descriptionEn, descriptionMs);
  List<String> positions(AppLanguage lang) {
    if (lang == AppLanguage.en) return positionsEn;
    if (lang == AppLanguage.ms) return positionsMs;
    return positionsZh;
  }
}

class Topic {
  final String zh, en, ms;
  const Topic({required this.zh, required this.en, required this.ms});
  String text(AppLanguage lang) => tr(lang, zh, en, ms);
}

final List<SpreadConfig> availableSpreads = [
  SpreadConfig(
    nameZh: '圣三角牌阵 (3张)', nameEn: 'Holy Triangle Spread (3 cards)', nameMs: 'Susunan Segitiga Suci (3 kad)',
    descriptionZh: '最经典的入门牌阵，呈倒三角排列。适合每日运势或快速提问。',
    descriptionEn: 'A classic beginner spread in an inverted triangle. Best for daily fortune or quick questions.',
    descriptionMs: 'Susunan klasik untuk pemula dalam bentuk segitiga terbalik. Sesuai untuk nasib harian atau soalan pantas.',
    positionsZh: ['显意识 / 外部现状', '潜意识 / 隐性阻碍', '破局点 / 核心建议'],
    positionsEn: ['Conscious / External Situation', 'Subconscious / Hidden Obstacle', 'Breakthrough / Core Advice'],
    positionsMs: ['Sedar / Situasi Luaran', 'Bawah Sedar / Halangan Tersembunyi', 'Titik Kejayaan / Nasihat Utama'],
  ),
  SpreadConfig(
    nameZh: '大十字展开法 (5张)', nameEn: 'Grand Cross Layout (5 cards)', nameMs: 'Susunan Salib Besar (5 kad)',
    descriptionZh: '呈完美的十字形状，剖析特定事件的核心、阻力、助力及深层原因。',
    descriptionEn: 'A perfect cross layout that reveals the core, resistance, support and deep roots of a specific event.',
    descriptionMs: 'Susunan salib yang sempurna yang mendedahkan inti, rintangan, sokongan dan akar mendalam peristiwa tertentu.',
    positionsZh: ['最终结果', '外在环境的有利因素 / 帮助', '外在环境的阻碍 / 挑战', '问题的原因 / 心理根源', '最主要的解决方法 / 核心对策'],
    positionsEn: ['Outcome', 'External Support / Help', 'External Obstacle / Challenge', 'Cause / Mental Root', 'Main Solution / Core Strategy'],
    positionsMs: ['Hasil', 'Sokongan Luaran / Bantuan', 'Halangan Luaran / Cabaran', 'Punca / Akar Mental', 'Penyelesaian Utama / Strategi Teras'],
  ),
  SpreadConfig(
    nameZh: '二择一展开法 (5张)', nameEn: 'Choice Spread (5 cards)', nameMs: 'Susunan Pilihan (5 kad)',
    descriptionZh: '呈 Y 字形分支，面临抉择时专门针对“做决定”设计的牌阵。',
    descriptionEn: 'A Y-shaped spread crafted for decision-making questions and evaluating two options.',
    descriptionMs: 'Susunan berbentuk Y yang direka untuk soalan membuat keputusan dan menilai dua pilihan.',
    positionsZh: ['求问者现状', '选择 A 的发展现状', '选择 B 的发展现状', '选择 A 的最终结果', '选择 B 的最终结果'],
    positionsEn: ['Querent Situation', 'Option A Current Path', 'Option B Current Path', 'Option A Outcome', 'Option B Outcome'],
    positionsMs: ['Situasi Penanya', 'Laluan Semasa Pilihan A', 'Laluan Semasa Pilihan B', 'Hasil Pilihan A', 'Hasil Pilihan B'],
  ),
  SpreadConfig(
    nameZh: '凯尔特十字 (10张)', nameEn: 'Celtic Cross (10 cards)', nameMs: 'Salib Celtic (10 kad)',
    descriptionZh: '最经典的塔罗牌阵，包含中央十字与右侧立柱。全方位深度剖析复杂问题。',
    descriptionEn: 'The classic Celtic Cross with a central cross and right-side pillar for deep analysis of complex issues.',
    descriptionMs: 'Salib Celtic klasik dengan salib di tengah dan tiang di sebelah kanan untuk analisis mendalam isu yang kompleks.',
    positionsZh: ['当前现状', '面临的障碍(横放)', '潜意识 / 现实基础', '过去的影响', '显意识 / 理想目标', '不久的未来', '当事人状态', '环境/他人影响', '希望与恐惧', '最终结果'],
    positionsEn: ['Current Situation', 'Obstacle (Crossed)', 'Subconscious / Foundation', 'Past Influence', 'Conscious / Ideal Goal', 'Near Future', 'Self State', 'Environment / External Influence', 'Hopes & Fears', 'Final Outcome'],
    positionsMs: ['Situasi Semasa', 'Halangan (Menyilang)', 'Bawah Sedar / Asas', 'Pengaruh Masa Lalu', 'Sedar / Matlamat Ideal', 'Masa Depan Terdekat', 'Keadaan Diri', 'Persekitaran / Pengaruh Luaran', 'Harapan & Ketakutan', 'Hasil Akhir'],
  ),
];

final List<Topic> availableTopics = const [
  Topic(zh: '综合运势', en: 'General Fortune', ms: 'Nasib Umum'),
  Topic(zh: '爱情与感情', en: 'Love & Relationship', ms: 'Cinta & Hubungan'),
  Topic(zh: '事业与工作', en: 'Career & Work', ms: 'Kerjaya & Pekerjaan'),
  Topic(zh: '金钱与财富', en: 'Money & Wealth', ms: 'Wang & Kekayaan'),
  Topic(zh: '身心健康', en: 'Health & Wellbeing', ms: 'Kesihatan & Kesejahteraan'),
];

class TarotCard {
  final String nameZh, nameEn, nameMs, number, arcana, img, uprightZh, uprightEn, uprightMs, reversedZh, reversedEn, reversedMs;
  final String? suit;

  TarotCard({
    required this.nameZh, required this.nameEn, required this.nameMs,
    required this.number, required this.arcana, this.suit, required this.img,
    required this.uprightZh, required this.uprightEn, required this.uprightMs,
    required this.reversedZh, required this.reversedEn, required this.reversedMs,
  });

  String name(AppLanguage lang) => tr(lang, nameZh, nameEn, nameMs);
  String uprightMeaning(AppLanguage lang) => tr(lang, uprightZh, uprightEn, uprightMs);
  String reversedMeaning(AppLanguage lang) => tr(lang, reversedZh, reversedEn, reversedMs);
}

class DrawnCard {
  final TarotCard card;
  final bool isReversed;
  final String positionMeaning;
  DrawnCard({required this.card, required this.isReversed, required this.positionMeaning});
}

// 占位模拟数据注入点
final List<TarotCard> tarotDeck = rawTarotData.map((data) {
  return TarotCard(
    nameZh: data['nameZh'] ?? "", nameEn: data['nameEn'] ?? "", nameMs: data['nameMs'] ?? "",
    number: data['number'] ?? "", arcana: data['arcana'] ?? "", suit: data['suit'],
    img: data['img'] ?? "",
    uprightZh: data['uprightZh'] ?? "解析加载中...", uprightEn: data['uprightEn'] ?? "Meaning loading...", uprightMs: data['uprightMs'] ?? "Maksud sedang dimuatkan...",
    reversedZh: data['reversedZh'] ?? "解析加载中...", reversedEn: data['reversedEn'] ?? "Meaning loading...", reversedMs: data['reversedMs'] ?? "Maksud sedang dimuatkan...",
  );
}).toList();

// ================= Hive 历史记录模型与序列化 =================
class ReadingRecord {
  final String id;
  final int timestamp;
  final String topicZh;
  final String spreadZh;
  final String cardsJson;
  final String aiResponse;
  final int langIndex;

  ReadingRecord({
    required this.id, required this.timestamp, required this.topicZh,
    required this.spreadZh, required this.cardsJson, required this.aiResponse,
    required this.langIndex,
  });
}

class ReadingRecordAdapter extends TypeAdapter<ReadingRecord> {
  @override
  final int typeId = 0;

  @override
  ReadingRecord read(BinaryReader reader) {
    return ReadingRecord(
      id: reader.readString(),
      timestamp: reader.readInt(),
      topicZh: reader.readString(),
      spreadZh: reader.readString(),
      cardsJson: reader.readString(),
      aiResponse: reader.readString(),
      langIndex: reader.readInt(),
    );
  }

  @override
  void write(BinaryWriter writer, ReadingRecord obj) {
    writer.writeString(obj.id);
    writer.writeInt(obj.timestamp);
    writer.writeString(obj.topicZh);
    writer.writeString(obj.spreadZh);
    writer.writeString(obj.cardsJson);
    writer.writeString(obj.aiResponse);
    writer.writeInt(obj.langIndex);
  }
}

String cardsToJson(List<DrawnCard> cards) {
  List<Map<String, dynamic>> list = cards.map((c) => {
    'cardZh': c.card.nameZh,
    'isReversed': c.isReversed,
    'positionMeaning': c.positionMeaning,
  }).toList();
  return jsonEncode(list);
}

List<DrawnCard> cardsFromJson(String jsonStr) {
  try {
    List<dynamic> list = jsonDecode(jsonStr);
    return list.map((item) {
      final cardZh = item['cardZh'];
      final card = tarotDeck.firstWhere((c) => c.nameZh == cardZh, orElse: () => tarotDeck[0]);
      return DrawnCard(
        card: card,
        isReversed: item['isReversed'] as bool,
        positionMeaning: item['positionMeaning'] as String,
      );
    }).toList();
  } catch (e) {
    debugPrint('cardsFromJson error: $e');
    return [];
  }
}

String formatTimestamp(int ms) {
  final dt = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${dt.year}-${dt.month.toString().padLeft(2, '0')}-${dt.day.toString().padLeft(2, '0')} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
}

// ================= 高级玻璃拟态卡片装饰 =================
BoxDecoration glassDecoration({Color? borderColor, double borderRadius = 18}) {
  return BoxDecoration(
    color: const Color.fromARGB(255, 19, 5, 43),
    borderRadius: BorderRadius.circular(borderRadius),
    border: Border.all(
      color: borderColor ?? AppColors.glassBorder,
      width: 1,
    ),
    boxShadow: const [
      BoxShadow(
        color: Color(0x33000000), 
        blurRadius: 15,
        spreadRadius: -2,
        offset: Offset(0, 8),
      ),
    ],
  );
}

// ================= 光晕按钮 (已集成 InkWell 水波纹) =================
class GlowButton extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final Color glowColor;
  final double borderRadius;
  const GlowButton({
    Key? key, 
    required this.child, 
    this.onTap, 
    this.glowColor = AppColors.mysticPurple, 
    this.borderRadius = 20
  }) : super(key: key);

  @override
  _GlowButtonState createState() => _GlowButtonState();
}

class _GlowButtonState extends State<GlowButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  bool _isPressed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 150));
    _scaleAnimation = Tween<double>(begin: 1.0, end: 0.96).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _scaleAnimation,
      builder: (_, child) => Transform.scale(
        scale: _scaleAnimation.value,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(widget.borderRadius),
            boxShadow: [
              BoxShadow(
                color: widget.glowColor.withOpacity(_isPressed ? 0.6 : 0.35),
                blurRadius: _isPressed ? 24 : 16,
                spreadRadius: _isPressed ? 4 : 1,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(widget.borderRadius),
            child: InkWell(
              borderRadius: BorderRadius.circular(widget.borderRadius),
              onTap: widget.onTap,
              splashColor: Colors.white.withOpacity(0.2),
              highlightColor: Colors.transparent,
              onTapDown: (_) {
                setState(() => _isPressed = true);
                _controller.forward();
              },
              onTapUp: (_) {
                setState(() => _isPressed = false);
                _controller.reverse();
              },
              onTapCancel: () {
                setState(() => _isPressed = false);
                _controller.reverse();
              },
              child: widget.child,
            ),
          ),
        ),
      ),
      child: widget.child,
    );
  }
}

// ================= 1. 首页 =================
class HomeScreen extends StatefulWidget {
  const HomeScreen({Key? key}) : super(key: key);
  @override
  _HomeScreenState createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  AppLanguage currentLanguage = AppLanguage.zh;
  Topic selectedTopic = availableTopics[0];
  SpreadConfig selectedSpread = availableSpreads[0];
  final String currentAppVersion = '2.1.0';

  @override
  void initState() {
    super.initState();
    _checkVersion(); 
  }

  Future<void> _checkVersion() async {
    try {
      final remoteConfig = FirebaseRemoteConfig.instance;
      await remoteConfig.setConfigSettings(RemoteConfigSettings(
        fetchTimeout: const Duration(minutes: 1),
        minimumFetchInterval: const Duration(seconds: 0),
      ));
      await remoteConfig.setDefaults({"latest_app_version": currentAppVersion, "apk_download_url": ""});
      await remoteConfig.fetchAndActivate();
    } catch (e) {
      debugPrint("Firebase 版本检查失败: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(tr(currentLanguage, '塔 罗 灵 境', 'Tarot Realm', 'Dunia Tarot'),
            style: GoogleFonts.notoSerifSc(
              fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 4, 
              color: const Color.fromARGB(255, 204, 109, 227), 
              shadows: const [Shadow(color: AppColors.goldGlow, blurRadius: 12)]
            )),
        actions: [
          // 添加历史记录入口按钮
          IconButton(
            icon: const Icon(Icons.history, color: AppColors.gold),
            onPressed: () {
              Navigator.push(context, _createRoute(HistoryScreen(lang: currentLanguage)));
            },
            tooltip: tr(currentLanguage, '历史记录', 'History', 'Sejarah'),
          ),
          PopupMenuButton<AppLanguage>(
            onSelected: (AppLanguage result) => setState(() => currentLanguage = result),
            icon: const Icon(Icons.language, color: AppColors.gold),
            itemBuilder: (BuildContext context) => <PopupMenuEntry<AppLanguage>>[
              const PopupMenuItem(value: AppLanguage.zh, child: Text('中文')),
              const PopupMenuItem(value: AppLanguage.en, child: Text('English')),
              const PopupMenuItem(value: AppLanguage.ms, child: Text('Bahasa Melayu')),
            ],
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16.0),
              child: Text(
                currentLanguage == AppLanguage.zh ? '中文' : currentLanguage == AppLanguage.en ? 'EN' : 'BM',
                style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold),
              ),
            ),
          )
        ],
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter, end: Alignment.bottomCenter,
            colors: [AppColors.bgTop, AppColors.bgBottom],
          ),
        ),
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Center(child: Icon(Icons.auto_awesome, size: 50, color: AppColors.gold)),
                const SizedBox(height: 10),
                Text(tr(currentLanguage, '开启你的占卜结界', 'Open your divination realm', 'Buka alam tenung nasib anda'),
                    textAlign: TextAlign.center,
                    style: GoogleFonts.notoSerifSc(fontSize: 16, color: Colors.white70, letterSpacing: 1.5)),
                const SizedBox(height: 40),
                
                Row(
                  children: [
                    const Icon(Icons.category, color: AppColors.mysticPurple, size: 20),
                    const SizedBox(width: 8),
                    Text(tr(currentLanguage, '你想占卜什么？', 'What would you like to ask?', 'Apa yang anda ingin tanya?'),
                        style: GoogleFonts.notoSerifSc(
                          fontSize: 18, color: AppColors.gold, fontWeight: FontWeight.bold, 
                          shadows: const [Shadow(color: AppColors.goldGlow, blurRadius: 6)]
                        )),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12, runSpacing: 12,
                  children: availableTopics.map((topic) {
                    final isSelected = selectedTopic == topic;
                    return GestureDetector(
                      onTap: () { 
                        setState(() => selectedTopic = topic);
                        AudioManager().playSfx('audio/click.wav');
                      },
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                        decoration: BoxDecoration(
                          color: isSelected ? const Color.fromARGB(255, 123, 2, 115) : AppColors.glassBg,
                          borderRadius: BorderRadius.circular(30),
                          border: Border.all(
                            color: isSelected ? AppColors.gold : Colors.white10,
                            width: 1.2,
                          ),
                          boxShadow: isSelected ? [
                            BoxShadow(color: AppColors.gold.withOpacity(0.3), blurRadius: 12, spreadRadius: 1)
                          ] : [],
                        ),
                        child: Text(
                          topic.text(currentLanguage),
                          style: TextStyle(
                            color: isSelected ? Colors.white : const Color.fromARGB(246, 253, 252, 252),
                            fontSize: 15, fontWeight: isSelected ? FontWeight.w600 : FontWeight.normal,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 45),

                Row(
                  children: [
                    const Icon(Icons.dashboard_customize, color: AppColors.mysticPurple, size: 20),
                    const SizedBox(width: 8),
                    Text(tr(currentLanguage, '请选择灵力法阵', 'Select a spread', 'Sila pilih susunan kad'),
                        style: GoogleFonts.notoSerifSc(
                          fontSize: 18, color: AppColors.gold, fontWeight: FontWeight.bold, 
                          shadows: const [Shadow(color: AppColors.goldGlow, blurRadius: 6)]
                        )),
                  ],
                ),
                const SizedBox(height: 16),
                ...availableSpreads.map((spread) {
                  final isSelected = selectedSpread == spread;
                  return GestureDetector(
                    onTap: () { 
                      setState(() => selectedSpread = spread);
                      AudioManager().playSfx('audio/click.wav');
                    },
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.only(bottom: 16),
                      padding: const EdgeInsets.all(20),
                      decoration: glassDecoration(
                        borderColor: isSelected ? AppColors.gold : Colors.white12,
                      ).copyWith(
                        color: isSelected ? AppColors.pink : AppColors.glassBg,
                        boxShadow: isSelected ? [
                          BoxShadow(color: AppColors.pink, blurRadius: 15, spreadRadius: 0)
                        ] : const [BoxShadow(color: Color(0x33000000), blurRadius: 10, offset: Offset(0, 4))],
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(spread.name(currentLanguage),
                                  style: TextStyle(
                                      fontSize: 18, fontWeight: FontWeight.bold,
                                      color: isSelected ? AppColors.gold : Colors.white,
                                      shadows: isSelected ? const [Shadow(color: AppColors.goldGlow, blurRadius: 8)] : []
                                  )),
                              if (isSelected)
                                const Icon(Icons.check_circle, color: AppColors.gold, size: 22)
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(spread.description(currentLanguage),
                              style: TextStyle(
                                  fontSize: 14, height: 1.6,
                                  color: isSelected ? Colors.white70 : Colors.white54)),
                        ],
                      ),
                    ),
                  );
                }).toList(),

                const SizedBox(height: 45),

                GlowButton(
                  glowColor: AppColors.mysticPurple,
                  onTap: () {
                    AudioManager().playSfx('audio/magic_start.mp3');
                    Navigator.push(context, _createRoute(VirtualDrawScreen(topic: selectedTopic, spread: selectedSpread, lang: currentLanguage)));
                  },
                  child: _buildActionButton(
                    icon: Icons.touch_app,
                    label: tr(currentLanguage, '线上虚拟抽牌 (3D翻牌)', 'Virtual draw (3D flip)', 'Cabutan Maya (Balikan 3D)'),
                    colors: const [Color(0xFF8E54E9), Color(0xFF4776E6)],
                  ),
                ),
                const SizedBox(height: 16),
                GlowButton(
                  glowColor: const Color(0xFF283593),
                  onTap: () {
                    AudioManager().playSfx('audio/magic_start.mp3');
                    Navigator.push(context, _createRoute(ManualDrawScreen(topic: selectedTopic, spread: selectedSpread, lang: currentLanguage)));
                  },
                  child: _buildActionButton(
                    icon: Icons.view_module,
                    label: tr(currentLanguage, '现实自主选牌 (手动录入)', 'Manual card entry', 'Pilihan Kad Manual'),
                    colors: const [Color(0xFF3949AB), Color(0xFF1A237E)], 
                  ),
                ),
                const SizedBox(height: 50),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButton({required IconData icon, required String label, required List<Color> colors}) {
    return Container(
      height: 60,
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: colors, begin: Alignment.topLeft, end: Alignment.bottomRight),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white.withOpacity(0.15), width: 1),
      ),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: Colors.white, size: 24),
            const SizedBox(width: 12),
            Text(
              label,
              style: const TextStyle(
                fontSize: 17, color: Colors.white, fontWeight: FontWeight.w600, letterSpacing: 1.2,
                shadows: [Shadow(color: Colors.black45, blurRadius: 6, offset: Offset(0, 2))],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= 新增：历史记录界面 =================
class HistoryScreen extends StatelessWidget {
  final AppLanguage lang;
  const HistoryScreen({Key? key, required this.lang}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(lang, '灵境档案 (历史)', 'Divination History', 'Rekod Sejarah')),
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.bgTop, AppColors.bgBottom]),
        ),
        child: ValueListenableBuilder<Box<ReadingRecord>>(
          valueListenable: Hive.box<ReadingRecord>('reading_history').listenable(),
          builder: (context, box, _) {
            if (box.isEmpty) {
              return Center(
                child: Text(
                  tr(lang, '尚未留下灵境足迹...', 'No records found in the realm...', 'Tiada rekod ditemui...'),
                  style: const TextStyle(color: Colors.white54, fontSize: 16),
                ),
              );
            }
            
            final records = box.values.toList()..sort((a, b) => b.timestamp.compareTo(a.timestamp));
            
            return ListView.builder(
              padding: const EdgeInsets.symmetric(vertical: 16),
              itemCount: records.length,
              itemBuilder: (ctx, index) {
                final record = records[index];
                
                // 根据保存的 Zh 名字找到原始配置，若找不到则返回默认第一项防崩溃
                final topic = availableTopics.firstWhere((t) => t.zh == record.topicZh, orElse: () => availableTopics[0]);
                final spread = availableSpreads.firstWhere((s) => s.nameZh == record.spreadZh, orElse: () => availableSpreads[0]);
                final savedLang = AppLanguage.values[record.langIndex];
                
                return Dismissible(
                  key: Key(record.id),
                  direction: DismissDirection.endToStart,
                  background: Container(
                    color: Colors.redAccent.withOpacity(0.8),
                    alignment: Alignment.centerRight,
                    padding: const EdgeInsets.only(right: 20),
                    child: const Icon(Icons.delete_outline, color: Colors.white, size: 28),
                  ),
                  onDismissed: (_) {
                    box.delete(record.id);
                  },
                  child: Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: glassDecoration(borderRadius: 16, borderColor: AppColors.mysticPurpleDim),
                    child: ListTile(
                      contentPadding: const EdgeInsets.all(16),
                      title: Text(
                        topic.text(lang),
                        style: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold, fontSize: 17),
                      ),
                      subtitle: Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(spread.name(lang), style: const TextStyle(color: Colors.white70, fontSize: 14)),
                            const SizedBox(height: 6),
                            Text(formatTimestamp(record.timestamp), style: const TextStyle(color: Colors.white38, fontSize: 12)),
                          ],
                        ),
                      ),
                      trailing: const Icon(Icons.arrow_forward_ios, color: Colors.white24, size: 16),
                      onTap: () {
                        AudioManager().playSfx('audio/click.wav');
                        Navigator.push(context, _createRoute(ReadingScreen(
                          cards: cardsFromJson(record.cardsJson),
                          topic: topic,
                          spread: spread,
                          lang: savedLang,
                          isFromHistory: true,
                          historyAiResponse: record.aiResponse,
                        )));
                      },
                    ),
                  ),
                );
              },
            );
          },
        ),
      ),
    );
  }
}

// ================= 法阵可视化引擎 (幽邃光晕连线) =================
class SpreadVisualizer extends StatelessWidget {
  final String spreadName; 
  final List<Widget> cards;
  const SpreadVisualizer({Key? key, required this.spreadName, required this.cards}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    double canvasWidth = 320;
    double canvasHeight = 200;
    List<Widget> positions = [];

    if (spreadName.contains('圣三角')) {
      canvasWidth = 280; canvasHeight = 460;
      positions = [
        Positioned(left: 0, top: 0, child: _safeCard(0)),     
        Positioned(left: 170, top: 0, child: _safeCard(1)),   
        Positioned(left: 85, top: 230, child: _safeCard(2)),  
      ];
    } else if (spreadName.contains('大十字')) {
      canvasWidth = 340; canvasHeight = 670;
      positions = [
        Positioned(left: 120, top: 225, child: _safeCard(0)), 
        Positioned(left: 5, top: 225, child: _safeCard(1)),   
        Positioned(left: 235, top: 225, child: _safeCard(2)), 
        Positioned(left: 120, top: 0, child: _safeCard(3)),   
        Positioned(left: 120, top: 450, child: _safeCard(4)), 
      ];
    } else if (spreadName.contains('二择一')) {
      canvasWidth = 340; canvasHeight = 600;
      positions = [
        Positioned(left: 120, top: 400, child: _safeCard(0)), 
        Positioned(left: 40, top: 200, child: _safeCard(1)),  
        Positioned(left: 200, top: 200, child: _safeCard(2)), 
        Positioned(left: 0, top: 0, child: _safeCard(3)),     
        Positioned(left: 240, top: 0, child: _safeCard(4)),   
      ];
    } else if (spreadName.contains('凯尔特')) {
      canvasWidth = 480; canvasHeight = 1000; 
      positions = [
        Positioned(left: 120, top: 320, child: _safeCard(0)), 
        Positioned(left: 120, top: 360, child: _safeCard(1)), 
        Positioned(left: 120, top: 600, child: _safeCard(2)), 
        Positioned(left: 10,  top: 320, child: _safeCard(3)), 
        Positioned(left: 120, top: 40,  child: _safeCard(4)), 
        Positioned(left: 230, top: 320, child: _safeCard(5)), 
        Positioned(left: 370, top: 760, child: _safeCard(6)), 
        Positioned(left: 370, top: 520, child: _safeCard(7)), 
        Positioned(left: 370, top: 280, child: _safeCard(8)), 
        Positioned(left: 370, top: 40,  child: _safeCard(9)), 
      ];
    } else {
      return Wrap(spacing: 10, runSpacing: 10, children: cards); 
    }

    return FittedBox(
      fit: BoxFit.contain,
      child: SizedBox(
        width: canvasWidth,
        height: canvasHeight,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            if (cards.length >= 2) _buildLines(spreadName, canvasWidth, canvasHeight),
            ...positions,
          ],
        ),
      ),
    );
  }

  Widget _buildLines(String name, double w, double h) {
    List<List<Offset>> segments = [];
    if (name.contains('圣三角')) {
      segments = [ const [Offset(47.5, 107.5), Offset(217.5, 107.5)], const [Offset(47.5, 107.5), Offset(132.5, 337.5)], const [Offset(217.5, 107.5), Offset(132.5, 337.5)] ];
    } else if (name.contains('大十字')) {
      segments = [ const [Offset(167.5, 332.5), Offset(52.5, 332.5)], const [Offset(167.5, 332.5), Offset(282.5, 332.5)], const [Offset(167.5, 332.5), Offset(167.5, 107.5)], const [Offset(167.5, 332.5), Offset(167.5, 557.5)] ];
    } else if (name.contains('二择一')) {
      segments = [ const [Offset(167.5, 507.5), Offset(87.5, 307.5)], const [Offset(167.5, 507.5), Offset(247.5, 307.5)], const [Offset(87.5, 307.5), Offset(47.5, 107.5)], const [Offset(247.5, 307.5), Offset(287.5, 107.5)] ];
    }
    return CustomPaint(painter: _DashedLinePainter(segments: segments), size: Size(w, h));
  }

  Widget _safeCard(int index) => index < cards.length ? cards[index] : const SizedBox(width: 95, height: 215);
}

class _DashedLinePainter extends CustomPainter {
  final List<List<Offset>> segments;
  _DashedLinePainter({required this.segments});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.mysticPurple.withOpacity(0.35)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;
    const dashWidth = 6.0;
    const dashSpace = 4.0;

    for (var seg in segments) {
      if (seg.length == 2) _drawDashedLine(canvas, seg[0], seg[1], paint, dashWidth, dashSpace);
    }
  }

  void _drawDashedLine(Canvas canvas, Offset start, Offset end, Paint paint, double dashWidth, double dashSpace) {
    double distance = (end - start).distance;
    if (distance <= 0) return; 
    
    double drawLength = dashWidth;
    double currentDistance = 0;
    while (currentDistance < distance) {
      double t1 = currentDistance / distance;
      double t2 = min((currentDistance + drawLength) / distance, 1.0);
      canvas.drawLine(Offset.lerp(start, end, t1)!, Offset.lerp(start, end, t2)!, paint);
      currentDistance += dashWidth + dashSpace;
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ================= 2. 线上虚拟抽牌 =================
class VirtualDrawScreen extends StatefulWidget {
  final Topic topic;
  final SpreadConfig spread;
  final AppLanguage lang;

  const VirtualDrawScreen({Key? key, required this.topic, required this.spread, required this.lang}) : super(key: key);

  @override
  _VirtualDrawScreenState createState() => _VirtualDrawScreenState();
}

class _VirtualDrawScreenState extends State<VirtualDrawScreen> {
  List<DrawnCard> drawnCards = [];
  int flippedCount = 0;

  @override
  void initState() {
    super.initState();
    final deck = List<TarotCard>.from(tarotDeck)..shuffle();
    for (int i = 0; i < widget.spread.positions(widget.lang).length; i++) {
      drawnCards.add(DrawnCard(
        card: deck[i],
        isReversed: Random().nextBool(),
        positionMeaning: widget.spread.positions(widget.lang)[i],
      ));
    }
  }

  void onCardFlipped() {
    setState(() => flippedCount++);
    HapticFeedback.heavyImpact(); 
    AudioManager().playSfx('audio/card_flip.mp3');
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> cardWidgets = List.generate(drawnCards.length, (index) {
      bool isCrossed = (widget.spread.nameZh.contains('凯尔特') && index == 1);
      
      return SizedBox(
        width: 95, height: 215,
        child: Column(
          children: [
            Container(
              height: 35, alignment: Alignment.center,
              child: Text(drawnCards[index].positionMeaning, 
                style: const TextStyle(
                  color: AppColors.gold, fontSize: 12, fontWeight: FontWeight.bold, 
                  shadows: [Shadow(color: AppColors.goldGlow, blurRadius: 6)]
                ),
                textAlign: TextAlign.center, maxLines: 2,
              ),
            ),
            Expanded(
              child: TarotCardWidget(
                drawnCard: drawnCards[index],
                onFlipped: onCardFlipped,
                isCrossed: isCrossed,
              ),
            ),
          ],
        ),
      );
    });

    return Scaffold(
      appBar: AppBar(title: Text(widget.spread.name(widget.lang), style: const TextStyle(fontSize: 18))),
      body: Container(
        width: double.infinity,
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.bgTop, AppColors.bgBottom]),
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(15.0),
              child: Text(
                widget.lang == AppLanguage.en
                    ? 'Focus on your question about 【${widget.topic.text(widget.lang)}】 and flip the cards in order.'
                    : widget.lang == AppLanguage.ms 
                    ? 'Tumpukan pada soalan anda tentang 【${widget.topic.text(widget.lang)}】 dan terbalikkan kad mengikut urutan.'
                    : '冥想关于【${widget.topic.text(widget.lang)}】的问题，依次翻开下方阵法中的卡牌',
                style: const TextStyle(fontSize: 15, color: Colors.white70, shadows: [Shadow(color: AppColors.mysticPurpleDim, blurRadius: 8)]),
                textAlign: TextAlign.center,
              ),
            ),
            
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                child: Center(
                  child: SpreadVisualizer(spreadName: widget.spread.nameZh, cards: cardWidgets),
                ),
              ),
            ),
            
            if (flippedCount == widget.spread.positions(widget.lang).length)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                child: GlowButton(
                  glowColor: AppColors.gold,
                  onTap: () => Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ReadingScreen(cards: drawnCards, topic: widget.topic, spread: widget.spread, lang: widget.lang))),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(colors: [Color(0xFFE8C37C), Color(0xFFA67C00)]),
                      borderRadius: BorderRadius.circular(30),
                    ),
                    child: Center(
                      child: Text(
                        widget.lang == AppLanguage.en ? '✨ Reveal the reading' : widget.lang == AppLanguage.ms ? '✨ Dedahkan bacaan' : '✨ 揭晓天机',
                        style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
                      ),
                    ),
                  ),
                ),
              )
          ],
        ),
      ),
    );
  }
}

class TarotCardWidget extends StatefulWidget {
  final DrawnCard drawnCard; 
  final VoidCallback onFlipped; 
  final bool isCrossed;
  
  const TarotCardWidget({Key? key, required this.drawnCard, required this.onFlipped, this.isCrossed = false}) : super(key: key);
  
  @override 
  _TarotCardWidgetState createState() => _TarotCardWidgetState();
}

class _TarotCardWidgetState extends State<TarotCardWidget> with TickerProviderStateMixin {
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;
  bool _isFront = false;
  
  late AnimationController _glowBurstController;
  late Animation<double> _glowBurstAnimation;
  late AnimationController _backGlowController;

  @override 
  void initState() {
    super.initState();
    _flipController = AnimationController(vsync: this, duration: const Duration(milliseconds: 750));
    _flipAnimation = Tween<double>(begin: 0, end: 1).animate(CurvedAnimation(parent: _flipController, curve: Curves.easeOutBack));
    
    _glowBurstController = AnimationController(vsync: this, duration: const Duration(milliseconds: 800));
    _glowBurstAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(CurvedAnimation(parent: _glowBurstController, curve: Curves.easeOut));
    _backGlowController = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();
  }

  void _flipCard() {
    if (!_isFront) {
      _flipController.forward();
      _isFront = true;
      widget.onFlipped();
      Future.delayed(const Duration(milliseconds: 350), () {
        if (mounted) _glowBurstController.forward(from: 0.0);
      });
    }
  }

  @override 
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _flipAnimation,
      builder: (context, child) {
        final angle = _flipAnimation.value * pi;
        final isUnderBack = angle > pi / 2;
        
        Widget cardUI;
        if (isUnderBack) {
          cardUI = Transform(
            transform: Matrix4.identity()..rotateY(pi)..rotateZ(widget.drawnCard.isReversed ? pi : 0),
            alignment: Alignment.center,
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.gold, width: 1.5),
                boxShadow: const [BoxShadow(color: AppColors.mysticPurpleDim, blurRadius: 16, spreadRadius: 1)]
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.asset('assets/images/${widget.drawnCard.card.img}', fit: BoxFit.cover, errorBuilder: (context, error, stackTrace) => Container(color: Colors.grey[900])),
              ),
            ),
          );
        } else {
          cardUI = Container(
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                begin: Alignment.topLeft, end: Alignment.bottomRight,
                colors: [AppColors.cardBackLight, AppColors.cardBackDark],
              ),
              border: Border.all(color: AppColors.gold.withOpacity(0.5), width: 1.5),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(color: AppColors.gold.withOpacity(0.2), blurRadius: 10, spreadRadius: 1),
                const BoxShadow(color: Colors.black45, blurRadius: 6, offset: Offset(2, 4)),
              ],
            ),
            child: Stack(
              children: [
                Center(child: Icon(Icons.auto_awesome, color: AppColors.mysticPurple.withOpacity(0.8), size: 40)),
                Positioned(top: 8, left: 8, child: Icon(Icons.star, color: AppColors.gold.withOpacity(0.4), size: 12)),
                Positioned(bottom: 8, right: 8, child: Icon(Icons.star, color: AppColors.gold.withOpacity(0.4), size: 12)),
                Center(
                  child: RotationTransition(
                    turns: _backGlowController,
                    child: Container(
                      width: 65, height: 65,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.gold.withOpacity(0.4), width: 1.5),
                        boxShadow: [BoxShadow(color: AppColors.gold.withOpacity(0.15), blurRadius: 10)],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        }
        
        if (widget.isCrossed) cardUI = Transform.rotate(angle: pi / 2, child: cardUI);
        
        return Stack(
          alignment: Alignment.center,
          children: [
            GestureDetector(onTap: _flipCard, child: cardUI),
            if (_isFront)
              AnimatedBuilder(
                animation: _glowBurstAnimation,
                builder: (_, child) {
                  final burstAlpha = (0.7 * (1 - _glowBurstAnimation.value)).clamp(0.0, 1.0);
                  return Opacity(
                    opacity: 1.0 - _glowBurstAnimation.value,
                    child: Container(
                      width: 95, height: 160,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: AppColors.cyanGlow.withOpacity(burstAlpha),
                            blurRadius: 40 * _glowBurstAnimation.value + 15,
                            spreadRadius: 25 * _glowBurstAnimation.value,
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
          ]
        );
      },
    );
  }

  @override 
  void dispose() { 
    _flipController.stop();
    _glowBurstController.stop();
    _backGlowController.stop();
    _flipController.dispose(); 
    _glowBurstController.dispose();
    _backGlowController.dispose(); 
    super.dispose(); 
  }
}

// ================= 3. 手动录入模式 =================
class ManualDrawScreen extends StatefulWidget {
  final Topic topic;
  final SpreadConfig spread;
  final AppLanguage lang;

  const ManualDrawScreen({Key? key, required this.topic, required this.spread, required this.lang}) : super(key: key);

  @override
  _ManualDrawScreenState createState() => _ManualDrawScreenState();
}

class _ManualDrawScreenState extends State<ManualDrawScreen> {
  List<DrawnCard> selectedCards = [];

  void _selectCard(TarotCard card) {
    if (selectedCards.length >= widget.spread.positions(widget.lang).length) return;
    
    AudioManager().playSfx('audio/click.wav');

    final int currentIndex = selectedCards.length;
    final String currentPositionMeaning = widget.spread.positions(widget.lang)[currentIndex];

    showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: AppColors.glassBg.withOpacity(0.95),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20), side: const BorderSide(color: AppColors.gold, width: 1)),
          title: Text(
            '【${card.name(widget.lang)}】' + (widget.lang == AppLanguage.en ? ' State?' : widget.lang == AppLanguage.ms ? ' Keadaan?' : '的状态是？'), 
            style: const TextStyle(color: AppColors.gold, shadows: [Shadow(color: AppColors.goldGlow, blurRadius: 8)])
          ),
          content: Text(
            widget.lang == AppLanguage.en ? 'Recall the upright or reversed state of this card when you drew it.' 
            : widget.lang == AppLanguage.ms ? 'Ingat kembali keadaan tegak atau terbalik kad ini semasa anda mencabutnya di dunia nyata.'
            : '请回忆你在现实中抽到这张牌时的正逆位状态。', 
            style: const TextStyle(color: Colors.white70)
          ),
          actions: [
            TextButton(
              onPressed: () {
                setState(() => selectedCards.add(DrawnCard(card: card, isReversed: false, positionMeaning: currentPositionMeaning)));
                Navigator.pop(context);
                _checkFinish();
              },
              child: Text(widget.lang == AppLanguage.en ? 'Upright' : widget.lang == AppLanguage.ms ? 'Tegak' : '正位', style: const TextStyle(color: Colors.white, fontSize: 16)),
            ),
            TextButton(
              onPressed: () {
                setState(() => selectedCards.add(DrawnCard(card: card, isReversed: true, positionMeaning: currentPositionMeaning)));
                Navigator.pop(context);
                _checkFinish();
              },
              child: Text(widget.lang == AppLanguage.en ? 'Reversed' : widget.lang == AppLanguage.ms ? 'Terbalik' : '逆位', style: const TextStyle(color: Colors.redAccent, fontSize: 16)),
            ),
          ],
        );
      },
    );
  }

  void _checkFinish() {
    if (selectedCards.length == widget.spread.positions(widget.lang).length) {
      Future.delayed(const Duration(milliseconds: 600), () {
        Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => ReadingScreen(cards: selectedCards, topic: widget.topic, spread: widget.spread, lang: widget.lang)));
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    int maxCards = widget.spread.positions(widget.lang).length;
    
    List<Widget> miniMapCards = List.generate(maxCards, (index) {
      bool isCrossed = (widget.spread.nameZh.contains('凯尔特') && index == 1);
      
      if (index < selectedCards.length) {
        final c = selectedCards[index];
        Widget img = Transform.rotate(
          angle: c.isReversed ? pi : 0,
          child: Image.asset('assets/images/${c.card.img}', fit: BoxFit.cover, errorBuilder: (ctx, err, stack) => Container(color: Colors.grey[900])),
        );
        if (isCrossed) img = Transform.rotate(angle: pi / 2, child: img);

        return SizedBox(
          width: 95, height: 215,
          child: Column(
            children: [
              Container(
                height: 35, alignment: Alignment.center,
                child: Text(c.positionMeaning, style: const TextStyle(color: AppColors.gold, fontSize: 12, fontWeight: FontWeight.bold, shadows: [Shadow(color: AppColors.goldGlow, blurRadius: 6)]), textAlign: TextAlign.center, maxLines: 2),
              ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(color: Color(0xFF1A1235), border: Border.all(color: AppColors.gold, width: 1.5), borderRadius: BorderRadius.circular(6)),
                  child: ClipRRect(borderRadius: BorderRadius.circular(4), child: img),
                ),
              ),
            ],
          ),
        );
      } else {
        bool isCurrent = index == selectedCards.length;
        Widget placeholder = Container(
          decoration: BoxDecoration(
            color: isCurrent ? AppColors.mysticPurple.withOpacity(0.2) : Colors.black38,
            border: Border.all(color: isCurrent ? AppColors.mysticPurple : Colors.white24, width: isCurrent ? 2 : 1),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Center(
            child: Icon(Icons.add_circle_outline, color: isCurrent ? AppColors.mysticPurple : Colors.white24, size: 30),
          ),
        );
        if (isCrossed) placeholder = Transform.rotate(angle: pi / 2, child: placeholder);

        return SizedBox(
          width: 95, height: 215,
          child: Column(
            children: [
              Container(
                height: 35, alignment: Alignment.center,
                child: Text(widget.spread.positions(widget.lang)[index], style: TextStyle(color: isCurrent ? AppColors.gold : Colors.white54, fontSize: 12, fontWeight: FontWeight.bold), textAlign: TextAlign.center, maxLines: 2),
              ),
              Expanded(child: placeholder),
            ],
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.lang == AppLanguage.en ? 'Manual Entry (${selectedCards.length}/$maxCards)' 
          : widget.lang == AppLanguage.ms ? 'Pilihan Manual (${selectedCards.length}/$maxCards)'
          : '选牌录入 (${selectedCards.length}/$maxCards)'
        )
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.bgTop, AppColors.bgBottom]),
        ),
        child: Column(
          children: [
            Container(
              height: widget.spread.nameZh.contains('凯尔特') ? 380 : 250,
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10),
              decoration: const BoxDecoration(
                color: Color(0x1A000000),
                border: Border(bottom: BorderSide(color: Colors.white10)),
              ),
              child: SpreadVisualizer(spreadName: widget.spread.nameZh, cards: miniMapCards), 
            ),
            
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Text(
                selectedCards.length < maxCards
                  ? (widget.lang == AppLanguage.en
                      ? '👉 Select the card for 【${widget.spread.positions(widget.lang)[selectedCards.length]}】'
                      : widget.lang == AppLanguage.ms
                      ? '👉 Pilih kad untuk 【${widget.spread.positions(widget.lang)[selectedCards.length]}】'
                      : '👉 请在下方选择【${widget.spread.positions(widget.lang)[selectedCards.length]}】的牌')
                  : (widget.lang == AppLanguage.en ? '✨ Spread ready, reading...' 
                     : widget.lang == AppLanguage.ms ? '✨ Susunan sedia, mula bacaan...'
                     : '✨ 阵法就绪，正在开启解读...'),
                style: const TextStyle(color: AppColors.cyanGlow, fontSize: 16, fontWeight: FontWeight.bold, shadows: [Shadow(color: AppColors.mysticPurple, blurRadius: 8)]),
                textAlign: TextAlign.center,
              ),
            ),
            
            Expanded(
              child: GridView.builder(
                padding: const EdgeInsets.all(12),
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 3, childAspectRatio: 0.6, crossAxisSpacing: 12, mainAxisSpacing: 12),
                itemCount: tarotDeck.length,
                itemBuilder: (context, index) {
                  final card = tarotDeck[index];
                  bool isPicked = selectedCards.any((c) => c.card.nameZh == card.nameZh);
                  
                  return GestureDetector(
                    onTap: isPicked ? null : () => _selectCard(card),
                    child: Opacity(
                      opacity: isPicked ? 0.25 : 1.0,
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(6),
                        child: GridTile(
                          footer: Container(
                            color: Colors.black87,
                            padding: const EdgeInsets.symmetric(vertical: 4),
                            child: Text(card.name(widget.lang), textAlign: TextAlign.center, style: const TextStyle(fontSize: 10, color: Colors.white)),
                          ),
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              Image.asset('assets/images/${card.img}', fit: BoxFit.cover,
                                 errorBuilder: (c, e, s) => Container(color: Colors.grey[900], child: const Center(child: Icon(Icons.image_not_supported, color: Colors.white24))),
                              ),
                              if (isPicked)
                                Container(
                                  color: Colors.black54,
                                  child: const Center(child: Icon(Icons.check_circle, color: AppColors.gold, size: 40)),
                                )
                            ],
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================= 打字机效果 Widget =================
class TypewriterText extends StatefulWidget {
  final String text; final Duration speed; final TextStyle? style; final VoidCallback? onFinished; final MarkdownStyleSheet? styleSheet;
  const TypewriterText({Key? key, required this.text, this.speed = const Duration(milliseconds: 30), this.style, this.styleSheet, this.onFinished}) : super(key: key);
  @override _TypewriterTextState createState() => _TypewriterTextState();
}
class _TypewriterTextState extends State<TypewriterText> {
  String _displayed = "";
  Timer? _timer;
  int _index = 0;
  @override void initState() {
    super.initState();
    _start();
  }
  void _start() {
    _timer = Timer.periodic(widget.speed, (timer) {
      if (!mounted) { timer.cancel(); return; }
      if (_index < widget.text.length) {
        setState(() { _displayed += widget.text[_index]; _index++; });
      } else {
        timer.cancel();
        widget.onFinished?.call();
      }
    });
  }
  @override void dispose() {
    _timer?.cancel();
    super.dispose();
  }
  @override Widget build(BuildContext context) {
    return MarkdownBody(
      data: _displayed,
      styleSheet: widget.styleSheet ?? MarkdownStyleSheet(
        p: widget.style ?? const TextStyle(fontSize: 15, height: 1.8, color: Colors.white70, letterSpacing: 0.5),
        pPadding: const EdgeInsets.only(bottom: 12),
        strong: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold),
        h1: const TextStyle(color: AppColors.gold, fontSize: 24, fontWeight: FontWeight.bold),
        h1Padding: const EdgeInsets.only(top: 16, bottom: 8),
        h2: const TextStyle(color: AppColors.gold, fontSize: 20, fontWeight: FontWeight.bold),
        h2Padding: const EdgeInsets.only(top: 16, bottom: 8),
        h3: const TextStyle(color: AppColors.gold, fontSize: 18, fontWeight: FontWeight.bold),
        h3Padding: const EdgeInsets.only(top: 16, bottom: 8),
        listBullet: const TextStyle(color: AppColors.gold, fontSize: 16),
        listBulletPadding: const EdgeInsets.only(top: 4),
      ),
    );
  }
}

// ================= 卷轴解读面板 Painter =================
class ScrollBorderPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.gold.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawLine(Offset(8, 20), Offset(8, size.height - 20), paint);
    canvas.drawCircle(Offset(8, 20), 4, paint);
    canvas.drawCircle(Offset(8, size.height - 20), 4, paint);
    canvas.drawLine(Offset(size.width - 8, 20), Offset(size.width - 8, size.height - 20), paint);
    canvas.drawCircle(Offset(size.width - 8, 20), 4, paint);
    canvas.drawCircle(Offset(size.width - 8, size.height - 20), 4, paint);
    canvas.drawLine(Offset(14, 14), Offset(size.width - 14, 14), paint);
    canvas.drawLine(Offset(14, size.height - 14), Offset(size.width - 14, size.height - 14), paint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ================= 4. 解牌结果页面 =================
class ReadingScreen extends StatefulWidget {
  final List<DrawnCard> cards;
  final Topic topic;
  final SpreadConfig spread; 
  final AppLanguage lang;
  
  // 新增的历史相关参数
  final bool isFromHistory;
  final String? historyAiResponse;

  const ReadingScreen({
    Key? key, 
    required this.cards, 
    required this.topic, 
    required this.spread, 
    required this.lang,
    this.isFromHistory = false,
    this.historyAiResponse,
  }) : super(key: key);

  @override
  _ReadingScreenState createState() => _ReadingScreenState();
}

class _ReadingScreenState extends State<ReadingScreen> with TickerProviderStateMixin {
  String aiResponse = "";
  bool isGenerating = false;
  bool showAI = false;
  bool isFinished = false;
  bool _isError = false; // 新增：标识是否遇到 API 请求失败

  final String _proxyUrl = 'https://tai-taro.vercel.app/api/gemini';
  late AnimationController _magicCircleController;

  @override
  void initState() {
    super.initState();
    _magicCircleController = AnimationController(vsync: this, duration: const Duration(seconds: 4))..repeat();

    // 如果是通过历史记录进入，则直接展示结果
    if (widget.isFromHistory) {
      showAI = true;
      isGenerating = false;
      isFinished = true;
      aiResponse = widget.historyAiResponse ?? "";
    }
  }

  @override
  void dispose() {
    _magicCircleController.dispose();
    super.dispose();
  }

  Future<void> _saveToHistory() async {
    if (widget.isFromHistory) return;

    try {
      final box = Hive.box<ReadingRecord>('reading_history');
      final record = ReadingRecord(
        id: '${DateTime.now().millisecondsSinceEpoch}-${Random().nextInt(10000)}',
        timestamp: DateTime.now().millisecondsSinceEpoch,
        topicZh: widget.topic.zh,
        spreadZh: widget.spread.nameZh,
        cardsJson: cardsToJson(widget.cards),
        aiResponse: aiResponse,
        langIndex: widget.lang.index,
      );
      await box.put(record.id, record);   // 已添加 await
    } catch (e) {
      debugPrint('Save history failed: $e');
    }
  }

  Future<void> _askAI() async {
    setState(() {
      showAI = true;
      isGenerating = true;
      _isError = false; // 每次请求时重置错误状态
      aiResponse = widget.lang == AppLanguage.en
        ? "🔮 Connecting to the oracle, your tarot master is preparing the reading...\n\n"
        : widget.lang == AppLanguage.ms 
        ? "🔮 Menyambung ke alam ramalan, pakar tarot anda sedang menyediakan bacaan...\n\n"
        : "🔮 灵界连结中，占卜师正在为你综合解读...\n\n";
    });
    
    String prompt = "";
    if (widget.lang == AppLanguage.en) {
      prompt = "You are a deeply intuitive, psychologically astute, and compassionate tarot master. IMPORTANT: YOU MUST ANSWER ENTIRELY IN ENGLISH.\n" +
        "The user asked about 【${widget.topic.text(widget.lang)}】 using the 【${widget.spread.name(widget.lang)}】.\n\n" +
        "Card draw details are as follows:\n";
    } else if (widget.lang == AppLanguage.ms) {
      prompt = "Anda adalah seorang pakar tarot yang sangat intuitif, peka secara psikologi, dan penuh belas kasihan. PENTING: ANDA MESTI MENJAWAB SEPENUHNYA DALAM BAHASA MELAYU (MALAY).\n" +
        "Pengguna bertanya tentang 【${widget.topic.text(widget.lang)}】 menggunakan 【${widget.spread.name(widget.lang)}】.\n\n" +
        "Butiran cabutan kad adalah seperti berikut:\n";
    } else {
      prompt = "你是一位极度神秘、深谙心理学且充满同理心的资深塔罗牌大师。请务必使用中文进行解答。\n" +
        "用户向你求问关于【${widget.topic.text(widget.lang)}】的发展，使用的是【${widget.spread.name(widget.lang)}】。\n\n" +
        "抽牌情况如下：\n";
    }

    for (var c in widget.cards) {
      String status = c.isReversed 
          ? (widget.lang == AppLanguage.en ? 'Reversed' : widget.lang == AppLanguage.ms ? 'Terbalik' : '逆位') 
          : (widget.lang == AppLanguage.en ? 'Upright' : widget.lang == AppLanguage.ms ? 'Tegak' : '正位');
          
      if (widget.lang == AppLanguage.en) {
         prompt += "- At position [${c.positionMeaning}], the card drawn is [${c.card.name(widget.lang)}] (${status})\n";
      } else if (widget.lang == AppLanguage.ms) {
         prompt += "- Di posisi [${c.positionMeaning}], kad yang dicabut adalah [${c.card.name(widget.lang)}] (${status})\n";
      } else {
         prompt += "- 在【${c.positionMeaning}】位置，抽到【${c.card.name(widget.lang)}（$status）】\n";
      }
    }

    if (widget.lang == AppLanguage.en) {
      prompt += "\nPlease answer using the following structure IN ENGLISH ONLY, using Markdown formatting (bold key points, use paragraphs):\n\n" +
        "### 🌟 Energy Sensing\n(Reveal the overall field around ${widget.topic.text(widget.lang)})\n\n" +
        "### 🃏 Spread Analysis\n(Dive into how each position and card interacts)\n\n" +
        "### 💡 Cosmic Guidance\n(Concrete action advice and healing words)\n\n" +
        "Write with graceful clarity and empathetic insight. Ensure the entire response is in English.";
    } else if (widget.lang == AppLanguage.ms) {
      prompt += "\nSila jawab menggunakan struktur berikut DALAM BAHASA MELAYU SAHAJA, menggunakan format Markdown (tebalkan isi penting, gunakan perenggan):\n\n" +
        "### 🌟 Pengesanan Tenaga\n(Dedahkan medan keseluruhan di sekitar ${widget.topic.text(widget.lang)})\n\n" +
        "### 🃏 Analisis Susunan\n(Kaji interaksi setiap kedudukan dan kad)\n\n" +
        "### 💡 Panduan Kosmik\n(Nasihat tindakan konkrit dan kata-kata penyembuhan)\n\n" +
        "Tulis dengan kejelasan yang anggun dan empati. Pastikan keseluruhan jawapan adalah dalam Bahasa Melayu.";
    } else {
      prompt += "\n请按照以下结构使用 Markdown 格式排版解答（加粗重点内容，使用分段）：\n\n" +
        "### 🌟 能量感知\n(点破当前【${widget.topic.text(widget.lang)}】的整体磁场)\n\n" +
        "### 🃏 牌阵深度拆解\n(根据法阵的位置和牌面，深入分析它们相互的影响)\n\n" +
        "### 💡 宇宙指引\n(给出具体的行动建议和治愈的寄语)\n\n" +
        "请使用优雅清晰的排版，语气洞悉人心。";
    }

    try {
      final response = await http.post(
        Uri.parse(_proxyUrl),
        headers: {'Content-Type': 'application/json', 'x-app-version': '2.1.0'},
        body: jsonEncode({"prompt": prompt}),
      );
      
      if (!mounted) return;

      if (response.statusCode == 200) {
        final data = jsonDecode(utf8.decode(response.bodyBytes));
        setState(() {
          aiResponse = data['text'] ?? (
            widget.lang == AppLanguage.en ? 'The reader is unable to interpret right now, please try again later.' 
            : widget.lang == AppLanguage.ms ? 'Pakar tarot tidak dapat mentafsir sekarang, sila cuba lagi nanti.'
            : '占卜师暂时无法解读，请稍后再试。'
          );
          _isError = false;
        });
        // 成功获取解牌后保存至历史记录
        _saveToHistory();
      } else {
        setState(() {
          aiResponse = "⚠️ API Failed (${response.statusCode})\n\n${response.body}";
          _isError = true;
        });
      }
    } catch (e) {
      if (!mounted) return; 
      setState(() {
        aiResponse = "⚠️ Network issue or Master disconnected. ($e)";
        _isError = true;
      });
    } finally {
      if (mounted) setState(() => isGenerating = false);
    }
  }

  MarkdownStyleSheet get _mdStyleSheet => MarkdownStyleSheet(
    p: const TextStyle(fontSize: 15, height: 1.8, color: Colors.white70, letterSpacing: 0.5),
    pPadding: const EdgeInsets.only(bottom: 12),
    strong: const TextStyle(color: AppColors.gold, fontWeight: FontWeight.bold),
    h1: const TextStyle(color: AppColors.gold, fontSize: 24, fontWeight: FontWeight.bold),
    h1Padding: const EdgeInsets.only(top: 16, bottom: 8),
    h2: const TextStyle(color: AppColors.gold, fontSize: 20, fontWeight: FontWeight.bold),
    h2Padding: const EdgeInsets.only(top: 16, bottom: 8),
    h3: const TextStyle(color: AppColors.gold, fontSize: 18, fontWeight: FontWeight.bold),
    h3Padding: const EdgeInsets.only(top: 16, bottom: 8),
    listBullet: const TextStyle(color: AppColors.gold, fontSize: 16),
    listBulletPadding: const EdgeInsets.only(top: 4),
  );

  Widget _buildTypewriterText() {
    if (aiResponse.isEmpty) return const SizedBox();
    
    // 如果是历史记录，直接展示完整 Markdown 排版，跳过打字动画
    return MarkdownBody(
      data: aiResponse,
      styleSheet: _mdStyleSheet,
    );
  }

  @override
  Widget build(BuildContext context) {
    List<Widget> miniMapCards = List.generate(widget.cards.length, (index) {
      bool isCrossed = (widget.spread.nameZh.contains('凯尔特') && index == 1);
      final c = widget.cards[index];
      
      Widget img = Transform.rotate(
        angle: c.isReversed ? pi : 0,
        child: Image.asset('assets/images/${c.card.img}', fit: BoxFit.cover, errorBuilder: (ctx, err, stack) => Container(color: Colors.grey[900])),
      );
      if (isCrossed) img = Transform.rotate(angle: pi / 2, child: img);

      return SizedBox(
        width: 95, height: 215,
        child: Column(
          children: [
            Container(
              height: 35, alignment: Alignment.center,
              child: Text(c.positionMeaning, style: const TextStyle(color: AppColors.gold, fontSize: 12, fontWeight: FontWeight.bold, shadows: [Shadow(color: AppColors.goldGlow, blurRadius: 6)]), textAlign: TextAlign.center, maxLines: 2),
            ),
            Expanded(
              child: Container(
                decoration: BoxDecoration(border: Border.all(color: AppColors.gold, width: 1.5), borderRadius: BorderRadius.circular(4)),
                child: ClipRRect(borderRadius: BorderRadius.circular(2), child: img),
              ),
            ),
          ],
        ),
      );
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          widget.lang == AppLanguage.en ? '【${widget.topic.text(widget.lang)}】 Report' 
          : widget.lang == AppLanguage.ms ? 'Laporan 【${widget.topic.text(widget.lang)}】'
          : '【${widget.topic.text(widget.lang)}】指引报告', 
        )
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [AppColors.bgTop, AppColors.bgBottom]),
        ),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // 牌阵预览
            Container(
              height: widget.spread.nameZh.contains('凯尔特') ? 380 : 250,
              padding: const EdgeInsets.symmetric(vertical: 10),
              margin: const EdgeInsets.only(bottom: 24),
              decoration: glassDecoration(borderRadius: 16),
              child: SpreadVisualizer(spreadName: widget.spread.nameZh, cards: miniMapCards), 
            ),

            // 每张牌详解
            ...widget.cards.map((c) {
              final status = c.isReversed 
                  ? (widget.lang == AppLanguage.en ? "Reversed" : widget.lang == AppLanguage.ms ? "Terbalik" : "逆位") 
                  : (widget.lang == AppLanguage.en ? "Upright" : widget.lang == AppLanguage.ms ? "Tegak" : "正位");
              final meaning = c.isReversed ? c.card.reversedMeaning(widget.lang) : c.card.uprightMeaning(widget.lang);

              return Container(
                margin: const EdgeInsets.only(bottom: 20),
                decoration: glassDecoration(borderColor: AppColors.gold), 
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Transform(
                        transform: Matrix4.identity()..rotateZ(c.isReversed ? pi : 0),
                        alignment: Alignment.center,
                        child: Container(
                          decoration: BoxDecoration(
                            border: Border.all(color: AppColors.gold, width: 1),
                            borderRadius: BorderRadius.circular(6)
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(5),
                            child: Image.asset(
                              'assets/images/${c.card.img}',
                              width: 80, height: 140, fit: BoxFit.cover,
                              errorBuilder: (ctx, err, stack) => Container(width: 80, height: 140, color: Colors.grey[900]),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 20),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '【${c.positionMeaning}】\n${c.card.name(widget.lang)}',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: AppColors.gold, height: 1.4, shadows: [Shadow(color: AppColors.goldGlow, blurRadius: 4)]),
                            ),
                            const SizedBox(height: 8),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: c.isReversed ? Colors.redAccent.withOpacity(0.15) : AppColors.cyanGlow.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(4),
                                border: Border.all(color: c.isReversed ? Colors.redAccent.withOpacity(0.5) : AppColors.cyanGlow.withOpacity(0.5), width: 1),
                              ),
                              child: Text(
                                status,
                                style: TextStyle(color: c.isReversed ? Colors.redAccent : AppColors.cyanGlow, fontWeight: FontWeight.w600, fontSize: 12),
                              ),
                            ),
                            const Divider(color: Colors.white12, height: 24),
                            Text(meaning, style: const TextStyle(fontSize: 14, height: 1.6, color: Colors.white70)),
                          ],
                        ),
                      )
                    ],
                  ),
                ),
              );
            }).toList(),

            // AI 解读区域 (卷轴面板)
            if (showAI)
              Container(
                margin: const EdgeInsets.only(top: 10, bottom: 20),
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: AppColors.glassBg, 
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(color: AppColors.mysticPurple.withOpacity(0.1), blurRadius: 20, spreadRadius: 2),
                  ],
                ),
                child: Stack(
                  children: [
                    Positioned.fill(child: CustomPaint(painter: ScrollBorderPainter())),
                    if (isGenerating)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                        child: Column(
                          children: [
                            AnimatedBuilder(
                              animation: _magicCircleController,
                              builder: (_, child) {
                                return Transform.rotate(
                                  angle: _magicCircleController.value * 2 * pi,
                                  child: CustomPaint(size: const Size(100, 100), painter: _MagicCirclePainter()),
                                );
                              },
                            ),
                            const SizedBox(height: 20),
                            Text(
                              widget.lang == AppLanguage.en ? 'Master is writing your reading...' : widget.lang == AppLanguage.ms ? 'Pakar sedang menulis bacaan anda...' : '大师正在撰写指引报告...',
                              style: const TextStyle(color: AppColors.gold, fontSize: 16, shadows: [Shadow(color: AppColors.goldGlow, blurRadius: 8)]),
                            ),
                            const SizedBox(height: 10),
                            _buildTypewriterText(),
                          ],
                        ),
                      )
                    else
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            _buildTypewriterText(),
                            
                            // 失败重试按钮 (只有在非生成状态并且遇到错误时才显示)
                            if (!isGenerating && _isError)
                              Padding(
                                padding: const EdgeInsets.only(top: 24),
                                child: Center(
                                  child: GlowButton(
                                    glowColor: AppColors.mysticPurple,
                                    borderRadius: 20,
                                    onTap: () {
                                      AudioManager().playSfx('audio/click.wav');
                                      _askAI();
                                    },
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                                      decoration: BoxDecoration(
                                        color: AppColors.mysticPurple,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          const Icon(Icons.refresh, color: Colors.white, size: 20),
                                          const SizedBox(width: 8),
                                          Text(
                                            widget.lang == AppLanguage.en ? 'Retry' 
                                            : widget.lang == AppLanguage.ms ? 'Cuba Semula' 
                                            : '重新解读',
                                            style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 15),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              )
                          ],
                        ),
                      ),
                  ],
                ),
              ),

            const SizedBox(height: 100),
          ],
        ),
      ),

      floatingActionButton: isFinished || showAI || widget.isFromHistory
          ? null
          : GlowButton(
              glowColor: AppColors.mysticPurple,
              onTap: () {
                AudioManager().playSfx('audio/magic_start.mp3');
                _askAI();
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [Color(0xFF8E54E9), Color(0xFF4776E6)]),
                  borderRadius: BorderRadius.circular(30),
                  border: Border.all(color: Colors.white.withOpacity(0.2)),
                ),
                child: Text(
                  widget.lang == AppLanguage.en ? '✨ Start AI Deep Reading' : widget.lang == AppLanguage.ms ? '✨ Mulakan Bacaan AI Mendalam' : '✨ 开启 AI 深度解牌',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 16, letterSpacing: 1.0),
                ),
              ),
            ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}

// 魔法阵绘制
class _MagicCirclePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()
      ..color = AppColors.mysticPurple.withOpacity(0.7)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    canvas.drawCircle(center, radius, paint);
    canvas.drawCircle(center, radius * 0.7, paint);
    for (int i = 0; i < 6; i++) {
      final angle = i * pi / 3;
      final dx = center.dx + cos(angle) * radius;
      final dy = center.dy + sin(angle) * radius;
      canvas.drawLine(center, Offset(dx, dy), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

// ⬇️ 完整78张塔罗牌数据（多语言）
const List<Map<String, dynamic>> rawTarotData = [
  {"number": "0", "arcana": "大阿尔卡纳", "suit": null, "img": "m00.jpg",
   "nameZh": "愚者", "nameEn": "The Fool", "nameMs": "Sang Pengembara",
   "uprightZh": "全新的开始、未知冒险。放空心思，勇敢踏上旅程，相信宇宙。",
   "uprightEn": "New beginnings, unknown adventures. Clear your mind, step forward, trust the universe.",
   "uprightMs": "Permulaan baharu, pengembaraan tanpa arah. Kosongkan fikiran, berani melangkah, percayalah pada alam semesta.",
   "reversedZh": "鲁莽、不切实际、错失良机。你的行为可能过于冲动，小心过度冒险带来的危机。",
   "reversedEn": "Reckless, impractical, missed opportunities. Beware of risks from excessive impulsiveness.",
   "reversedMs": "Gopoh, tidak realistik. Berhati-hati dengan krisis akibat tindakan terburu-buru."},
   
  {"number": "1", "arcana": "大阿尔卡纳", "suit": null, "img": "m01.jpg",
   "nameZh": "魔术师", "nameEn": "The Magician", "nameMs": "Ahli Sihir",
   "uprightZh": "创造力、行动力、化无为有。你拥有所需的所有资源，是付诸行动的最佳时机。",
   "uprightEn": "Creativity, action, manifestation. You have all resources; it's time to take action.",
   "uprightMs": "Kreativiti, tindakan, manifestasi. Anda mempunyai sumber yang cukup, tiba masanya bertindak.",
   "reversedZh": "才华未展、缺乏计划。你可能在浪费天赋，或被花言巧语蒙蔽。",
   "reversedEn": "Unused talent, poor planning. You may be wasting potential or being deceived.",
   "reversedMs": "Bakat terpendam, tiada rancangan. Anda mungkin mensia-siakan bakat atau ditipu."},
   
  {"number": "2", "arcana": "大阿尔卡纳", "suit": null, "img": "m02.jpg",
   "nameZh": "女祭司", "nameEn": "The High Priestess", "nameMs": "Pendeta Wanita",
   "uprightZh": "直觉、潜意识。顺从直觉，现在不宜向外行动，而应向内探索。",
   "uprightEn": "Intuition, subconscious. Trust your inner voice; reflect inward rather than acting outwardly.",
   "uprightMs": "Gerak hati, bawah sedar. Percaya kata hati; renung ke dalam diri bukan bertindak ke luar.",
   "reversedZh": "直觉受阻、情绪化。过度依赖表面逻辑而忽略了隐藏的真相。",
   "reversedEn": "Blocked intuition, emotional. Relying too much on surface logic, ignoring hidden truths.",
   "reversedMs": "Gerak hati tersekat, beremosi. Terlalu bergantung pada logik, mengabaikan kebenaran tersembunyi."},

  {"number": "3", "arcana": "大阿尔卡纳", "suit": null, "img": "m03.jpg",
   "nameZh": "皇后", "nameEn": "The Empress", "nameMs": "Maharani",
   "uprightZh": "丰收、母性、创造力。享受生活美好，计划即将开花结果。",
   "uprightEn": "Abundance, nurturing, creativity. Enjoy life; your plans are bearing fruit.",
   "uprightMs": "Kelimpahan, sifat keibuan, kreativiti. Nikmati hidup; usaha anda akan membuahkan hasil.",
   "reversedZh": "过度依赖、溺爱、创造力受阻。在感情或物质上过于索取。",
   "reversedEn": "Overdependence, stagnation. Being overly demanding emotionally or materially.",
   "reversedMs": "Terlalu bergantung, kebuntuan. Terlalu menuntut dari segi emosi atau material."},

  {"number": "4", "arcana": "大阿尔卡纳", "suit": null, "img": "m04.jpg",
   "nameZh": "皇帝", "nameEn": "The Emperor", "nameMs": "Maharaja",
   "uprightZh": "权力、规则、稳定的基础。需要建立纪律，用理性和意志掌控全局。",
   "uprightEn": "Authority, rules, stable foundation. Establish discipline and control the situation with logic.",
   "uprightMs": "Kuasa, peraturan, asas yang stabil. Tegakkan disiplin dan kawal keadaan secara rasional.",
   "reversedZh": "独裁、僵化、失去控制。过于固执或缺乏自律导致计划崩塌。",
   "reversedEn": "Dictatorship, rigidity, loss of control. Stubbornness leading to collapsed plans.",
   "reversedMs": "Diktator, kaku, hilang kawalan. Kedegilan yang membawa kepada kegagalan rancangan."},

  {"number": "5", "arcana": "大阿尔卡纳", "suit": null, "img": "m05.jpg",
   "nameZh": "教皇", "nameEn": "The Hierophant", "nameMs": "Mahaguru",
   "uprightZh": "传统、信仰、精神指引。遵从规则或寻找经验丰富的导师。",
   "uprightEn": "Tradition, faith, guidance. Follow the rules or seek an experienced mentor.",
   "uprightMs": "Tradisi, kepercayaan, panduan rohani. Ikuti peraturan atau cari mentor berpengalaman.",
   "reversedZh": "打破常规、盲从、挑战权威。不再受制于传统，渴望开创全新道路。",
   "reversedEn": "Rebellion, blind obedience. Breaking free from traditions to forge a new path.",
   "reversedMs": "Pemberontakan, patuh membuta tuli. Memecah tradisi untuk membina haluan baru."},

  {"number": "6", "arcana": "大阿尔卡纳", "suit": null, "img": "m06.jpg",
   "nameZh": "恋人", "nameEn": "The Lovers", "nameMs": "Kekasih",
   "uprightZh": "爱情、和谐。面临重要选择，请遵从真心，充满吸引力的关系正在展开。",
   "uprightEn": "Love, harmony, choices. Follow your heart in a major decision; an attractive bond is forming.",
   "uprightMs": "Cinta, keharmonian, pilihan. Ikut kata hati; satu ikatan menarik sedang terbentuk.",
   "reversedZh": "关系破裂、价值观冲突。感情不和，或面临选择时逃避责任。",
   "reversedEn": "Broken bond, conflicting values. Relationship disharmony or avoiding responsibility.",
   "reversedMs": "Hubungan retak, konflik nilai. Ketidakharmonian atau lari dari tanggungjawab."},

  {"number": "7", "arcana": "大阿尔卡纳", "suit": null, "img": "m07.jpg",
   "nameZh": "战车", "nameEn": "The Chariot", "nameMs": "Kereta Kuda",
   "uprightZh": "意志力、胜利。通过决心和自律克服一切阻力，成功掌控局面。",
   "uprightEn": "Willpower, victory. Overcome obstacles with determination and take control.",
   "uprightMs": "Tekad, kemenangan. Atasi rintangan dengan keazaman dan kuasai keadaan.",
   "reversedZh": "失去方向、受阻。感到失控，因内心冲突无法向前推进。",
   "reversedEn": "Lack of direction, blocked. Feeling out of control or paralyzed by inner conflicts.",
   "reversedMs": "Hilang arah, tersekat. Hilang kawalan atau lumpuh akibat konflik dalaman."},

  {"number": "8", "arcana": "大阿尔卡纳", "suit": null, "img": "m08.jpg",
   "nameZh": "力量", "nameEn": "Strength", "nameMs": "Kekuatan",
   "uprightZh": "内在力量、勇气。用温柔化解冲突，力量源于内心的平静与坚韧。",
   "uprightEn": "Inner strength, courage. Resolve conflicts with gentle compassion and resilience.",
   "uprightMs": "Kekuatan dalaman, keberanian. Selesaikan konflik dengan kelembutan dan ketabahan.",
   "reversedZh": "自我怀疑、情绪失控。对能力不自信，被恐惧和愤怒支配。",
   "reversedEn": "Self-doubt, emotional loss of control. Dominated by fear and insecurity.",
   "reversedMs": "Ragu-ragu, hilang kawalan emosi. Dikuasai oleh ketakutan dan tidak yakin diri."},

  {"number": "9", "arcana": "大阿尔卡纳", "suit": null, "img": "m09.jpg",
   "nameZh": "隐士", "nameEn": "The Hermit", "nameMs": "Pertapa",
   "uprightZh": "内省、寻找内在智慧。暂时远离喧嚣，独处能帮你找到答案。",
   "uprightEn": "Introspection, seeking inner wisdom. Step away from the noise to find your answers.",
   "uprightMs": "Muhasabah diri, mencari kebijaksanaan. Jauhkan diri dari kebisingan untuk mencari jawapan.",
   "reversedZh": "孤立、迷失。过度封闭自我陷入孤独，是时候回到人群中。",
   "reversedEn": "Isolation, lost. Over-isolation leads to loneliness; it's time to reconnect.",
   "reversedMs": "Terasing, sesat. Terlalu menyendiri membawa kesepian; masanya untuk kembali berhubung."},

  {"number": "10", "arcana": "大阿尔卡纳", "suit": null, "img": "m10.jpg",
   "nameZh": "命运之轮", "nameEn": "Wheel of Fortune", "nameMs": "Roda Nasib",
   "uprightZh": "转机、不可避免的变化。运势好转，顺应生命起伏，抓住好运。",
   "uprightEn": "Turning point, inevitable change. Luck is improving, ride the wave of destiny.",
   "uprightMs": "Titik perubahan, nasib yang berubah. Tuah memihak anda, ikuti arus takdir.",
   "reversedZh": "抗拒改变、暂时的厄运。偏离预期，耐心等待低谷过去。",
   "reversedEn": "Resisting change, temporary bad luck. Be patient and wait out the low point.",
   "reversedMs": "Menolak perubahan, nasib malang sementara. Bersabar dan tunggu fasa sukar berlalu."},

  {"number": "11", "arcana": "大阿尔卡纳", "suit": null, "img": "m11.jpg",
   "nameZh": "正义", "nameEn": "Justice", "nameMs": "Keadilan",
   "uprightZh": "公平、诚实、因果。理性的决定带来公正结果，过去的作为正产生回报。",
   "uprightEn": "Fairness, karma. Rational decisions bring just results; you reap what you sow.",
   "uprightMs": "Keadilan, karma. Keputusan rasional membawa hasil adil; anda menuai apa yang disemai.",
   "reversedZh": "不公、偏见、逃避责任。面临不公平待遇，或缺乏诚实判断。",
   "reversedEn": "Injustice, bias, evading responsibility. Facing unfair treatment or dishonesty.",
   "reversedMs": "Ketidakadilan, prejudis, lari tanggungjawab. Menghadapi ketidakadilan atau penipuan."},

  {"number": "12", "arcana": "大阿尔卡纳", "suit": null, "img": "m12.jpg",
   "nameZh": "倒吊人", "nameEn": "The Hanged Man", "nameMs": "Orang Tergantung",
   "uprightZh": "换位思考、自愿牺牲。停滞是为了更深层顿悟，放下无谓的执念。",
   "uprightEn": "New perspective, surrender. A pause for deeper enlightenment. Let go of control.",
   "uprightMs": "Perspektif baharu, pengorbanan. Jeda untuk pencerahan. Lepaskan kawalan yang sia-sia.",
   "reversedZh": "无谓的牺牲、停滞不前。在不值得的事上浪费精力，抗拒改变。",
   "reversedEn": "Useless sacrifice, stagnation. Wasting energy on unworthy causes and resisting change.",
   "reversedMs": "Pengorbanan sia-sia, kebuntuan. Membazir tenaga untuk perkara remeh dan menolak perubahan."},

  {"number": "13", "arcana": "大阿尔卡纳", "suit": null, "img": "m13.jpg",
   "nameZh": "死神", "nameEn": "Death", "nameMs": "Kematian",
   "uprightZh": "结束与新生。旧阶段彻底结束，勇敢放手，为全新开始腾出空间。",
   "uprightEn": "Endings and rebirth. A definitive end to the old; brave the transition for a new start.",
   "uprightMs": "Pengakhiran dan kelahiran semula. Lepaskan yang lama demi permulaan yang baharu.",
   "reversedZh": "恐惧改变、拒绝现实。紧抓过去不放，只会延长痛苦。",
   "reversedEn": "Fear of change, denial. Clinging to the past only prolongs your pain.",
   "reversedMs": "Takut akan perubahan, penafian. Terus berpaut pada masa lalu hanya memanjangkan luka."},

  {"number": "14", "arcana": "大阿尔卡纳", "suit": null, "img": "m14.jpg",
   "nameZh": "节制", "nameEn": "Temperance", "nameMs": "Kesederhanaan",
   "uprightZh": "平衡、耐心。将不同元素完美结合，保持情绪稳定，稳步走向治愈。",
   "uprightEn": "Balance, patience. Blend different elements harmoniously, emotional stability brings healing.",
   "uprightMs": "Keseimbangan, kesabaran. Gabungkan elemen dengan harmoni, emosi stabil membawa kesembuhan.",
   "reversedZh": "失衡、极端、缺乏耐心。生活陷入混乱，处理问题手段过于极端。",
   "reversedEn": "Imbalance, extremes, impatience. Life is chaotic, dealing with issues too extremely.",
   "reversedMs": "Tidak seimbang, ekstrem, kurang sabar. Kehidupan kacau bilau akibat tindakan ekstrem."},

  {"number": "15", "arcana": "大阿尔卡纳", "suit": null, "img": "m15.jpg",
   "nameZh": "恶魔", "nameEn": "The Devil", "nameMs": "Iblis",
   "uprightZh": "诱惑、束缚。被坏习惯或有毒关系所困，其实锁链在你手中。",
   "uprightEn": "Temptation, bondage. Trapped by toxic habits or relationships, but the key is in your hands.",
   "uprightMs": "Godaan, belenggu. Terperangkap dalam tabiat toksik, namun kunci kebebasan di tangan anda.",
   "reversedZh": "挣脱束缚、克服诱惑。意识到问题所在，摆脱阴暗面，找回自控力。",
   "reversedEn": "Breaking free, overcoming temptation. Reclaiming self-control and escaping the dark side.",
   "reversedMs": "Bebas dari belenggu, atasi godaan. Mendapatkan semula kawalan diri dan bebas dari kegelapan."},

  {"number": "16", "arcana": "大阿尔卡纳", "suit": null, "img": "m16.jpg",
   "nameZh": "高塔", "nameEn": "The Tower", "nameMs": "Menara",
   "uprightZh": "突变、打破虚假的幻象。不稳固的基础将崩塌，虽痛苦却带来彻底解脱。",
   "uprightEn": "Sudden upheaval, shattering illusions. False foundations fall, bringing painful but true liberation.",
   "uprightMs": "Pergolakan mengejut, ilusi hancur. Asas palsu runtuh, membawa pembebasan sebenar biarpun perit.",
   "reversedZh": "害怕改变、拖延结局。竭力维持注定要破裂的假象。",
   "reversedEn": "Delaying the inevitable, fear of change. Clinging to a failing illusion.",
   "reversedMs": "Menangguh kesudahan, takut akan perubahan. Berpegang teguh pada ilusi yang pasti hancur."},

  {"number": "17", "arcana": "大阿尔卡纳", "suit": null, "img": "m17.jpg",
   "nameZh": "星星", "nameEn": "The Star", "nameMs": "Bintang",
   "uprightZh": "希望、宁静、治愈。风暴过后灵感重新降临，宇宙正在祝福你。",
   "uprightEn": "Hope, peace, healing. After the storm, inspiration returns under the universe's blessing.",
   "uprightMs": "Harapan, ketenangan, penyembuhan. Selepas badai, inspirasi kembali diiringi rahmat semesta.",
   "reversedZh": "绝望、失去信心。对未来失去希望，需要重新找回内心的光芒。",
   "reversedEn": "Despair, lack of faith. Losing hope in the future; you must find your inner light again.",
   "reversedMs": "Putus asa, hilang keyakinan. Hilang harapan; anda perlu mencari semula cahaya diri."},

  {"number": "18", "arcana": "大阿尔卡纳", "suit": null, "img": "m18.jpg",
   "nameZh": "月亮", "nameEn": "The Moon", "nameMs": "Bulan",
   "uprightZh": "幻觉、恐惧。事情并非表面那样简单，注意隐藏的危险与焦虑。",
   "uprightEn": "Illusion, fear, anxiety. Things are not as they seem; beware of hidden truths and fears.",
   "uprightMs": "Ilusi, ketakutan, kebimbangan. Berhati-hati, perkara sebenar mungkin berbeza dari luarannya.",
   "reversedZh": "揭露真相、摆脱困惑。迷雾散去，看清真相并克服了恐惧。",
   "reversedEn": "Truth revealed, overcoming fear. The fog lifts, bringing clarity and dispelling anxiety.",
   "reversedMs": "Kebenaran terbongkar, atasi ketakutan. Kabus menghilang, membawa kejelasan dan ketenangan."},

  {"number": "19", "arcana": "大阿尔卡纳", "suit": null, "img": "m19.jpg",
   "nameZh": "太阳", "nameEn": "The Sun", "nameMs": "Matahari",
   "uprightZh": "成功、快乐。一切朝着最好方向发展，努力将获得极大满足。",
   "uprightEn": "Success, joy, vitality. Everything is going perfectly; your efforts will bring great fulfillment.",
   "uprightMs": "Kejayaan, kegembiraan. Segalanya berjalan lancar; usaha anda akan memberi kepuasan besar.",
   "reversedZh": "暂时的阴霾、成功延迟。需要付出更多努力才能见到彩虹。",
   "reversedEn": "Temporary clouds, delayed success. Joy is slightly dimmed, requires more effort to shine.",
   "reversedMs": "Awan mendung sementara, kejayaan tertunda. Memerlukan usaha ekstra untuk melihat pelangi."},

  {"number": "20", "arcana": "大阿尔卡纳", "suit": null, "img": "m20.jpg",
   "nameZh": "审判", "nameEn": "Judgement", "nameMs": "Penghakiman",
   "uprightZh": "觉醒、重生。总结过去、宽恕自己，作出影响深远的决定。",
   "uprightEn": "Awakening, rebirth. Time to reflect, forgive, and make profound life-changing choices.",
   "uprightMs": "Kesedaran, kelahiran semula. Masa untuk memaafkan masa lalu dan membuat pilihan besar.",
   "reversedZh": "自我怀疑、拒绝面对。因过去的内疚而不敢迎接新阶段。",
   "reversedEn": "Self-doubt, refusal to face facts. Past guilt holds you back from a new beginning.",
   "reversedMs": "Keraguan diri, lari dari kenyataan. Rasa bersalah menghalang permulaan baharu."},

  {"number": "21", "arcana": "大阿尔卡纳", "suit": null, "img": "m21.jpg",
   "nameZh": "世界", "nameEn": "The World", "nameMs": "Dunia",
   "uprightZh": "圆满、成功的终点。重要周期完美结束，即将迈入更高层次。",
   "uprightEn": "Completion, ultimate success. A major cycle ends perfectly, opening doors to higher levels.",
   "uprightMs": "Kesempurnaan, kejayaan mutlak. Kitaran tamat dengan indah, membuka pintu ke tahap yang lebih tinggi.",
   "reversedZh": "未完成、停滞。距离成功仅一步之遥，因未解决的问题暂时受阻。",
   "reversedEn": "Incomplete, stagnation. One step away from success, delayed by unresolved loose ends.",
   "reversedMs": "Tidak lengkap, terbantut. Tinggal selangkah lagi menuju kejayaan, dihalang isu tertunggak."},


  // ================= CUPS (圣杯 / Piala) =================
  {"number": "1", "arcana": "小阿尔卡纳", "suit": "圣杯", "img": "c01.jpg",
   "nameZh": "圣杯王牌", "nameEn": "Ace of Cups", "nameMs": "As Piala",
   "uprightZh": "感情的崭新开始、新恋情或新友谊的诞生。",
   "uprightEn": "A new beginning of emotions, the birth of a new romance or friendship.",
   "uprightMs": "Permulaan emosi yang baharu, percintaan atau persahabatan baru terjalin.",
   "reversedZh": "情感枯竭、单相思或冷漠。",
   "reversedEn": "Emotional drain, unrequited love, or apathy.",
   "reversedMs": "Keletihan emosi, cinta bertepuk sebelah tangan, atau sikap dingin."},
  {"number": "2", "arcana": "小阿尔卡纳", "suit": "圣杯", "img": "c02.jpg",
   "nameZh": "圣杯二", "nameEn": "Two of Cups", "nameMs": "Dua Piala",
   "uprightZh": "完美的伴侣关系、互相吸引与和谐的合作。",
   "uprightEn": "A perfect partnership, mutual attraction, and harmonious cooperation.",
   "uprightMs": "Pasangan yang sempurna, daya tarikan bersama, dan kerjasama harmoni.",
   "reversedZh": "关系破裂、沟通不畅或产生不信任。",
   "reversedEn": "Broken relationship, poor communication, or distrust.",
   "reversedMs": "Hubungan retak, komunikasi yang lemah, atau hilang kepercayaan."},
  {"number": "3", "arcana": "小阿尔卡纳", "suit": "圣杯", "img": "c03.jpg",
   "nameZh": "圣杯三", "nameEn": "Three of Cups", "nameMs": "Tiga Piala",
   "uprightZh": "庆祝、欢乐的聚会、美好的友谊与分享。",
   "uprightEn": "Celebration, joyful gatherings, beautiful friendship and sharing.",
   "uprightMs": "Keraian, pertemuan gembira, ikatan persahabatan yang indah.",
   "reversedZh": "过度放纵、乐极生悲或出现第三方的干扰。",
   "reversedEn": "Overindulgence, joy turning to sorrow, or third-party interference.",
   "reversedMs": "Tersasar batas, keseronokan membawa padah, atau gangguan pihak ketiga."},
  {"number": "4", "arcana": "小阿尔卡纳", "suit": "圣杯", "img": "c04.jpg",
   "nameZh": "圣杯四", "nameEn": "Four of Cups", "nameMs": "Empat Piala",
   "uprightZh": "厌倦、冷漠，对现状不满而错失了外界的新机遇。",
   "uprightEn": "Apathy, boredom, dissatisfaction causing you to miss new opportunities.",
   "uprightMs": "Rasa bosan, tidak peduli, ketidakpuasan hati membuat anda terlepas peluang.",
   "reversedZh": "重新振作、走出低谷，开始愿意接受新事物。",
   "reversedEn": "Renewed vigor, breaking out of a slump, ready for new things.",
   "reversedMs": "Semangat kembali pulih, bangkit dari kesedihan, sedia menerima perkara baharu."},
  {"number": "5", "arcana": "小阿尔卡纳", "suit": "圣杯", "img": "c05.jpg",
   "nameZh": "圣杯五", "nameEn": "Five of Cups", "nameMs": "Lima Piala",
   "uprightZh": "悲伤、失落，沉溺于失去的事物而忽略了剩下的美好。",
   "uprightEn": "Grief, loss, dwelling on the past and ignoring what still remains.",
   "uprightMs": "Kesedihan, kehilangan, terlalu meratapi memori lalu dan buta pada apa yang ada.",
   "reversedZh": "逐渐走出阴霾、释怀过去的伤痛。",
   "reversedEn": "Gradually moving on from grief and letting go of past pain.",
   "reversedMs": "Mula melangkah ke depan, melepaskan kesakitan masa lalu."},
  {"number": "6", "arcana": "小阿尔卡纳", "suit": "圣杯", "img": "c06.jpg",
   "nameZh": "圣杯六", "nameEn": "Six of Cups", "nameMs": "Enam Piala",
   "uprightZh": "童年的回忆、纯真的感情、故人重逢。",
   "uprightEn": "Childhood memories, innocence, nostalgia, or reuniting with an old friend.",
   "uprightMs": "Kenangan zaman kanak-kanak, kepolosan, atau bertemu kembali rakan lama.",
   "reversedZh": "过度沉溺过去、拒绝成长。",
   "reversedEn": "Overly stuck in the past, refusing to grow up or move forward.",
   "reversedMs": "Terperangkap di masa lalu, menolak kedewasaan dan kenyataan."},
  {"number": "7", "arcana": "小阿尔卡纳", "suit": "圣杯", "img": "c07.jpg",
   "nameZh": "圣杯七", "nameEn": "Seven of Cups", "nameMs": "Tujuh Piala",
   "uprightZh": "充满幻象与选择，需要看清什么才是真实的。",
   "uprightEn": "Illusions, daydreaming, having many choices but needing to see reality.",
   "uprightMs": "Ilusi, angan-angan, banyak pilihan tetapi perlu melihat realiti sebenar.",
   "reversedZh": "认清现实、做出明确的决定。",
   "reversedEn": "Facing reality, making a clear and decisive choice.",
   "reversedMs": "Menerima hakikat, membuat keputusan yang muktamad."},
  {"number": "8", "arcana": "小阿尔卡纳", "suit": "圣杯", "img": "c08.jpg",
   "nameZh": "圣杯八", "nameEn": "Eight of Cups", "nameMs": "Lapan Piala",
   "uprightZh": "放弃现有的安逸，转身离开去追寻更高的精神满足。",
   "uprightEn": "Walking away from comfort to seek a higher spiritual fulfillment.",
   "uprightMs": "Meninggalkan keselesaan demi mencari kepuasan rohani yang lebih tinggi.",
   "reversedZh": "害怕未知、不敢离开有毒的环境。",
   "reversedEn": "Fear of the unknown, afraid to leave a toxic or stagnant environment.",
   "reversedMs": "Takut akan masa depan, tidak berani keluar dari persekitaran toksik."},
  {"number": "9", "arcana": "小阿尔卡纳", "suit": "圣杯", "img": "c09.jpg",
   "nameZh": "圣杯九", "nameEn": "Nine of Cups", "nameMs": "Sembilan Piala",
   "uprightZh": "美梦成真、极度的物质与精神满足。",
   "uprightEn": "Wishes fulfilled, extreme material and emotional satisfaction.",
   "uprightMs": "Impian tercapai, kepuasan material dan emosi yang mutlak.",
   "reversedZh": "贪婪、自满或期待的愿望最终落空。",
   "reversedEn": "Greed, smugness, or unfulfilled expectations.",
   "reversedMs": "Tamak, bongkak, atau harapan yang akhirnya berkecai."},
  {"number": "10", "arcana": "小阿尔卡纳", "suit": "圣杯", "img": "c10.jpg",
   "nameZh": "圣杯十", "nameEn": "Ten of Cups", "nameMs": "Sepuluh Piala",
   "uprightZh": "美满的家庭、长久的幸福与终极的情感和谐。",
   "uprightEn": "A happy family, long-lasting joy, and ultimate emotional harmony.",
   "uprightMs": "Keluarga yang bahagia, kegembiraan abadi, dan keharmonian mutlak.",
   "reversedZh": "家庭冲突、失去和谐，表面风光内在破裂。",
   "reversedEn": "Family conflicts, broken harmony, a facade of happiness.",
   "reversedMs": "Konflik keluarga, hilang keharmonian, bahagia hanya pada luaran."},
  {"number": "11", "arcana": "小阿尔卡纳", "suit": "圣杯", "img": "c11.jpg",
   "nameZh": "圣杯侍从", "nameEn": "Page of Cups", "nameMs": "Pengiring Piala",
   "uprightZh": "浪漫的消息、充满想象力的新起点。",
   "uprightEn": "Romantic news, an imaginative and sensitive new beginning.",
   "uprightMs": "Berita romantik, permulaan baharu yang penuh imaginasi dan kelembutan.",
   "reversedZh": "情感不成熟、过于情绪化或收到失望的消息。",
   "reversedEn": "Emotional immaturity, overly sensitive, or disappointing news.",
   "reversedMs": "Emosi tidak matang, terlalu sensitif, atau berita yang mengecewakan."},
  {"number": "12", "arcana": "小阿尔卡纳", "suit": "圣杯", "img": "c12.jpg",
   "nameZh": "圣杯骑士", "nameEn": "Knight of Cups", "nameMs": "Kesatria Piala",
   "uprightZh": "浪漫的追求者、理想主义、顺从内心的爱意。",
   "uprightEn": "A romantic pursuer, an idealist following the heart's calling.",
   "uprightMs": "Pengejar romantis, seorang idealis yang mengikut panggilan hati.",
   "reversedZh": "虚伪的承诺、嫉妒心强或过于情绪化。",
   "reversedEn": "False promises, extreme jealousy, or unrealistic emotionality.",
   "reversedMs": "Janji manis palsu, cemburu buta, atau terlalu beremosi."},
  {"number": "13", "arcana": "小阿尔卡纳", "suit": "圣杯", "img": "c13.jpg",
   "nameZh": "圣杯王后", "nameEn": "Queen of Cups", "nameMs": "Ratu Piala",
   "uprightZh": "极强的同理心、温柔、极具直觉力的抚慰。",
   "uprightEn": "Deep empathy, gentle, highly intuitive, and nurturing.",
   "uprightMs": "Empati yang mendalam, lembut, penuh intuisi, dan penyayang.",
   "reversedZh": "情绪泛滥、过度敏感或显得有些病态。",
   "reversedEn": "Emotional overflow, overly sensitive, or toxic dependency.",
   "reversedMs": "Emosi meluap-luap, terlampau sensitif, atau bergantungan toksik."},
  {"number": "14", "arcana": "小阿尔卡纳", "suit": "圣杯", "img": "c14.jpg",
   "nameZh": "圣杯国王", "nameEn": "King of Cups", "nameMs": "Raja Piala",
   "uprightZh": "情感掌控力强、宽容、能冷静处理复杂的人际关系。",
   "uprightEn": "Emotional mastery, tolerant, handles complex relations with calm wisdom.",
   "uprightMs": "Kawal emosi cemerlang, bertoleransi, mengurus hubungan kompleks dengan tenang.",
   "reversedZh": "操控他人情感、外表冷静但内心冷漠或压抑。",
   "reversedEn": "Emotional manipulation, cold under a calm exterior, repressed feelings.",
   "reversedMs": "Memanipulasi emosi, nampak tenang tapi dingin di dalam, emosi terpendam."},

  // ================= SWORDS (宝剑 / Pedang) =================
  {"number": "1", "arcana": "小阿尔卡纳", "suit": "宝剑", "img": "s01.jpg",
   "nameZh": "宝剑王牌", "nameEn": "Ace of Swords", "nameMs": "As Pedang",
   "uprightZh": "清晰的思考、突破性的真相与决断力。",
   "uprightEn": "Clear thinking, breakthrough truth, and decisive power.",
   "uprightMs": "Pemikiran yang jelas, kebenaran terungkap, dan kuasa membuat keputusan.",
   "reversedZh": "思维混乱、误解、言语伤人或计划受挫。",
   "reversedEn": "Mental confusion, misunderstandings, harsh words, or blocked plans.",
   "reversedMs": "Kekeliruan minda, salah faham, kata-kata tajam, atau rancangan terhalang."},
  {"number": "2", "arcana": "小阿尔卡纳", "suit": "宝剑", "img": "s02.jpg",
   "nameZh": "宝剑二", "nameEn": "Two of Swords", "nameMs": "Dua Pedang",
   "uprightZh": "僵局、逃避现实，在艰难选择面前蒙住双眼。",
   "uprightEn": "Stalemate, avoidance, being blindfolded to a tough choice.",
   "uprightMs": "Kebuntuan, lari dari kenyataan, menutup mata dari pilihan yang sukar.",
   "reversedZh": "打破僵局，终于看清真相并做出选择。",
   "reversedEn": "Breaking the stalemate, finally facing the truth and choosing.",
   "reversedMs": "Memecah kebuntuan, akhirnya melihat kebenaran dan membuat keputusan."},
  {"number": "3", "arcana": "小阿尔卡纳", "suit": "宝剑", "img": "s03.jpg",
   "nameZh": "宝剑三", "nameEn": "Three of Swords", "nameMs": "Tiga Pedang",
   "uprightZh": "令人心碎的痛苦、悲伤、背叛或残酷的真相。",
   "uprightEn": "Heartbreak, sorrow, betrayal, or facing a cruel truth.",
   "uprightMs": "Kelukaan hati, kesedihan, pengkhianatan, atau berdepan kebenaran perit.",
   "reversedZh": "痛苦减轻、开始疗愈内心伤创。",
   "reversedEn": "Pain lessening, beginning the process of inner healing and forgiveness.",
   "reversedMs": "Kesakitan beransur hilang, mula memaafkan dan menyembuhkan luka dalaman."},
  {"number": "4", "arcana": "小阿尔卡纳", "suit": "宝剑", "img": "s04.jpg",
   "nameZh": "宝剑四", "nameEn": "Four of Swords", "nameMs": "Empat Pedang",
   "uprightZh": "休息、恢复、静修冥想，需要退避修养。",
   "uprightEn": "Rest, recovery, meditation, a necessary retreat to recharge.",
   "uprightMs": "Berehat, pemulihan, meditasi, berundur seketika untuk kumpul tenaga.",
   "reversedZh": "被迫行动、疲劳过度，或休息完毕重新出发。",
   "reversedEn": "Forced action, exhaustion, or being fully rested and ready to go.",
   "reversedMs": "Terpaksa bertindak, kepenatan melampau, atau sudah bersedia untuk maju."},
  {"number": "5", "arcana": "小阿尔卡纳", "suit": "宝剑", "img": "s05.jpg",
   "nameZh": "宝剑五", "nameEn": "Five of Swords", "nameMs": "Lima Pedang",
   "uprightZh": "不择手段的胜利、冲突、充满敌意的环境。",
   "uprightEn": "Victory at all costs, conflict, a hostile and toxic environment.",
   "uprightMs": "Menang tanpa mengira cara, konflik, persekitaran yang bermusuhan.",
   "reversedZh": "和解、放下恩怨，或冲突升级导致不可挽回的伤害。",
   "reversedEn": "Reconciliation, dropping grudges, or a conflict escalating irreparably.",
   "reversedMs": "Berdamai, membuang dendam, atau konflik memuncak tanpa jalan kembali."},
  {"number": "6", "arcana": "小阿尔卡纳", "suit": "宝剑", "img": "s06.jpg",
   "nameZh": "宝剑六", "nameEn": "Six of Swords", "nameMs": "Enam Pedang",
   "uprightZh": "逐渐渡过难关、向平静彼岸过渡，带着伤痛前行。",
   "uprightEn": "Passing through difficulties, moving towards calmer waters despite past scars.",
   "uprightMs": "Beransur pulih dari masalah, menuju ketenangan walau membawa luka lama.",
   "reversedZh": "困境难逃、抗拒改变，过去的阴影纠缠不休。",
   "reversedEn": "Stuck in hardship, resisting change, haunted by the past.",
   "reversedMs": "Terperangkap dalam masalah, menolak perubahan, dihantui bayangan lalu."},
  {"number": "7", "arcana": "小阿尔卡纳", "suit": "宝剑", "img": "s07.jpg",
   "nameZh": "宝剑七", "nameEn": "Seven of Swords", "nameMs": "Tujuh Pedang",
   "uprightZh": "欺骗、背着人做事，或通过捷径获取利益。",
   "uprightEn": "Deception, sneaking around, or taking shortcuts to gain an advantage.",
   "uprightMs": "Penipuan, sembunyi-sembunyi, atau mengambil jalan pintas untuk untung.",
   "reversedZh": "谎言被揭穿、必须面对现实，不再自欺欺人。",
   "reversedEn": "Lies exposed, forced to face reality, no more self-deception.",
   "reversedMs": "Pembohongan terbongkar, terpaksa terima realiti, tiada lagi tipu muslihat."},
  {"number": "8", "arcana": "小阿尔卡纳", "suit": "宝剑", "img": "s08.jpg",
   "nameZh": "宝剑八", "nameEn": "Eight of Swords", "nameMs": "Lapan Pedang",
   "uprightZh": "自我限制、感到被束缚，解开眼罩就能自由。",
   "uprightEn": "Self-imposed restriction, feeling trapped. Freedom comes by opening your eyes.",
   "uprightMs": "Menyekat diri sendiri, berasa terkurung. Buka penutup mata untuk bebas.",
   "reversedZh": "挣脱束缚、重获自由，看清现实并找到出路。",
   "reversedEn": "Breaking free, reclaiming freedom, seeing clearly and finding a way out.",
   "reversedMs": "Memutuskan rantaian, bebas semula, melihat dengan jelas untuk mencari jalan keluar."},
  {"number": "9", "arcana": "小阿尔卡纳", "suit": "宝剑", "img": "s09.jpg",
   "nameZh": "宝剑九", "nameEn": "Nine of Swords", "nameMs": "Sembilan Pedang",
   "uprightZh": "极度焦虑、失眠噩梦，内疚与过度的精神折磨。",
   "uprightEn": "Extreme anxiety, nightmares, guilt, and deep mental anguish.",
   "uprightMs": "Keresahan melampau, mimpi ngeri, rasa bersalah, dan seksaan mental.",
   "reversedZh": "从噩梦中醒来、恐惧减轻，正视心中的烦恼。",
   "reversedEn": "Waking from the nightmare, easing fears, facing your worries.",
   "reversedMs": "Bangkit dari mimpi buruk, reda ketakutan, berani hadapi masalah hati."},
  {"number": "10", "arcana": "小阿尔卡纳", "suit": "宝剑", "img": "s10.jpg",
   "nameZh": "宝剑十", "nameEn": "Ten of Swords", "nameMs": "Sepuluh Pedang",
   "uprightZh": "毁灭、彻底结束，跌入谷底，意味着苦难已到尽头。",
   "uprightEn": "Ruin, absolute ending, hitting rock bottom. The suffering is finally over.",
   "uprightMs": "Kemusnahan, pengakhiran mutlak, jatuh teruk. Derita telah pun di penghujung.",
   "reversedZh": "绝处逢生、重新开始，从打击中逐渐恢复过来。",
   "reversedEn": "Survival, fresh start, slowly recovering from a fatal blow.",
   "reversedMs": "Sinar di hujung terowong, mula semula, beransur pulih dari tamparan hebat."},
  {"number": "11", "arcana": "小阿尔卡纳", "suit": "宝剑", "img": "s11.jpg",
   "nameZh": "宝剑侍从", "nameEn": "Page of Swords", "nameMs": "Pengiring Pedang",
   "uprightZh": "保持警觉、旺盛好奇心，直言不讳的观察者。",
   "uprightEn": "Alert, deeply curious, blunt speaker, and sharp observer.",
   "uprightMs": "Peka, penuh rasa ingin tahu, jujur bersuara, dan pemerhati tajam.",
   "reversedZh": "充满敌意、流言蜚语、显得尖酸刻薄。",
   "reversedEn": "Hostility, gossip, coming off as bitter or overly sarcastic.",
   "reversedMs": "Permusuhan, khabar angin, mulut tajam dan menyakitkan hati."},
  {"number": "12", "arcana": "小阿尔卡纳", "suit": "宝剑", "img": "s12.jpg",
   "nameZh": "宝剑骑士", "nameEn": "Knight of Swords", "nameMs": "Kesatria Pedang",
   "uprightZh": "行动迅速、雷厉风行，但也可能缺乏思考。",
   "uprightEn": "Swift action, moving at lightning speed, but potentially reckless.",
   "uprightMs": "Tindakan pantas, bergerak sepantas kilat, tapi mungkin terburu-buru.",
   "reversedZh": "鲁莽冲撞、不切实际，因急躁导致严重错误。",
   "reversedEn": "Reckless, impractical, causing major mistakes due to impatience.",
   "reversedMs": "Gopoh, tidak realistik, mengundang kesilapan besar kerana hilang sabar."},
  {"number": "13", "arcana": "小阿尔卡纳", "suit": "宝剑", "img": "s13.jpg",
   "nameZh": "宝剑王后", "nameEn": "Queen of Swords", "nameMs": "Ratu Pedang",
   "uprightZh": "独立、理智，用清晰的逻辑去剥离感情的干扰。",
   "uprightEn": "Independent, rational, cutting through emotional fog with clear logic.",
   "uprightMs": "Berdikari, rasional, menepis gangguan emosi dengan logik yang tajam.",
   "reversedZh": "冷酷无情、尖酸刻薄或利用聪明才智去伤人。",
   "reversedEn": "Cold-hearted, overly critical, using intellect to hurt others.",
   "reversedMs": "Dingin, sangat kritis, menggunakan kepintaran untuk melukakan orang lain."},
  {"number": "14", "arcana": "小阿尔卡纳", "suit": "宝剑", "img": "s14.jpg",
   "nameZh": "宝剑国王", "nameEn": "King of Swords", "nameMs": "Raja Pedang",
   "uprightZh": "绝对理性、公正，逻辑严密且富有决断力的领导者。",
   "uprightEn": "Pure logic, fairness, a highly analytical and decisive leader.",
   "uprightMs": "Logik mutlak, keadilan, pemimpin yang analitikal dan tegas.",
   "reversedZh": "滥用权力、独断专行或过于冷血无情。",
   "reversedEn": "Abusing power, dictatorial, or excessively cold and merciless.",
   "reversedMs": "Salah guna kuasa, diktator, atau terlampau kejam tanpa belas kasihan."},

  // ================= WANDS (权杖 / Tongkat) =================
  {"number": "1", "arcana": "小阿尔卡纳", "suit": "权杖", "img": "w01.jpg",
   "nameZh": "权杖王牌", "nameEn": "Ace of Wands", "nameMs": "As Tongkat",
   "uprightZh": "强烈的灵感、爆发的创造力与充满热情的新计划。",
   "uprightEn": "Intense inspiration, explosive creativity, and a passionate new plan.",
   "uprightMs": "Inspirasi hebat, kreativiti meledak, dan rancangan baru yang penuh semangat.",
   "reversedZh": "缺乏动力、计划延迟或热情迅速消退。",
   "reversedEn": "Lack of drive, delayed plans, or rapidly fading enthusiasm.",
   "reversedMs": "Kurang motivasi, rancangan tertunda, atau semangat cepat pudar."},
  {"number": "2", "arcana": "小阿尔卡纳", "suit": "权杖", "img": "w02.jpg",
   "nameZh": "权杖二", "nameEn": "Two of Wands", "nameMs": "Dua Tongkat",
   "uprightZh": "长远的规划、远见，站在十字路口决定未来方向。",
   "uprightEn": "Long-term planning, vision, standing at a crossroads deciding the future.",
   "uprightMs": "Perancangan jangka panjang, visi, di persimpangan memilih arah depan.",
   "reversedZh": "害怕未知、将自己局限在舒适区内不敢探索。",
   "reversedEn": "Fear of the unknown, trapping oneself in a comfort zone.",
   "reversedMs": "Takut mencuba, terperangkap dalam zon selesa tanpa berani meneroka."},
  {"number": "3", "arcana": "小阿尔卡纳", "suit": "权杖", "img": "w03.jpg",
   "nameZh": "权杖三", "nameEn": "Three of Wands", "nameMs": "Tiga Tongkat",
   "uprightZh": "向外探索、事业初见成效，期待跨界或海外合作。",
   "uprightEn": "Outward expansion, initial success, anticipating overseas or wider collaborations.",
   "uprightMs": "Peluasan pengaruh, kejayaan awal, menunggu kerjasama seberang laut.",
   "reversedZh": "合作不顺、计划受阻，努力迟迟看不到回报。",
   "reversedEn": "Failing collaborations, blocked plans, unrewarded efforts.",
   "reversedMs": "Kerjasama gagal, rancangan tersekat, usaha belum membuahkan hasil."},
  {"number": "4", "arcana": "小阿尔卡纳", "suit": "权杖", "img": "w04.jpg",
   "nameZh": "权杖四", "nameEn": "Four of Wands", "nameMs": "Empat Tongkat",
   "uprightZh": "庆祝、稳固的里程碑、繁荣，买房或步入婚姻的喜悦。",
   "uprightEn": "Celebration, solid milestones, prosperity, buying a home or marriage.",
   "uprightMs": "Keraian, pencapaian kukuh, kemakmuran, membeli rumah atau perkahwinan.",
   "reversedZh": "基础不稳、失去和谐，庆祝活动被推迟。",
   "reversedEn": "Unstable foundations, lost harmony, or delayed celebrations.",
   "reversedMs": "Asas yang rapuh, hilang keharmonian, keraian terpaksa ditunda."},
  {"number": "5", "arcana": "小阿尔卡纳", "suit": "权杖", "img": "w05.jpg",
   "nameZh": "权杖五", "nameEn": "Five of Wands", "nameMs": "Lima Tongkat",
   "uprightZh": "激烈竞争、冲突，众人七嘴八舌无法统一意见。",
   "uprightEn": "Fierce competition, conflicts, chaotic disagreements and clashes.",
   "uprightMs": "Persaingan sengit, konflik, kekacauan dan perbezaan pendapat.",
   "reversedZh": "达成共识、内部矛盾逐渐平息。",
   "reversedEn": "Finding consensus, avoiding conflict, internal disputes settling down.",
   "reversedMs": "Mencapai persetujuan, elak konflik, pertelingkahan dalaman mula reda."},
  {"number": "6", "arcana": "小阿尔卡纳", "suit": "权杖", "img": "w06.jpg",
   "nameZh": "权杖六", "nameEn": "Six of Wands", "nameMs": "Enam Tongkat",
   "uprightZh": "光荣的胜利、获得公众认可，自信站在巅峰。",
   "uprightEn": "Glorious victory, public recognition, standing proudly at the peak.",
   "uprightMs": "Kemenangan gemilang, pengiktirafan ramai, berdiri bangga di puncak.",
   "reversedZh": "骄傲自大、失去支持或期待的表彰落空。",
   "reversedEn": "Arrogance, lost support, or expected recognition falls through.",
   "reversedMs": "Sikap bongkak, hilang sokongan, atau pujian yang tidak kunjung tiba."},
  {"number": "7", "arcana": "小阿尔卡纳", "suit": "权杖", "img": "w07.jpg",
   "nameZh": "权杖七", "nameEn": "Seven of Wands", "nameMs": "Tujuh Tongkat",
   "uprightZh": "顽强的防御、坚持立场，克服重重阻力。",
   "uprightEn": "Tenacious defense, standing your ground, overcoming heavy opposition.",
   "uprightMs": "Pertahanan teguh, mempertahankan prinsip, mengatasi rintangan hebat.",
   "reversedZh": "感到力不从心、屈服于压力或立场动摇。",
   "reversedEn": "Feeling overwhelmed, yielding to pressure, or wavering stance.",
   "reversedMs": "Rasa tidak mampu, mengalah pada tekanan, atau goyah pendirian."},
  {"number": "8", "arcana": "小阿尔卡纳", "suit": "权杖", "img": "w08.jpg",
   "nameZh": "权杖八", "nameEn": "Eight of Wands", "nameMs": "Lapan Tongkat",
   "uprightZh": "快速行动、飞速进展，即将收到期待的消息。",
   "uprightEn": "Rapid action, swift progress, incoming exciting news or travel.",
   "uprightMs": "Tindakan pantas, kemajuan laju, berita gembira bakal tiba.",
   "reversedZh": "严重延迟、失去方向或沟通障碍出错。",
   "reversedEn": "Severe delays, lost direction, miscommunication leading to errors.",
   "reversedMs": "Kelewatan teruk, hilang arah, salah faham membawa kepada kesilapan."},
  {"number": "9", "arcana": "小阿尔卡纳", "suit": "权杖", "img": "w09.jpg",
   "nameZh": "权杖九", "nameEn": "Nine of Wands", "nameMs": "Sembilan Tongkat",
   "uprightZh": "保持警惕、虽然疲惫但仍坚守阵地，韧性极强。",
   "uprightEn": "Vigilant, exhausted but holding the last line of defense, high resilience.",
   "uprightMs": "Berwaspada, keletihan tetapi teguh bertahan, daya tahan sangat tinggi.",
   "reversedZh": "彻底放弃、过度防御导致偏执，意志力耗尽。",
   "reversedEn": "Giving up, paranoia from over-defense, willpower completely drained.",
   "reversedMs": "Menyerah kalah, paranoid akibat terlalu bertahan, semangat luntur."},
  {"number": "10", "arcana": "小阿尔卡纳", "suit": "权杖", "img": "w10.jpg",
   "nameZh": "权杖十", "nameEn": "Ten of Wands", "nameMs": "Sepuluh Tongkat",
   "uprightZh": "沉重的负担、扛下所有责任，过度劳累。",
   "uprightEn": "Heavy burden, immense pressure, shouldering all responsibilities, burnout.",
   "uprightMs": "Beban berat, tekanan kuat, memikul semua tanggungjawab sendirian, keletihan.",
   "reversedZh": "卸下重担、学会放权，或被压力压垮。",
   "reversedEn": "Releasing the burden, learning to delegate, or collapsing under pressure.",
   "reversedMs": "Melepaskan beban, belajar membahagi tugas, atau rebah akibat tekanan."},
  {"number": "11", "arcana": "小阿尔卡纳", "suit": "权杖", "img": "w11.jpg",
   "nameZh": "权杖侍从", "nameEn": "Page of Wands", "nameMs": "Pengiring Tongkat",
   "uprightZh": "充满活力的探索者、热情的新想法与好消息。",
   "uprightEn": "Energetic explorer, passionate new ideas, and exciting news.",
   "uprightMs": "Peneroka bertenaga, idea baharu yang penuh semangat dan berita baik.",
   "reversedZh": "缺乏耐心、三分钟热度或坏消息传来。",
   "reversedEn": "Lack of patience, short-lived passion, or receiving bad news.",
   "reversedMs": "Kurang sabar, hangat-hangat tahi ayam, atau berita buruk tiba."},
  {"number": "12", "arcana": "小阿尔卡纳", "suit": "权杖", "img": "w12.jpg",
   "nameZh": "权杖骑士", "nameEn": "Knight of Wands", "nameMs": "Kesatria Tongkat",
   "uprightZh": "勇敢的冒险家、精力充沛，但做事可能冲动。",
   "uprightEn": "Brave adventurer, full of energy, but can be impulsive.",
   "uprightMs": "Pengembara berani, penuh tenaga, tetapi kadangkala bertindak melulu.",
   "reversedZh": "鲁莽好战、做事不计后果或暴躁易怒。",
   "reversedEn": "Reckless, combative, acting without thinking of consequences, angry.",
   "reversedMs": "Semberono, suka berlawan, bertindak tanpa fikir panjang, cepat marah."},
  {"number": "13", "arcana": "小阿尔卡纳", "suit": "权杖", "img": "w13.jpg",
   "nameZh": "权杖王后", "nameEn": "Queen of Wands", "nameMs": "Ratu Tongkat",
   "uprightZh": "极具魅力、自信热情，在职场或社交中大放异彩。",
   "uprightEn": "Highly charismatic, confident, passionate, shining in social or career settings.",
   "uprightMs": "Sangat berkarisma, yakin, bersemangat, menyerlah dalam kerjaya atau sosial.",
   "reversedZh": "固执己见、嫉妒心重或专横跋扈惹麻烦。",
   "reversedEn": "Stubborn, jealous, domineering, causing trouble through emotional outbursts.",
   "reversedMs": "Keras kepala, cemburu buta, terlalu mengawal dan mencetus masalah."},
  {"number": "14", "arcana": "小阿尔卡纳", "suit": "权杖", "img": "w14.jpg",
   "nameZh": "权杖国王", "nameEn": "King of Wands", "nameMs": "Raja Tongkat",
   "uprightZh": "天生领导者、拥有宏大愿景与非凡魅力。",
   "uprightEn": "Natural leader, possessing a grand vision and extraordinary charisma.",
   "uprightMs": "Pemimpin semula jadi, mempunyai visi besar dan karisma luar biasa.",
   "reversedZh": "独裁专制、冲动傲慢，为达目的不择手段。",
   "reversedEn": "Dictatorial, impulsive, arrogant, and ruthless in achieving goals.",
   "reversedMs": "Kuku besi, gopoh, angkuh, dan sanggup lakukan apa saja demi matlamat."},

  // ================= PENTACLES (星币 / Pentakel) =================
  {"number": "1", "arcana": "小阿尔卡纳", "suit": "星币", "img": "p01.jpg",
   "nameZh": "星币王牌", "nameEn": "Ace of Pentacles", "nameMs": "As Pentakel",
   "uprightZh": "财富新起点、实质回报、带来物质繁荣的新机遇。",
   "uprightEn": "New financial start, tangible rewards, new opportunity for prosperity.",
   "uprightMs": "Permulaan kewangan baharu, pulangan nyata, peluang kemakmuran.",
   "reversedZh": "错失良机、财务损失、贪婪或项目缺乏资金。",
   "reversedEn": "Missed opportunity, financial loss, greed, or lack of funding.",
   "reversedMs": "Peluang terlepas, kerugian, tamak, atau projek kurang dana."},
  {"number": "2", "arcana": "小阿尔卡纳", "suit": "星币", "img": "p02.jpg",
   "nameZh": "星币二", "nameEn": "Two of Pentacles", "nameMs": "Dua Pentakel",
   "uprightZh": "灵活资金周转、在多任务中保持平衡与适应。",
   "uprightEn": "Flexible cash flow, balancing multiple tasks, adapting to changes.",
   "uprightMs": "Aliran tunai fleksibel, mengimbangi pelbagai tugas, mudah menyesuaikan diri.",
   "reversedZh": "失去平衡、财务危机或过度透支了精力金钱。",
   "reversedEn": "Loss of balance, financial crisis, overextending energy and money.",
   "reversedMs": "Hilang keseimbangan, krisis wang, tenaga dan duit terlampau diperah."},
  {"number": "3", "arcana": "小阿尔卡纳", "suit": "星币", "img": "p03.jpg",
   "nameZh": "星币三", "nameEn": "Three of Pentacles", "nameMs": "Tiga Pentakel",
   "uprightZh": "完美团队合作、精湛技艺、获得初步成就。",
   "uprightEn": "Perfect teamwork, masterful craftsmanship, achieving initial success.",
   "uprightMs": "Kerjasama pasukan cemerlang, kemahiran tinggi, kejayaan awal dicapai.",
   "reversedZh": "缺乏协作、技术不精或团队内部出现分歧。",
   "reversedEn": "Lack of teamwork, poor skills, or internal team disputes.",
   "reversedMs": "Kurang kerjasama, kurang kemahiran, atau perpecahan dalam pasukan."},
  {"number": "4", "arcana": "小阿尔卡纳", "suit": "星币", "img": "p04.jpg",
   "nameZh": "星币四", "nameEn": "Four of Pentacles", "nameMs": "Empat Pentakel",
   "uprightZh": "保守理财、物质安全感，但需避免过度固执。",
   "uprightEn": "Conservative finance, material security, but avoid being overly stingy.",
   "uprightMs": "Berjimat cermat, rasa selamat dengan harta, tapi jangan terlalu kedekut.",
   "reversedZh": "挥霍无度、放弃控制或学会分享不再守财。",
   "reversedEn": "Overspending, losing control, or finally learning to share wealth.",
   "reversedMs": "Boros berbelanja, hilang kawalan, atau mula sudi berkongsi rezeki."},
  {"number": "5", "arcana": "小阿尔卡纳", "suit": "星币", "img": "p05.jpg",
   "nameZh": "星币五", "nameEn": "Five of Pentacles", "nameMs": "Lima Pentakel",
   "uprightZh": "贫困、孤立无援，物质或健康上的困境。",
   "uprightEn": "Poverty, isolation, feeling abandoned in material or health struggles.",
   "uprightMs": "Kemiskinan, terpinggir, masalah kesihatan dan kewangan yang mendesak.",
   "reversedZh": "经济好转、脱离困境、找到援助之手。",
   "reversedEn": "Financial recovery, escaping hardship, finding a helping hand.",
   "reversedMs": "Kewangan pulih, keluar dari kesusahan, mendapat bantuan yang dicari."},
  {"number": "6", "arcana": "小阿尔卡纳", "suit": "星币", "img": "p06.jpg",
   "nameZh": "星币六", "nameEn": "Six of Pentacles", "nameMs": "Enam Pentakel",
   "uprightZh": "慷慨、慈善、资源合理分配，收到奖金或帮助。",
   "uprightEn": "Generosity, charity, fair resource distribution, receiving bonuses or help.",
   "uprightMs": "Murah hati, amal jariah, agihan adil, menerima bonus atau bantuan.",
   "reversedZh": "自私、债务纠纷或带附加条件的帮助。",
   "reversedEn": "Selfishness, debt disputes, or help that comes with strings attached.",
   "reversedMs": "Mementingkan diri, beban hutang, atau bantuan yang ada udang di sebalik batu."},
  {"number": "7", "arcana": "小阿尔卡纳", "suit": "星币", "img": "p07.jpg",
   "nameZh": "星币七", "nameEn": "Seven of Pentacles", "nameMs": "Tujuh Pentakel",
   "uprightZh": "长远投资、耐心等待收成，评估目前的进度。",
   "uprightEn": "Long-term investment, patiently waiting for harvest, evaluating progress.",
   "uprightMs": "Pelaburan jangka panjang, sabar menunggu hasil, menilai kemajuan.",
   "reversedZh": "缺乏耐心、投资失败、努力未得相应回报。",
   "reversedEn": "Impatience, failed investments, efforts not yielding adequate returns.",
   "reversedMs": "Kurang sabar, pelaburan lebur, usaha keras tanpa pulangan setimpal."},
  {"number": "8", "arcana": "小阿尔卡纳", "suit": "星币", "img": "p08.jpg",
   "nameZh": "星币八", "nameEn": "Eight of Pentacles", "nameMs": "Lapan Pentakel",
   "uprightZh": "极度专注、勤奋工作、通过打磨工艺获得提升。",
   "uprightEn": "Extreme focus, hard work, leveling up through dedicated craftsmanship.",
   "uprightMs": "Fokus luar biasa, kerja keras, meningkatkan tahap melalui ketekunan.",
   "reversedZh": "缺乏热情、粗心大意或只看重钱忽略质量。",
   "reversedEn": "Lack of passion, carelessness, or prioritizing money over quality.",
   "reversedMs": "Kurang semangat, cuai, atau hanya kejar duit mengabaikan kualiti."},
  {"number": "9", "arcana": "小阿尔卡纳", "suit": "星币", "img": "p09.jpg",
   "nameZh": "星币九", "nameEn": "Nine of Pentacles", "nameMs": "Sembilan Pentakel",
   "uprightZh": "富足、独立自主，享受自己辛勤劳动换来的成果。",
   "uprightEn": "Abundance, independence, enjoying the fruits of your hard labor.",
   "uprightMs": "Kewangan kukuh, berdikari, menikmati hasil titik peluh sendiri.",
   "reversedZh": "过度依赖他人或表面风光背地里牺牲了自由。",
   "reversedEn": "Overdependence, material lack, or sacrificing freedom for fake wealth.",
   "reversedMs": "Terlalu bergantung pada orang, atau nampak kaya tapi hilang kebebasan."},
  {"number": "10", "arcana": "小阿尔卡纳", "suit": "星币", "img": "p10.jpg",
   "nameZh": "星币十", "nameEn": "Ten of Pentacles", "nameMs": "Sepuluh Pentakel",
   "uprightZh": "财富传承、家族繁荣、长期财务安全与稳固基础。",
   "uprightEn": "Generational wealth, family prosperity, long-term financial security.",
   "uprightMs": "Harta turun-temurun, keluarga makmur, jaminan kewangan jangka panjang.",
   "reversedZh": "财务纠纷、家庭破裂或投资遭受重大损失。",
   "reversedEn": "Financial disputes, broken family, or severe investment losses.",
   "reversedMs": "Pertelingkahan harta, keluarga berpecah, atau kerugian besar pelaburan."},
  {"number": "11", "arcana": "小阿尔卡纳", "suit": "星币", "img": "p11.jpg",
   "nameZh": "星币侍从", "nameEn": "Page of Pentacles", "nameMs": "Pengiring Pentakel",
   "uprightZh": "好学务实、脚踏实地，即将收到关于事业的好消息。",
   "uprightEn": "Studious, pragmatic, grounded, expecting solid news about career or money.",
   "uprightMs": "Rajin belajar, pragmatik, bakal terima berita baik tentang kerjaya/kewangan.",
   "reversedZh": "懒惰、缺乏目标、不切实际或无法集中注意力。",
   "reversedEn": "Lazy, lacking goals, impractical, or unable to focus on studies.",
   "reversedMs": "Malas, tiada arah tuju, tidak berpijak di bumi nyata atau hilang fokus."},
  {"number": "12", "arcana": "小阿尔卡纳", "suit": "星币", "img": "p12.jpg",
   "nameZh": "星币骑士", "nameEn": "Knight of Pentacles", "nameMs": "Kesatria Pentakel",
   "uprightZh": "稳重勤奋、绝对可靠，虽缓慢但定会坚持到底。",
   "uprightEn": "Steady, diligent, absolutely reliable. Slow but guaranteed to finish.",
   "uprightMs": "Berhemah, rajin, sangat boleh diharap. Biar lambat asalkan siap.",
   "reversedZh": "极其固执、因循守旧或工作狂导致忽略生活。",
   "reversedEn": "Extremely stubborn, stuck in a rut, or a workaholic ignoring life.",
   "reversedMs": "Sangat degil, jumud, atau gila kerja hingga abaikan kehidupan."},
  {"number": "13", "arcana": "小阿尔卡纳", "suit": "星币", "img": "p13.jpg",
   "nameZh": "星币王后", "nameEn": "Queen of Pentacles", "nameMs": "Ratu Pentakel",
   "uprightZh": "丰饶、慷慨贤惠，完美平衡家庭与物质生活。",
   "uprightEn": "Abundant, generous, nurturing, perfectly balancing family and wealth.",
   "uprightMs": "Makmur, pemurah, seimbang menguruskan rumah tangga dan kerjaya.",
   "reversedZh": "贪婪、极度缺乏安全感或忽略家人的感受。",
   "reversedEn": "Greedy, extremely insecure about money, or neglecting family needs.",
   "reversedMs": "Tamak, rasa tidak selamat soal wang, atau abaikan kehendak keluarga."},
  {"number": "14", "arcana": "小阿尔卡纳", "suit": "星币", "img": "p14.jpg",
   "nameZh": "星币国王", "nameEn": "King of Pentacles", "nameMs": "Raja Pentakel",
   "uprightZh": "巨大财富、事业巅峰、值得信赖的成功人士。",
   "uprightEn": "Massive wealth, peak career, a highly reliable and successful figure.",
   "uprightMs": "Kekayaan luar biasa, puncak kerjaya, individu sukses yang dipercayai.",
   "reversedZh": "腐败、极端物质主义或为金钱不择手段。",
   "reversedEn": "Corruption, extreme materialism, or ruthless in the pursuit of wealth.",
   "reversedMs": "Rasuah, materialistik ekstrem, atau sanggup buat apa saja demi duit."}
];