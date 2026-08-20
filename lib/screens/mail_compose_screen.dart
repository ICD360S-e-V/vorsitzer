import 'dart:async';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../models/mail_models.dart';
import '../services/api_service.dart';
import '../utils/file_picker_helper.dart';
import '../utils/mail_adressbuch.dart';
import '../utils/mail_sendeschutz.dart';
import '../utils/mail_vorlage.dart';
import 'mail_kontakte_screen.dart';
import 'mail_vorlagen_screen.dart';

/// Verfassen-Ansicht für eine neue, beantwortete oder weitergeleitete E-Mail.
///
/// Der Entwurf liegt auf dem Server, nicht auf dem Gerät: alle 5 Sekunden wird
/// gespeichert, sofern sich etwas geändert hat. Jede Verfassen-Sitzung hat eine
/// draft_id — daran erkennt der Server alle Kopien und löscht die älteren, damit
/// im Ordner Entwürfe immer genau einer liegt.
class MailComposeScreen extends StatefulWidget {
  final String selfEmail;
  final String? to;
  final String? cc;
  final String? subject;

  /// Fertig vorformulierter Brieftext, der **vor** der Signatur steht — anders
  /// als [quotedBody], das ans Ende gehört. Wird von Generatoren wie der
  /// Krankmeldung befüllt; der Vorsitzer kann ihn vor dem Senden noch ändern.
  final String? body;

  /// Vorbelegter Nachrichtentext (Zitat bei Antwort/Weiterleitung).
  final String? quotedBody;

  /// Message-ID der Nachricht, auf die geantwortet wird (Threading).
  final String? inReplyTo;

  /// References-Kette der Elternnachricht. Ohne sie verliert eine Antwort auf
  /// eine Antwort ihre Historie, und Gmail fädelt sie gar nicht mehr ein.
  final String? references;

  /// Bereits übernommene Anhänge (Weiterleitung).
  final List<MailOutgoingAttachment> initialAttachments;

  /// Weiterschreiben an einem gespeicherten Entwurf.
  final MailDraft? draft;

  /// Wird nach erfolgreichem Senden mit der Serverantwort aufgerufen — darin
  /// steht die `message_id`, ohne die sich später kein Sendebericht abrufen
  /// lässt. Der Rückgabewert des Bildschirms bleibt unverändert `true`, damit
  /// bestehende Aufrufer nichts merken.
  final void Function(Map<String, dynamic> antwort)? onSent;

  const MailComposeScreen({
    super.key,
    required this.selfEmail,
    this.to,
    this.cc,
    this.subject,
    this.body,
    this.quotedBody,
    this.inReplyTo,
    this.references,
    this.initialAttachments = const [],
    this.draft,
    this.onSent,
  });

  @override
  State<MailComposeScreen> createState() => _MailComposeScreenState();
}

class _MailComposeScreenState extends State<MailComposeScreen> {
  final _api = ApiService();
  final _toCtrl = TextEditingController();
  final _ccCtrl = TextEditingController();
  final _bccCtrl = TextEditingController();
  final _subjectCtrl = TextEditingController();
  final _bodyCtrl = TextEditingController();

  /// Noch nicht hochgeladene Anhänge — nur diese gehen beim nächsten Speichern
  /// über die Leitung.
  final List<MailOutgoingAttachment> _newAttachments = [];

  /// Schon im Entwurf auf dem Server liegende Anhänge.
  final List<MailStoredAttachment> _storedAttachments = [];

  late final String _draftId;

  bool _showCcBcc = false;
  bool _requestReceipt = false;
  bool _sending = false;
  bool _picking = false;
  String _signature = '';

  /// Adressen, unter denen dieses Postfach schreiben darf.
  List<Map<String, dynamic>> _absender = const [];
  String _gewaehlterAbsender = '';

  /// Läuft die Frist, in der das Senden noch zurückgeholt werden kann.
  Timer? _absendeUhr;
  int _restSekunden = 0;

  /// Es gibt Änderungen, die noch nicht auf dem Server sind.
  bool _dirty = false;

  /// Ein Speichervorgang läuft. Nie zwei gleichzeitig — sonst könnten sich zwei
  /// Aufräum-Durchläufe überkreuzen.
  bool _saving = false;
  DateTime? _savedAt;
  String? _saveError;
  Timer? _autosave;

  static const int _maxTotal = ApiService.mailMaxAttachmentBytes;

  /// PHP nimmt pro Request nur 20 Dateien an (max_file_uploads) und verwirft
  /// den Rest still — deshalb hier hart begrenzen.
  static const int _maxFiles = 20;

  static const Duration _autosaveInterval = Duration(seconds: 5);

  @override
  void initState() {
    super.initState();
    final d = widget.draft;
    _draftId = (d != null && d.draftId.isNotEmpty) ? d.draftId : _newDraftId();

    if (d != null) {
      _toCtrl.text = d.to;
      _ccCtrl.text = d.cc;
      _bccCtrl.text = d.bcc;
      _subjectCtrl.text = d.subject;
      _bodyCtrl.text = d.body;
      _requestReceipt = d.requestReceipt;
      _storedAttachments.addAll(d.attachments);
      _showCcBcc = d.cc.isNotEmpty || d.bcc.isNotEmpty;
      // It was already saved once, otherwise it would not be in Entwürfe.
      _savedAt = null;
    } else {
      _toCtrl.text = widget.to ?? '';
      _ccCtrl.text = widget.cc ?? '';
      _subjectCtrl.text = widget.subject ?? '';
      _showCcBcc = (widget.cc ?? '').isNotEmpty;
      _newAttachments.addAll(widget.initialAttachments);
      if (widget.initialAttachments.isNotEmpty) _dirty = true;
    }

    for (final c in [_toCtrl, _ccCtrl, _bccCtrl, _subjectCtrl, _bodyCtrl]) {
      c.addListener(_markDirty);
    }
    _gewaehlterAbsender = widget.selfEmail;
    _ladeAbsender();
    // A draft that is being continued already has its signature in the body.
    if (widget.draft == null) _loadSignature();
    _autosave = Timer.periodic(_autosaveInterval, (_) => _autosaveTick());
  }

  String _newDraftId() {
    final rnd = Random();
    final suffix = List.generate(8, (_) => rnd.nextInt(36).toRadixString(36)).join();
    return 'd${DateTime.now().millisecondsSinceEpoch}-$suffix';
  }

  void _markDirty() {
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _loadSignature() async {
    try {
      final res = await _api.getMailSignature();
      if (res['success'] != true || !mounted) return;
      _signature = '${res['signature'] ?? ''}';
      final receiptDefault = res['request_receipt_default'] == true;
      setState(() {
        _requestReceipt = receiptDefault;
        // Signature and quote are only inserted while the body is untouched, so
        // a fast typist never loses what they wrote.
        if (_bodyCtrl.text.isEmpty) _bodyCtrl.text = _initialBody();
      });
    } catch (_) {
      if (mounted && _bodyCtrl.text.isEmpty) {
        setState(() => _bodyCtrl.text = _initialBody());
      }
    }
  }

  String _initialBody() {
    final sb = StringBuffer('\n');
    // Der Brieftext endet mit der Grußformel, die Signatur trägt Vorstand und
    // Impressum — deshalb Text zuerst, Signatur danach.
    if ((widget.body ?? '').isNotEmpty) sb.write('${widget.body}\n');
    if (_signature.isNotEmpty) sb.write('\n$_signature');
    if ((widget.quotedBody ?? '').isNotEmpty) sb.write('\n${widget.quotedBody}');
    return sb.toString();
  }

  /// Holt die erlaubten Absenderadressen.
  ///
  /// ⚠️ Scheitert der Aufruf, bleibt es beim eigenen Postfach und die Auswahl
  /// erscheint gar nicht. Ein leeres Auswahlfeld anzubieten wäre schlimmer als
  /// keines: es sähe aus, als wäre die Adresse verloren gegangen.
  Future<void> _ladeAbsender() async {
    try {
      final res = await _api.getMailAbsender();
      if (res['success'] != true || !mounted) return;
      final liste = ((res['absender'] as List?) ?? const [])
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
      if (liste.isEmpty) return;
      setState(() {
        _absender = liste;
        // Beim Weiterschreiben eines Entwurfs oder beim Antworten kann schon
        // eine Adresse gesetzt sein; nur wenn sie es nicht ist, gilt die erste.
        if (!liste.any((a) => '${a['adresse']}' == _gewaehlterAbsender)) {
          _gewaehlterAbsender = '${liste.first['adresse']}';
        }
      });
    } catch (_) {/* Absenderwahl ist eine Zugabe, kein Muss */}
  }

  @override
  void dispose() {
    _absendeUhr?.cancel();
    _autosave?.cancel();
    for (final c in [_toCtrl, _ccCtrl, _bccCtrl, _subjectCtrl, _bodyCtrl]) {
      c.removeListener(_markDirty);
    }
    _toCtrl.dispose();
    _ccCtrl.dispose();
    _bccCtrl.dispose();
    _subjectCtrl.dispose();
    _bodyCtrl.dispose();
    super.dispose();
  }

  int get _totalBytes =>
      _newAttachments.fold(0, (s, a) => s + a.size) +
      _storedAttachments.fold(0, (s, a) => s + a.size);

  int get _attachmentCount => _newAttachments.length + _storedAttachments.length;

  bool get _hasContent =>
      _toCtrl.text.trim().isNotEmpty ||
      _ccCtrl.text.trim().isNotEmpty ||
      _bccCtrl.text.trim().isNotEmpty ||
      _subjectCtrl.text.trim().isNotEmpty ||
      _bodyCtrl.text.trim().isNotEmpty ||
      _attachmentCount > 0;

  // ---------------- autosave ----------------

  void _autosaveTick() {
    if (!mounted || _sending || _saving || !_dirty) return;
    if (!_hasContent) return; // nothing worth keeping yet
    _saveDraft();
  }

  Future<bool> _saveDraft() async {
    if (_saving || _sending) return false;
    setState(() {
      _saving = true;
      _saveError = null;
    });
    // Clear the flag up front: edits made while the request is in flight should
    // mark it dirty again and trigger another save, not be swallowed.
    _dirty = false;
    final uploading = List<MailOutgoingAttachment>.from(_newAttachments);
    try {
      final res = await _api.saveMailDraft(
        draftId: _draftId,
        to: _toCtrl.text.trim(),
        cc: _ccCtrl.text.trim(),
        bcc: _bccCtrl.text.trim(),
        subject: _subjectCtrl.text.trim(),
        body: _bodyCtrl.text,
        requestReceipt: _requestReceipt,
        inReplyTo: widget.draft?.inReplyTo ?? widget.inReplyTo ?? '',
        references: widget.draft?.references ?? widget.references ?? '',
        keepAttachments: _storedAttachments.map((a) => a.index).toList(),
        newAttachments: uploading,
      );
      if (!mounted) return false;
      if (res['success'] == true) {
        // The server reports the stored layout; everything we just uploaded is
        // now part of the draft and must never be uploaded again.
        final stored = ((res['attachments'] as List?) ?? const [])
            .whereType<Map>()
            .map((a) => MailStoredAttachment.fromJson(Map<String, dynamic>.from(a)))
            .toList();
        setState(() {
          _storedAttachments
            ..clear()
            ..addAll(stored);
          _newAttachments.removeRange(0, uploading.length);
          _savedAt = DateTime.now();
          _saving = false;
        });
        return true;
      }
      setState(() {
        _saving = false;
        _dirty = true; // failed -> still unsaved
        _saveError = res['message']?.toString() ?? 'Entwurf konnte nicht gespeichert werden.';
      });
      return false;
    } catch (e) {
      if (!mounted) return false;
      setState(() {
        _saving = false;
        _dirty = true;
        _saveError = 'Entwurf nicht gespeichert — keine Verbindung.';
      });
      return false;
    }
  }

  Future<void> _saveNow() async {
    final ok = await _saveDraft();
    if (!mounted) return;
    if (ok) _toast('Entwurf gespeichert');
  }

  Future<void> _discardDraft() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Entwurf verwerfen?'),
        content: const Text('Der Entwurf wird gelöscht und die Nachricht nicht gesendet.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('Weiterschreiben')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('Verwerfen')),
        ],
      ),
    );
    if (ok != true) return;
    _autosave?.cancel();
    _dirty = false;
    try {
      await _api.deleteMailDraft(_draftId);
    } catch (_) {/* the sweep on the next save would clean it up anyway */}
    if (mounted) Navigator.pop(context, false);
  }

  /// Beim Verlassen still speichern — kein Dialog, wie bei Gmail.
  Future<bool> _onWillPop() async {
    if (_sending) return false;
    if (_dirty && _hasContent) {
      _autosave?.cancel();
      await _saveDraft();
      if (mounted && _saveError != null) {
        // Do not silently lose work when the save failed.
        final leave = await showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Entwurf nicht gespeichert'),
            content: Text('$_saveError\n\nTrotzdem schließen? Der Text wäre dann weg.'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(ctx, false),
                  child: const Text('Weiterschreiben')),
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, true),
                  child: const Text('Schließen')),
            ],
          ),
        );
        return leave == true;
      }
    }
    return true;
  }

  // ---------------- attachments ----------------

  bool _validEmail(String s) =>
      RegExp(r'^[a-zA-Z0-9._%+-]+@[a-zA-Z0-9.-]+\.[a-zA-Z]{2,}$').hasMatch(s.trim());

  /// Prüft eine Komma-Liste von Adressen; gibt die erste ungültige zurück.
  String? _firstInvalid(String raw) {
    for (final a in raw.split(',')) {
      if (a.trim().isEmpty) continue;
      if (!_validEmail(a)) return a.trim();
    }
    return null;
  }

  void _toast(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  // ---------------- Adressbuch ----------------

  /// Empfängerfeld mit dem Adressbuch-Knopf daneben.
  ///
  /// ⚠️ **Neben** dem Feld, nicht darunter und nicht als blasses `suffixIcon` —
  /// genauso wie am Telefon neben dem Nummernfeld. Wer eine Adresse sucht,
  /// sucht sie, BEVOR er tippt; ein Knopf unterhalb des Feldes wird erst
  /// gefunden, wenn man schon halb getippt hat.
  ///
  /// ⚠️ Oben ausgerichtet, nicht mittig: „An" trägt einen Hilfetext, der das
  /// Feld höher macht. Mittig gesetzt stünde der Knopf bei „An" tiefer als bei
  /// „Cc" und „Bcc", und drei Knöpfe auf drei Höhen sehen aus wie ein Fehler.
  Widget _empfaengerfeld(
    TextEditingController ctrl,
    String feld, {
    String? helferText,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: TextField(
            controller: ctrl,
            keyboardType: TextInputType.emailAddress,
            decoration: InputDecoration(
              labelText: feld,
              helperText: helferText,
              border: const OutlineInputBorder(),
            ),
          ),
        ),
        const SizedBox(width: 8),
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: IconButton.filledTonal(
            icon: const Icon(Icons.contacts_outlined),
            tooltip: 'Adressbuch — Empfänger für „$feld" suchen',
            onPressed: () => _adressbuchOeffnen(ctrl, feld),
          ),
        ),
      ],
    );
  }

  Future<void> _adressbuchOeffnen(
      TextEditingController ctrl, String feld) async {
    final gewaehlt = await Navigator.push<List<String>>(
      context,
      MaterialPageRoute(builder: (_) => MailKontakteScreen(feldName: feld)),
    );
    if (gewaehlt == null || gewaehlt.isEmpty || !mounted) return;

    // ⚠️ Anhängen, nicht ersetzen: wer die erste Adresse schon getippt hat,
    // verlöre sie sonst mit einem Griff ins Adressbuch — ohne Warnung und ohne
    // Weg zurück.
    final vorher = ctrl.text;
    final nachher = mailAdressenAnhaengen(vorher, gewaehlt);
    setState(() {
      ctrl.text = nachher;
      _dirty = true;
    });

    // Wurde nichts länger, war alles schon drin. Das gehört gesagt — sonst
    // sieht es aus, als hätte der Knopf nichts getan.
    final neu = mailAdressenAufteilen(nachher).length -
        mailAdressenAufteilen(vorher).length;
    if (neu == 0) {
      _toast(gewaehlt.length == 1
          ? 'Diese Adresse steht schon in „$feld".'
          : 'Diese Adressen stehen schon in „$feld".');
    } else if (neu < gewaehlt.length) {
      _toast('$neu von ${gewaehlt.length} Adressen ergänzt — '
          'der Rest stand schon in „$feld".');
    }
  }

  Future<void> _pickAttachments() async {
    if (_picking) return;
    setState(() => _picking = true);
    try {
      final result = await FilePickerHelper.pickFiles(
        dialogTitle: 'Anhänge auswählen',
        allowMultiple: true,
        withData: true,
      );
      if (result == null || !mounted) return;

      var used = _totalBytes;
      var count = _attachmentCount;
      final added = <MailOutgoingAttachment>[];
      final tooBig = <String>[];
      final tooMany = <String>[];
      for (final f in result.files) {
        final bytes = f.bytes;
        if (bytes == null) {
          tooBig.add(f.name);
          continue;
        }
        if (count >= _maxFiles) {
          tooMany.add(f.name);
          continue;
        }
        if (used + bytes.length > _maxTotal) {
          tooBig.add(f.name);
          continue;
        }
        used += bytes.length;
        count++;
        added.add(MailOutgoingAttachment(
          filename: f.name,
          bytes: Uint8List.fromList(bytes),
        ));
      }
      setState(() {
        _newAttachments.addAll(added);
        if (added.isNotEmpty) _dirty = true;
      });
      if (tooBig.isNotEmpty) {
        _toast('Kein Platz mehr für: ${tooBig.join(', ')} — '
            'insgesamt sind 25 MB möglich.');
      }
      if (tooMany.isNotEmpty) {
        _toast('Mehr als $_maxFiles Dateien pro E-Mail sind nicht möglich. '
            'Nicht übernommen: ${tooMany.join(', ')}');
      }
    } catch (e) {
      _toast('Anhang konnte nicht gelesen werden.');
    } finally {
      if (mounted) setState(() => _picking = false);
    }
  }

  // ---------------- send ----------------

  Future<void> _send() async {
    final to = _toCtrl.text.trim();
    if (to.isEmpty) {
      _toast('Bitte mindestens einen Empfänger angeben.');
      return;
    }
    for (final field in [to, _ccCtrl.text, _bccCtrl.text]) {
      final bad = _firstInvalid(field);
      if (bad != null) {
        _toast('Diese Adresse stimmt nicht: $bad');
        return;
      }
    }
    if (_subjectCtrl.text.trim().isEmpty) {
      final go = await showDialog<bool>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Ohne Betreff senden?'),
          content: const Text('Die E-Mail hat keinen Betreff.'),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Zurück')),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Trotzdem senden')),
          ],
        ),
      );
      if (go != true) return;
    }

    // Die drei Rückfragen. Sie stehen NACH der Adressprüfung und VOR der
    // Frist: was hier auffällt, soll man beheben können, ohne erst 15 Sekunden
    // zu warten.
    if (!await _sendeschutzBestanden()) return;

    _autosave?.cancel();
    _starteRueckholfrist();
  }

  /// Zeigt, was vor dem Senden auffällt. Gibt false zurück, wenn abgebrochen
  /// wurde oder etwas geändert wurde, das erneut geprüft gehört.
  Future<bool> _sendeschutzBestanden() async {
    final befunde = mailSendeBefunde(
      to: _toCtrl.text,
      cc: _ccCtrl.text,
      bcc: _bccCtrl.text,
      koerper: _bodyCtrl.text,
      anhangAnzahl: _attachmentCount,
    );
    for (final b in befunde) {
      final antwort = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(b.titel),
          content: Text(b.text),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'zurueck'),
                child: const Text('Zurück')),
            if (b.behebenLabel != null)
              FilledButton(
                  onPressed: () => Navigator.pop(ctx, 'beheben'),
                  child: Text(b.behebenLabel!)),
            TextButton(
                onPressed: () => Navigator.pop(ctx, 'trotzdem'),
                child: const Text('Trotzdem senden')),
          ],
        ),
      );
      if (!mounted) return false;
      if (antwort == null || antwort == 'zurueck') return false;
      if (antwort == 'beheben') {
        if (b.art == MailSendeWarnung.offeneEmpfaengerliste) {
          final neu = mailNachBcc(
              to: _toCtrl.text, cc: _ccCtrl.text, bcc: _bccCtrl.text);
          setState(() {
            _toCtrl.text = neu.to;
            _ccCtrl.text = neu.cc;
            _bccCtrl.text = neu.bcc;
            _showCcBcc = true;
            _dirty = true;
          });
          _toast('Die Empfänger stehen jetzt im Bcc.');
        }
        // Nach einer Änderung von vorn prüfen: die Behebung kann einen anderen
        // Befund erst sichtbar machen.
        return _sendeschutzBestanden();
      }
    }
    return true;
  }

  /// Die Frist, in der ein Versand noch zurückgeholt werden kann.
  ///
  /// ⚠️ Bewusst im Client und NICHT als Warteschlange auf dem Server: eine
  /// Mail, die serverseitig 15 Sekunden liegt, ist bereits abgegeben — stürzt
  /// die App ab, geht sie trotzdem hinaus. Hier ist sie in diesen Sekunden noch
  /// nirgends, und „Rückgängig" heißt wirklich: nicht gesendet.
  void _starteRueckholfrist() {
    setState(() {
      _sending = true;
      _restSekunden = kMailSendeVerzoegerung.inSeconds;
    });
    _absendeUhr?.cancel();
    _absendeUhr = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _restSekunden--);
      if (_restSekunden <= 0) {
        t.cancel();
        _wirklichSenden();
      }
    });
  }

  void _sendenAbbrechen() {
    _absendeUhr?.cancel();
    setState(() {
      _sending = false;
      _restSekunden = 0;
    });
    _autosave = Timer.periodic(_autosaveInterval, (_) => _autosaveTick());
    _toast('Nicht gesendet — die E-Mail ist noch hier.');
  }

  Future<void> _wirklichSenden() async {
    final to = _toCtrl.text.trim();
    if (!mounted) return;
    try {
      final res = await _api.sendMail(
        absender: _gewaehlterAbsender == widget.selfEmail
            ? ''
            : _gewaehlterAbsender,
        to: to,
        cc: _ccCtrl.text.trim(),
        bcc: _bccCtrl.text.trim(),
        subject: _subjectCtrl.text.trim(),
        body: _bodyCtrl.text,
        requestReceipt: _requestReceipt,
        inReplyTo: widget.draft?.inReplyTo ?? widget.inReplyTo ?? '',
        references: widget.draft?.references ?? widget.references ?? '',
        attachments: _newAttachments,
        // Attachments already in the draft stay on the server — naming them
        // spares a download-and-re-upload of everything.
        draftId: _draftId,
        keepAttachments: _storedAttachments.map((a) => a.index).toList(),
      );
      if (!mounted) return;
      if (res['success'] == true) {
        widget.onSent?.call(Map<String, dynamic>.from(res));
        Navigator.pop(context, true);
      } else {
        setState(() {
          _sending = false;
          _restSekunden = 0;
        });
        _autosave = Timer.periodic(_autosaveInterval, (_) => _autosaveTick());
        _toast(res['message']?.toString() ?? 'Senden fehlgeschlagen.');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _restSekunden = 0;
      });
      _autosave = Timer.periodic(_autosaveInterval, (_) => _autosaveTick());
      _toast('Keine Verbindung zum Server.');
    }
  }

  // ---------------- Vorlagen ----------------

  /// Öffnet die Bausteinliste und setzt den gewählten Text ein.
  ///
  /// ⚠️ Eingefügt wird VOR der Signatur und ohne irgendetwas zu überschreiben:
  /// wer schon zwei Sätze getippt hat, verliert sie nicht, weil er eine Vorlage
  /// nachschlägt. Der Text landet an der Schreibmarke, nicht am Anfang.
  Future<void> _vorlageEinfuegen() async {
    final gewaehlt = await Navigator.push<MailVorlage>(
      context,
      MaterialPageRoute(builder: (_) => const MailVorlagenScreen()),
    );
    if (gewaehlt == null || !mounted) return;

    final text = mailVorlageFuellen(
        gewaehlt.text, MailVorlageDaten(heute: DateTime.now()));

    final alt = _bodyCtrl.text;
    final stelle = _bodyCtrl.selection.isValid
        ? _bodyCtrl.selection.start
        : 0;
    final neu = alt.substring(0, stelle) + text + alt.substring(stelle);
    setState(() {
      _bodyCtrl.text = neu;
      _bodyCtrl.selection =
          TextSelection.collapsed(offset: stelle + text.length);
      if (_subjectCtrl.text.trim().isEmpty && gewaehlt.betreff.isNotEmpty) {
        _subjectCtrl.text = gewaehlt.betreff;
      }
      _dirty = true;
    });

    // Offene Platzhalter benennen. Sie STEHEN LASSEN und nichts sagen wäre der
    // Fehler: „Sehr geehrte {anrede}," geht sonst genau so hinaus.
    final offen = mailVorlageOffenePlatzhalter(text);
    if (offen.isNotEmpty) {
      _toast(offen.length == 1
          ? 'Noch auszufüllen: {${offen.first}}'
          : 'Noch auszufüllen: ${offen.map((o) => '{$o}').join(', ')}');
    }
  }

  // ---------------- ui ----------------

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final canLeave = await _onWillPop();
        // The captured context needs its own mounted check, not State.mounted.
        if (!context.mounted) return;
        if (canLeave) Navigator.pop(context, false);
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(widget.draft != null ? 'Entwurf' : 'Neue E-Mail'),
          actions: [
            if (_sending)
              const Padding(
                padding: EdgeInsets.all(14),
                child: SizedBox(
                    width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)),
              )
            else ...[
              IconButton(
                icon: const Icon(Icons.article_outlined),
                tooltip: 'Textbaustein einfügen',
                onPressed: _vorlageEinfuegen,
              ),
              IconButton(
                icon: const Icon(Icons.attach_file),
                tooltip: 'Anhang hinzufügen',
                onPressed: _picking ? null : _pickAttachments,
              ),
              IconButton(
                icon: const Icon(Icons.save_outlined),
                tooltip: 'Als Entwurf speichern',
                onPressed: _saving ? null : _saveNow,
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline),
                tooltip: 'Entwurf verwerfen',
                onPressed: _discardDraft,
              ),
              IconButton(
                icon: const Icon(Icons.send),
                tooltip: 'Senden',
                onPressed: _send,
              ),
            ],
          ],
        ),
        body: AbsorbPointer(
          // ⚠️ Während der Rückholfrist bleibt alles bedienbar: der Knopf
          // „Rückgängig" steht zwar in der unteren Leiste, aber ein gesperrter
          // Bildschirm dahinter fühlt sich an, als wäre schon alles vorbei.
          absorbing: _sending && _restSekunden <= 0,
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Row(
                children: [
                  Text('Von: ', style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13)),
                  Expanded(child: _absenderWahl(cs)),
                  if (!_showCcBcc)
                    TextButton(
                      onPressed: () => setState(() => _showCcBcc = true),
                      child: const Text('Cc/Bcc'),
                    ),
                ],
              ),
              const SizedBox(height: 8),
              _empfaengerfeld(
                _toCtrl,
                'An',
                helferText: 'Mehrere Adressen mit Komma trennen',
              ),
              if (_showCcBcc) ...[
                const SizedBox(height: 12),
                _empfaengerfeld(_ccCtrl, 'Cc'),
                const SizedBox(height: 12),
                _empfaengerfeld(_bccCtrl, 'Bcc'),
              ],
              const SizedBox(height: 12),
              TextField(
                controller: _subjectCtrl,
                decoration: const InputDecoration(
                    labelText: 'Betreff', border: OutlineInputBorder()),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _bodyCtrl,
                minLines: 10,
                maxLines: 24,
                keyboardType: TextInputType.multiline,
                decoration: const InputDecoration(
                  labelText: 'Nachricht',
                  alignLabelWithHint: true,
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 16),
              _attachmentSection(cs),
              const SizedBox(height: 8),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _requestReceipt,
                onChanged: (v) => setState(() {
                  _requestReceipt = v;
                  _dirty = true;
                }),
                title: const Text('Lesebestätigung anfordern',
                    style: TextStyle(fontSize: 14)),
                subtitle: const Text(
                  'Der Empfänger wird gefragt, ob er das Öffnen bestätigt. '
                  'Der Status steht danach im Ausgang.',
                  style: TextStyle(fontSize: 12),
                ),
              ),
              if (_sending) ...[
                const SizedBox(height: 8),
                const LinearProgressIndicator(),
                const SizedBox(height: 6),
                Center(
                  child: Text(
                    _newAttachments.isEmpty
                        ? 'Wird gesendet …'
                        : 'Wird gesendet — ${_fmtSize(_newAttachments.fold(0, (s, a) => s + a.size))} werden übertragen …',
                    style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ],
          ),
        ),
        bottomNavigationBar:
            _restSekunden > 0 ? _fristLeiste(cs) : _saveStatusBar(cs),
      ),
    );
  }

  /// Die Zeile „Von:" — eine Auswahl, sobald es mehr als eine Adresse gibt.
  ///
  /// ⚠️ Bei genau einer Adresse bleibt es beim schlichten Text. Ein Auswahlfeld
  /// mit einem einzigen Eintrag sieht aus wie eine Wahl und ist keine.
  Widget _absenderWahl(ColorScheme cs) {
    if (_absender.length < 2) {
      return Text(_gewaehlterAbsender,
          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600));
    }
    return DropdownButtonHideUnderline(
      child: DropdownButton<String>(
        value: _gewaehlterAbsender,
        isDense: true,
        isExpanded: true,
        style: TextStyle(fontSize: 13, color: cs.onSurface),
        onChanged: (v) {
          if (v == null) return;
          setState(() {
            _gewaehlterAbsender = v;
            _dirty = true;
          });
        },
        items: [
          for (final a in _absender)
            DropdownMenuItem(
              value: '${a['adresse']}',
              child: Row(
                children: [
                  Flexible(
                    child: Text('${a['adresse']}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w600)),
                  ),
                  if ('${a['label'] ?? ''}'.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text('${a['label']}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 11.5, color: cs.onSurfaceVariant)),
                    ),
                  ],
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// Die Leiste während der Rückholfrist. Sie ersetzt die Speicheranzeige,
  /// damit an dieser Stelle immer genau eine Aussage steht.
  Widget _fristLeiste(ColorScheme cs) {
    return Material(
      color: cs.tertiaryContainer,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Icon(Icons.schedule_send, size: 18, color: cs.onTertiaryContainer),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Wird in $_restSekunden Sekunden gesendet …',
                  style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.onTertiaryContainer),
                ),
              ),
              // Bewusst ein großer, beschrifteter Knopf und kein Symbol: er ist
              // in diesen Sekunden das Einzige, was jemand sucht.
              FilledButton.tonalIcon(
                onPressed: _sendenAbbrechen,
                icon: const Icon(Icons.undo, size: 18),
                label: const Text('Rückgängig'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Zeigt, wann der Entwurf zuletzt gespeichert wurde.
  Widget _saveStatusBar(ColorScheme cs) {
    IconData icon;
    String text;
    Color color;

    if (_saving) {
      icon = Icons.cloud_sync_outlined;
      text = 'Entwurf wird gespeichert …';
      color = cs.onSurfaceVariant;
    } else if (_saveError != null) {
      icon = Icons.cloud_off;
      text = _saveError!;
      color = cs.error;
    } else if (_savedAt != null) {
      icon = Icons.cloud_done_outlined;
      text = 'Entwurf gespeichert am ${_fmtDate(_savedAt!)} um ${_fmtTime(_savedAt!)}';
      color = const Color(0xFF2E9E4F);
    } else if (_dirty && _hasContent) {
      icon = Icons.edit_outlined;
      text = 'Noch nicht gespeichert';
      color = cs.onSurfaceVariant;
    } else {
      icon = Icons.edit_outlined;
      text = 'Entwurf wird alle 5 Sekunden gespeichert';
      color = cs.onSurfaceVariant;
    }

    return Material(
      color: cs.surfaceContainerLow,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
          child: Row(
            children: [
              if (_saving)
                SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: color),
                )
              else
                Icon(icon, size: 15, color: color),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w500),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _attachmentSection(ColorScheme cs) {
    final total = _totalBytes;
    final ratio = (total / _maxTotal).clamp(0.0, 1.0);
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        border: Border.all(color: cs.outlineVariant),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.attach_file, size: 18, color: cs.onSurfaceVariant),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Anhänge',
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
              ),
              Text(
                _attachmentCount == 0
                    ? 'max. 25 MB'
                    : '$_attachmentCount/$_maxFiles · ${_fmtSize(total)} von 25 MB',
                style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
              ),
            ],
          ),
          if (_attachmentCount == 0) ...[
            const SizedBox(height: 8),
            Text('Noch keine Dateien ausgewählt.',
                style: TextStyle(fontSize: 12.5, color: cs.onSurfaceVariant)),
            const SizedBox(height: 4),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _picking ? null : _pickAttachments,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Dateien auswählen'),
              ),
            ),
          ] else ...[
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: ratio,
                minHeight: 4,
                color: ratio > 0.9 ? const Color(0xFFE08A00) : cs.primary,
              ),
            ),
            const SizedBox(height: 4),
            for (var i = 0; i < _storedAttachments.length; i++)
              _attachmentTile(
                cs,
                name: _storedAttachments[i].name,
                size: _storedAttachments[i].size,
                uploaded: true,
                onRemove: () => setState(() {
                  _storedAttachments.removeAt(i);
                  _dirty = true;
                }),
              ),
            for (var i = 0; i < _newAttachments.length; i++)
              _attachmentTile(
                cs,
                name: _newAttachments[i].filename,
                size: _newAttachments[i].size,
                uploaded: false,
                onRemove: () => setState(() {
                  _newAttachments.removeAt(i);
                  _dirty = true;
                }),
              ),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                onPressed: (_picking || _attachmentCount >= _maxFiles)
                    ? null
                    : _pickAttachments,
                icon: const Icon(Icons.add, size: 18),
                label: const Text('Weitere Datei'),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _attachmentTile(
    ColorScheme cs, {
    required String name,
    required int size,
    required bool uploaded,
    required VoidCallback onRemove,
  }) {
    return ListTile(
      dense: true,
      contentPadding: EdgeInsets.zero,
      leading: Icon(_iconFor(name), size: 20),
      title: Text(name,
          maxLines: 1, overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontSize: 13.5)),
      subtitle: Row(
        children: [
          Text(_fmtSize(size), style: const TextStyle(fontSize: 11.5)),
          if (uploaded) ...[
            const SizedBox(width: 6),
            Icon(Icons.cloud_done_outlined, size: 12, color: cs.onSurfaceVariant),
            const SizedBox(width: 3),
            Text('im Entwurf',
                style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant)),
          ],
        ],
      ),
      trailing: IconButton(
        icon: const Icon(Icons.close, size: 18),
        tooltip: 'Anhang entfernen',
        onPressed: onRemove,
      ),
    );
  }
}

IconData _iconFor(String filename) {
  final ext = filename.contains('.') ? filename.split('.').last.toLowerCase() : '';
  switch (ext) {
    case 'pdf':
      return Icons.picture_as_pdf;
    case 'jpg':
    case 'jpeg':
    case 'png':
    case 'gif':
    case 'webp':
    case 'heic':
      return Icons.image_outlined;
    case 'doc':
    case 'docx':
    case 'odt':
    case 'rtf':
      return Icons.description_outlined;
    case 'xls':
    case 'xlsx':
    case 'ods':
    case 'csv':
      return Icons.table_chart_outlined;
    case 'zip':
    case '7z':
    case 'rar':
    case 'gz':
      return Icons.folder_zip_outlined;
    case 'mp3':
    case 'wav':
    case 'ogg':
    case 'm4a':
      return Icons.audiotrack_outlined;
    case 'mp4':
    case 'mov':
    case 'mkv':
    case 'webm':
      return Icons.movie_outlined;
    default:
      return Icons.insert_drive_file_outlined;
  }
}

String _fmtSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
  return '${(bytes / 1024 / 1024).toStringAsFixed(1)} MB';
}

String _two(int n) => n.toString().padLeft(2, '0');

String _fmtDate(DateTime d) => '${_two(d.day)}.${_two(d.month)}.${d.year}';

String _fmtTime(DateTime d) => '${_two(d.hour)}:${_two(d.minute)}';
