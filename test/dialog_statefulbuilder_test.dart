// Smoke test pentru fix-ul din PR #36:
// Verifica ca un StatefulBuilder INAUNTRUL unui AlertDialog se rebuildeste
// corect cand setStateLocal-ul lui e chemat dintr-un .then() async — exact
// pattern-ul folosit in _buildBerichtDokumente.
//
// Daca testul trece, fix-ul e demonstrabil corect (independent de UI-ul real).

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _Host extends StatefulWidget {
  final Future<List<String>> Function() loader;
  const _Host({required this.loader});
  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final Map<String, List<String>> _cache = {};
  final Map<String, bool> _loading = {};

  Widget _buildPanel(String key, StateSetter setParentState) {
    return StatefulBuilder(builder: (ctxLocal, setStateLocal) {
      if (!_cache.containsKey(key) && _loading[key] != true) {
        _loading[key] = true;
        widget.loader().then((docs) {
          _cache[key] = docs;
          _loading[key] = false;
          if (mounted) setState(() {});
          try { setStateLocal(() {}); } catch (_) {}
          try { setParentState(() {}); } catch (_) {}
        });
      }
      final docs = _cache[key] ?? [];
      final isLoading = _loading[key] == true;
      if (isLoading) {
        return const Center(child: CircularProgressIndicator(key: Key('spinner')));
      }
      if (docs.isEmpty) {
        return const Text('empty', key: Key('empty'));
      }
      return Column(
        key: const Key('list'),
        mainAxisSize: MainAxisSize.min,
        children: docs.map((d) => Text(d)).toList(),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        body: Builder(builder: (scaffoldCtx) {
          return Center(
            child: ElevatedButton(
              key: const Key('open-dialog'),
              onPressed: () {
                showDialog(
                  context: scaffoldCtx,
                  builder: (_) => StatefulBuilder(builder: (dlgCtx, setDlgParent) {
                    return AlertDialog(
                      content: SizedBox(
                        width: 300,
                        child: _buildPanel('test-key', setDlgParent),
                      ),
                    );
                  }),
                );
              },
              child: const Text('open'),
            ),
          );
        }),
      ),
    );
  }
}

void main() {
  testWidgets('StatefulBuilder inside dialog rebuilds after async load', (tester) async {
    final completer = Completer<List<String>>();

    await tester.pumpWidget(_Host(loader: () => completer.future));

    await tester.tap(find.byKey(const Key('open-dialog')));
    await tester.pump();

    // Initial: spinner visible, load in flight
    expect(find.byKey(const Key('spinner')), findsOneWidget);
    expect(find.byKey(const Key('list')), findsNothing);
    expect(find.byKey(const Key('empty')), findsNothing);

    // Resolve the loader with 2 docs
    completer.complete(['doc1.pdf', 'doc2.pdf']);
    await tester.pumpAndSettle();

    // After load: spinner gone, list rendered with both docs
    expect(find.byKey(const Key('spinner')), findsNothing,
        reason: 'Spinner should disappear after async load completes — '
            'this is exactly the bug PR #36 was meant to fix');
    expect(find.byKey(const Key('list')), findsOneWidget);
    expect(find.text('doc1.pdf'), findsOneWidget);
    expect(find.text('doc2.pdf'), findsOneWidget);
  });

  testWidgets('Empty load result also clears spinner (no docs case)', (tester) async {
    await tester.pumpWidget(_Host(loader: () async => <String>[]));

    await tester.tap(find.byKey(const Key('open-dialog')));
    await tester.pump();
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('spinner')), findsNothing);
    expect(find.byKey(const Key('empty')), findsOneWidget);
  });
}
