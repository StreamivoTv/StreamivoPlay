import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'core.dart';

const fxPanel = Color(0xFF1B1B1F);
const fxFieldBg = Color(0xFF2A2A2E);
const fxGrad = LinearGradient(colors: [Color(0xFFFF6A4D), Color(0xFFFF4D7A)]);

const monthFull = [
  'January',
  'February',
  'March',
  'April',
  'May',
  'June',
  'July',
  'August',
  'September',
  'October',
  'November',
  'December'
];

String two(int n) => n.toString().padLeft(2, '0');

bool adultName(String n) {
  final l = n.toLowerCase();
  if (l.contains('18+')) return true;
  return RegExp(r'(^|[^a-z0-9])(xxx|adults?|porn|sex|nsfw|erotic)([^a-z0-9]|$)').hasMatch(l);
}

// ---------------- Dialog frame (dark panel, small label, bold title) ----------------
class FxDialog extends StatelessWidget {
  final String label, title;
  final Widget child;
  final List<Widget> actions;
  final double width;
  const FxDialog(
      {required this.label,
      required this.title,
      required this.child,
      this.actions = const [],
      this.width = 560,
      super.key});

  @override
  Widget build(BuildContext c) {
    final mq = MediaQuery.of(c);
    return Dialog(
      backgroundColor: fxPanel,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: width, maxHeight: mq.size.height - 24),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (label.isNotEmpty)
                Text(label,
                    style: const TextStyle(fontSize: 12, letterSpacing: 2.5, color: Colors.white54)),
              const SizedBox(height: 4),
              Text(title, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Divider(height: 1, color: Colors.white24),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 14, bottom: 6),
                  child: child,
                ),
              ),
              if (actions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 10),
                  child: Row(children: [
                    for (var i = 0; i < actions.length; i++) ...[
                      if (i > 0) const SizedBox(width: 14),
                      Expanded(child: actions[i]),
                    ],
                  ]),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------- Pill button ----------------
class FxBtn extends StatefulWidget {
  final String text;
  final VoidCallback onTap;
  final bool primary, autofocus;
  const FxBtn(this.text, this.onTap, {this.primary = false, this.autofocus = false, super.key});
  @override
  State<FxBtn> createState() => _FxBtnState();
}

class _FxBtnState extends State<FxBtn> {
  bool f = false;
  @override
  Widget build(BuildContext c) {
    final on = showFocus(f);
    return InkWell(
      autofocus: widget.autofocus,
      onTap: widget.onTap,
      onFocusChange: (v) => setState(() => f = v),
      focusColor: Colors.transparent,
      borderRadius: BorderRadius.circular(30),
      child: Container(
        height: 50,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          gradient: widget.primary ? fxGrad : null,
          color: widget.primary ? null : const Color(0xFF3A3A3F),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
              color: on ? Colors.white : (widget.primary ? Colors.transparent : Colors.white38),
              width: on ? 3 : 2),
        ),
        child: Text(widget.text,
            style: const TextStyle(
                fontSize: 17, fontWeight: FontWeight.w600, letterSpacing: 0.5, color: Colors.white)),
      ),
    );
  }
}

// ---------------- Dropdown-looking field ----------------
class FxSelect extends StatefulWidget {
  final String text;
  final VoidCallback onTap;
  const FxSelect(this.text, this.onTap, {super.key});
  @override
  State<FxSelect> createState() => _FxSelectState();
}

class _FxSelectState extends State<FxSelect> {
  bool f = false;
  @override
  Widget build(BuildContext c) {
    final on = showFocus(f);
    return InkWell(
      onTap: widget.onTap,
      onFocusChange: (v) => setState(() => f = v),
      focusColor: Colors.transparent,
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: 52,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration: BoxDecoration(
          color: fxFieldBg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: on ? accent : Colors.white12, width: on ? 2 : 1),
        ),
        child: Row(children: [
          Expanded(
              child: Text(widget.text,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 17))),
          const Icon(Icons.arrow_downward, size: 22),
        ]),
      ),
    );
  }
}

// ---------------- Check box row ----------------
class FxCheck extends StatelessWidget {
  final String label;
  final bool value, boxFirst;
  final ValueChanged<bool> onChanged;
  const FxCheck(this.label, this.value, this.onChanged, {this.boxFirst = false, super.key});

  @override
  Widget build(BuildContext c) {
    final box = Container(
      width: 26,
      height: 26,
      decoration: BoxDecoration(
        color: value ? accent : Colors.transparent,
        border: Border.all(color: value ? accent : Colors.white70, width: 2),
        borderRadius: BorderRadius.circular(6),
      ),
      child: value ? const Icon(Icons.check, size: 20, color: Colors.black) : null,
    );
    final text = Expanded(child: Text(label, style: const TextStyle(fontSize: 17)));
    return InkWell(
      onTap: () => onChanged(!value),
      focusColor: Colors.white12,
      borderRadius: BorderRadius.circular(10),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: boxFirst ? [box, const SizedBox(width: 16), text] : [text, const SizedBox(width: 12), box],
        ),
      ),
    );
  }
}

Widget fxLabel(String t) => Padding(
      padding: const EdgeInsets.only(top: 14, bottom: 8),
      child: Text(t, style: const TextStyle(fontSize: 15, color: Colors.white70)),
    );

Widget fxInput(TextEditingController c, String hint,
        {bool obscure = false,
        TextInputType? type,
        int? maxLen,
        bool autofocus = false,
        ValueChanged<String>? onSubmit}) =>
    TextField(
      controller: c,
      obscureText: obscure,
      keyboardType: type,
      maxLength: maxLen,
      autofocus: autofocus,
      onSubmitted: onSubmit,
      style: const TextStyle(fontSize: 17),
      decoration: InputDecoration(
        counterText: '',
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white38),
        filled: true,
        fillColor: fxFieldBg,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(18),
            borderSide: const BorderSide(color: accent, width: 2)),
      ),
    );

// ---------------- Radio list dialog ----------------
class _RadioRow extends StatelessWidget {
  final String text;
  final bool on;
  final VoidCallback tap;
  const _RadioRow(this.text, this.on, this.tap);
  @override
  Widget build(BuildContext c) => InkWell(
        autofocus: on,
        onTap: tap,
        focusColor: Colors.white12,
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Row(children: [
            Icon(on ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                color: on ? accent : Colors.white54),
            const SizedBox(width: 14),
            Expanded(child: Text(text, style: const TextStyle(fontSize: 17))),
          ]),
        ),
      );
}

Future<String?> pickFx(BuildContext c, String title, List<List<String>> opts, String cur,
        {String label = ''}) =>
    showDialog<String>(
      context: c,
      builder: (d) => FxDialog(
        label: label,
        title: title,
        width: 460,
        child: Column(children: [
          for (final o in opts) _RadioRow(o[1], o[0] == cur, () => Navigator.pop(d, o[0])),
        ]),
        actions: [FxBtn('Cancel', () => Navigator.pop(d))],
      ),
    );

// ---------------- PIN (parental control) ----------------
Future<String?> enterPin(BuildContext c, String title) =>
    showDialog<String>(context: c, builder: (d) => _PinDlg(title));

class _PinDlg extends StatefulWidget {
  final String title;
  const _PinDlg(this.title);
  @override
  State<_PinDlg> createState() => _PinDlgState();
}

class _PinDlgState extends State<_PinDlg> {
  final t = TextEditingController();
  @override
  void dispose() {
    t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) => FxDialog(
        label: 'PARENTAL CONTROL',
        title: widget.title,
        width: 420,
        child: fxInput(t, '4-digit PIN',
            obscure: true,
            type: TextInputType.number,
            maxLen: 4,
            autofocus: true,
            onSubmit: (v) => Navigator.pop(c, v)),
        actions: [
          FxBtn('Cancel', () => Navigator.pop(c)),
          FxBtn('OK', () => Navigator.pop(c, t.text), primary: true),
        ],
      );
}

Future<bool> verifyPin(BuildContext c) async {
  final pin = Cfg.gs('pin');
  if (pin.isEmpty) return true;
  final e = await enterPin(c, 'Enter PIN');
  return e != null && e == pin;
}

// ---------------- Multi-screen layouts ----------------
// Rectangles inside a 100 x 70 box
List<Rect> layoutRects(int i) {
  switch (i) {
    case 1:
      return [
        const Rect.fromLTWH(0, 0, 100, 40),
        const Rect.fromLTWH(0, 44, 30, 26),
        const Rect.fromLTWH(35, 44, 30, 26),
        const Rect.fromLTWH(70, 44, 30, 26),
      ];
    case 2:
      return [
        const Rect.fromLTWH(0, 0, 100, 33),
        const Rect.fromLTWH(0, 37, 48, 33),
        const Rect.fromLTWH(52, 37, 48, 33),
      ];
    case 3:
      return [
        const Rect.fromLTWH(0, 0, 48, 25),
        const Rect.fromLTWH(52, 0, 48, 25),
        const Rect.fromLTWH(0, 29, 100, 41),
      ];
    case 4:
      return [
        const Rect.fromLTWH(0, 0, 48, 70),
        const Rect.fromLTWH(52, 0, 48, 70),
      ];
    case 5:
      return [
        const Rect.fromLTWH(0, 0, 100, 33),
        const Rect.fromLTWH(0, 37, 100, 33),
      ];
    default:
      return [
        const Rect.fromLTWH(0, 0, 48, 33),
        const Rect.fromLTWH(52, 0, 48, 33),
        const Rect.fromLTWH(0, 37, 48, 33),
        const Rect.fromLTWH(52, 37, 48, 33),
      ];
  }
}

class LayoutThumb extends StatelessWidget {
  final int index;
  final double width;
  const LayoutThumb(this.index, {this.width = 80, super.key});
  @override
  Widget build(BuildContext c) => CustomPaint(
        size: Size(width, width * 0.7),
        painter: _LayoutPainter(index),
      );
}

class _LayoutPainter extends CustomPainter {
  final int index;
  _LayoutPainter(this.index);
  @override
  void paint(Canvas c, Size s) {
    final k = s.width / 100;
    final p = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6;
    for (final r in layoutRects(index)) {
      c.drawRect(Rect.fromLTWH(r.left * k, r.top * k, r.width * k, r.height * k), p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => old is _LayoutPainter && old.index != index;
}

// ---------------- Home screen icons (drawn, so they stay sharp) ----------------
class TvIcon extends StatelessWidget {
  final double w;
  const TvIcon(this.w, {super.key});
  @override
  Widget build(BuildContext c) => CustomPaint(size: Size(w, w * 1.1), painter: _TvPainter());
}

class _TvPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final ant = Paint()
      ..color = const Color(0xFF4A4F5C)
      ..style = PaintingStyle.stroke
      ..strokeWidth = w * 0.035
      ..strokeCap = StrokeCap.round;
    c.drawLine(Offset(w * .50, h * .36), Offset(w * .10, h * .03), ant);
    c.drawLine(Offset(w * .50, h * .36), Offset(w * .90, h * .03), ant);
    final body = RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .02, h * .34, w * .96, h * .64), Radius.circular(w * .22));
    c.drawRRect(
        body,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF3A3F4C), Color(0xFF181B24)],
          ).createShader(body.outerRect));
    c.drawRRect(
        body,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .02
          ..color = const Color(0xFF555B6A));
    final tp = TextPainter(
      text: TextSpan(
          text: 'TV',
          style: TextStyle(color: Colors.white, fontSize: h * .36, fontWeight: FontWeight.w900)),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(c, Offset((w - tp.width) / 2, h * .34 + (h * .64 - tp.height) / 2));
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class PopcornIcon extends StatelessWidget {
  final double w;
  const PopcornIcon(this.w, {super.key});
  @override
  Widget build(BuildContext c) => CustomPaint(size: Size(w, w * 1.15), painter: _PopcornPainter());
}

class _PopcornPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final puff = Paint()..color = const Color(0xFFF8DFA8);
    final shade = Paint()..color = const Color(0xFFF2A94E);
    const puffs = [
      [.26, .30, .15],
      [.50, .20, .19],
      [.74, .30, .15],
      [.36, .42, .14],
      [.64, .42, .14],
      [.50, .36, .16],
    ];
    for (final p in puffs) {
      c.drawCircle(Offset(w * p[0], h * p[1]), w * p[2], puff);
    }
    c.drawCircle(Offset(w * .50, h * .40), w * .09, shade);
    c.drawCircle(Offset(w * .30, h * .36), w * .05, shade);
    c.drawCircle(Offset(w * .70, h * .36), w * .05, shade);
    final path = Path()
      ..moveTo(w * .08, h * .52)
      ..lineTo(w * .92, h * .52)
      ..lineTo(w * .82, h)
      ..lineTo(w * .18, h)
      ..close();
    c.drawPath(path, Paint()..color = Colors.white);
    c.save();
    c.clipPath(path);
    final st = Paint()..color = const Color(0xFF15161C);
    c.drawRect(Rect.fromLTWH(w * .30, h * .52, w * .13, h * .48), st);
    c.drawRect(Rect.fromLTWH(w * .57, h * .52, w * .13, h * .48), st);
    c.restore();
    c.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(0, h * .46, w, h * .10), Radius.circular(w * .03)),
        Paint()..color = Colors.white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

class ClapperIcon extends StatelessWidget {
  final double w;
  const ClapperIcon(this.w, {super.key});
  @override
  Widget build(BuildContext c) => CustomPaint(size: Size(w, w * .95), painter: _ClapperPainter());
}

void _stripes(Canvas c, Rect r, double w) {
  final rr = RRect.fromRectAndRadius(r, Radius.circular(w * .02));
  c.save();
  c.clipRRect(rr);
  c.drawRect(r, Paint()..color = const Color(0xFF111319));
  final wp = Paint()..color = Colors.white;
  final sw = r.width / 6;
  for (var i = 0; i < 6; i += 2) {
    final x = r.left + i * sw;
    final p = Path()
      ..moveTo(x + sw * .4, r.top)
      ..lineTo(x + sw * 1.4, r.top)
      ..lineTo(x + sw * 1.0, r.bottom)
      ..lineTo(x, r.bottom)
      ..close();
    c.drawPath(p, wp);
  }
  c.restore();
}

class _ClapperPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final w = s.width, h = s.height;
    final board = RRect.fromRectAndRadius(
        Rect.fromLTWH(w * .04, h * .42, w * .92, h * .56), Radius.circular(w * .06));
    c.drawRRect(board, Paint()..color = const Color(0xFF14171F));
    c.drawRRect(
        board,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = w * .015
          ..color = const Color(0xFF30343F));
    _stripes(c, Rect.fromLTWH(w * .04, h * .42, w * .92, h * .14), w);
    c.save();
    c.translate(w * .06, h * .40);
    c.rotate(-0.30);
    _stripes(c, Rect.fromLTWH(0, -h * .16, w * .9, h * .14), w);
    c.restore();
    c.drawCircle(Offset(w * .06, h * .46), w * .05, Paint()..color = Colors.black);
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}

// ---------------- "Poster Not Found" placeholder ----------------
class NoPoster extends StatelessWidget {
  const NoPoster({super.key});
  @override
  Widget build(BuildContext c) => CustomPaint(
        painter: _SunPainter(),
        child: Center(
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Transform.rotate(
                angle: -0.2,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                      color: const Color(0xFF1B1318), borderRadius: BorderRadius.circular(8)),
                  child: const Text('Poster\nNot Found',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          fontSize: 22, fontWeight: FontWeight.w800, height: 1.15, color: Colors.white)),
                ),
              ),
            ),
          ),
        ),
      );
}

class _SunPainter extends CustomPainter {
  @override
  void paint(Canvas c, Size s) {
    final ctr = Offset(s.width / 2, s.height / 2);
    final r = math.sqrt(s.width * s.width + s.height * s.height);
    c.drawRect(Offset.zero & s, Paint()..color = const Color(0xFFFBCB84));
    const n = 16;
    final p = Paint()..color = const Color(0xFFE8603A);
    for (var i = 0; i < n; i += 2) {
      final a0 = i * 2 * math.pi / n, a1 = (i + 1) * 2 * math.pi / n;
      final path = Path()
        ..moveTo(ctr.dx, ctr.dy)
        ..lineTo(ctr.dx + r * math.cos(a0), ctr.dy + r * math.sin(a0))
        ..lineTo(ctr.dx + r * math.cos(a1), ctr.dy + r * math.sin(a1))
        ..close();
      c.drawPath(path, p);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter old) => false;
}
