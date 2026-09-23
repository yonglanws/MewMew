import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:mewmew/models/models.dart';
import 'package:mewmew/widgets/mini_group_avatar.dart';
import 'package:mewmew/widgets/persona_avatar.dart';

Persona persona(String id, String emoji) =>
    Persona(id: id, name: id, emoji: emoji);

Widget host(Widget child) => MaterialApp(
  home: Scaffold(body: Center(child: child)),
);

void main() {
  testWidgets('多成员群头像：44 圆角容器内 2x2 均分网格，头像互不重叠', (tester) async {
    await tester.pumpWidget(
      host(
        MiniGroupAvatar(
          members: [
            persona('a', '🐱'),
            persona('b', '🐶'),
            persona('c', '🐰'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();

    // 容器整体 44x44，三个成员头像都渲染出来
    final box = tester.renderObject<RenderBox>(
      find.byType(MiniGroupAvatar),
    );
    expect(box.size.width, 44);
    expect(box.size.height, 44);
    expect(find.byType(PersonaAvatar), findsNWidgets(3));

    // 2x2 网格：任意两个头像圆心距 >= 头像直径（不重叠）
    final centers = tester
        .widgetList<PersonaAvatar>(find.byType(PersonaAvatar))
        .map((w) => tester.getCenter(find.byWidget(w)))
        .toList();
    for (var i = 0; i < centers.length; i++) {
      for (var j = i + 1; j < centers.length; j++) {
        expect(
          (centers[i] - centers[j]).distance,
          greaterThanOrEqualTo(17.0),
          reason: '成员头像发生了重叠',
        );
      }
    }
  });

  testWidgets('单成员群头像：居中单头像；空群：居中群图标', (tester) async {
    await tester.pumpWidget(
      host(MiniGroupAvatar(members: [persona('a', '🐱')])),
    );
    await tester.pumpAndSettle();
    // 单成员：半径 20（44/2 - 2）的头像
    expect(
      tester.widgetList<PersonaAvatar>(
        find.descendant(
          of: find.byType(MiniGroupAvatar),
          matching: find.byType(PersonaAvatar),
        ),
      ),
      isNotEmpty,
    );
    final single = tester.firstWidget<PersonaAvatar>(
      find.descendant(
        of: find.byType(MiniGroupAvatar),
        matching: find.byType(PersonaAvatar),
      ),
    );
    expect(single.radius, 20);
    expect(find.byIcon(Icons.group_outlined), findsNothing);

    await tester.pumpWidget(host(const MiniGroupAvatar(members: [])));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.group_outlined), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(MiniGroupAvatar),
        matching: find.byType(PersonaAvatar),
      ),
      findsNothing,
    );
  });

  testWidgets('超过 4 个成员只取前 4 个进入网格', (tester) async {
    await tester.pumpWidget(
      host(
        MiniGroupAvatar(
          members: [
            persona('a', '🐱'),
            persona('b', '🐶'),
            persona('c', '🐰'),
            persona('d', '🦊'),
            persona('e', '🐼'),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(PersonaAvatar), findsNWidgets(4));
  });
}
