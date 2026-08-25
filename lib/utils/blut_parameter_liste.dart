/// Alle Laborwerte, die im Blutwerte-Formular erfasst werden koennen.
///
/// ⚠️ EINE Liste fuer ALLE sechs Aerzte-Dialoge. Vorher stand sie als
/// `_blutParameter` in jedem der sechs Widgets — sechs Kopien, die auseinander
/// laufen, sobald jemand einen Parameter nur an einer Stelle ergaenzt. Bei 36
/// Eintraegen war das laestig, bei 170 waere es nicht mehr zu pflegen.
///
/// ⚠️ Die Schluessel sind der SPEICHER. Sie stehen so in der verschluesselten
/// Historie (`werte: {key: wert}`) und in `blut_parameter.php` auf dem Server,
/// der aus einem Befund liest. Ein Schluessel wird nie umbenannt — sonst ist
/// der gespeicherte Wert nicht mehr auffindbar, und der Befund-Import traegt
/// ihn in ein Feld ein, das es nicht mehr gibt.
///
/// ⚠️ Die 36 Eintraege, die es vorher schon gab, sind hier ZEICHENGLEICH
/// uebernommen — Bezeichnung, Einheit und Referenzbereich. Sie zu
/// „vereinheitlichen" hiesse, Grenzwerte zu verschieben, die jemand laengst
/// liest.
///
/// ⚠️ Referenzbereiche sind METHODENABHAENGIG. Der Bereich, den das Labor auf
/// den Befund druckt, geht immer vor; die Werte hier faerben nur
/// „hoch/niedrig" ein und sind keine Diagnose.
///
/// [maennlich] steuert die geschlechtsabhaengigen Bereiche.
List<Map<String, dynamic>> blutParameterListe(bool maennlich) {
  final m = maennlich;
  // ignore: unnecessary_statements
  m;
  return [
    // ── Blutbild ──
    {'key': 'erythrozyten', 'label': 'Erythrozyten', 'unit': 'Mio/µl', 'min': m ? 4.3 : 3.8, 'max': m ? 5.9 : 5.2, 'gruppe': 'Blutbild'},
    {'key': 'rdw', 'label': 'Erythrozytenverteilungsbreite', 'unit': '%', 'min': 11.5, 'max': 14.5, 'gruppe': 'Blutbild'},
    {'key': 'haematokrit', 'label': 'Hämatokrit', 'unit': '%', 'min': m ? 40.0 : 35.0, 'max': m ? 52.0 : 47.0, 'gruppe': 'Blutbild'},
    {'key': 'haemoglobin', 'label': 'Hämoglobin', 'unit': 'g/dl', 'min': m ? 13.5 : 12.0, 'max': m ? 17.5 : 16.0, 'gruppe': 'Blutbild'},
    {'key': 'leukozyten', 'label': 'Leukozyten', 'unit': 'Tsd/µl', 'min': 4.0, 'max': 10.0, 'gruppe': 'Blutbild'},
    {'key': 'mch', 'label': 'MCH', 'unit': 'pg', 'min': 27.0, 'max': 33.0, 'gruppe': 'Blutbild'},
    {'key': 'mchc', 'label': 'MCHC', 'unit': 'g/dl', 'min': 32.0, 'max': 36.0, 'gruppe': 'Blutbild'},
    {'key': 'mcv', 'label': 'MCV', 'unit': 'fl', 'min': 80.0, 'max': 100.0, 'gruppe': 'Blutbild'},
    {'key': 'mpv', 'label': 'Mittleres Thrombozytenvolumen', 'unit': 'fl', 'min': 7.0, 'max': 12.0, 'gruppe': 'Blutbild'},
    {'key': 'retikulozyten', 'label': 'Retikulozyten', 'unit': '‰', 'min': 5.0, 'max': 15.0, 'gruppe': 'Blutbild'},
    {'key': 'thrombozyten', 'label': 'Thrombozyten', 'unit': 'Tsd/µl', 'min': 150.0, 'max': 400.0, 'gruppe': 'Blutbild'},
    // ── Differentialblutbild ──
    {'key': 'basophile_absolut', 'label': 'Basophile Granulozyten (absolut)', 'unit': 'Tsd/µl', 'min': 0.015, 'max': 0.05, 'gruppe': 'Differentialblutbild'},
    {'key': 'basophile_prozent', 'label': 'Basophile Granulozyten (relativ)', 'unit': '%', 'min': 0.0, 'max': 1.0, 'gruppe': 'Differentialblutbild'},
    {'key': 'eosinophile_absolut', 'label': 'Eosinophile Granulozyten (absolut)', 'unit': 'Tsd/µl', 'min': 0.05, 'max': 0.25, 'gruppe': 'Differentialblutbild'},
    {'key': 'eosinophile_prozent', 'label': 'Eosinophile Granulozyten (relativ)', 'unit': '%', 'min': 1.0, 'max': 3.0, 'gruppe': 'Differentialblutbild'},
    {'key': 'lymphozyten_absolut', 'label': 'Lymphozyten (absolut)', 'unit': 'Tsd/µl', 'min': 1.5, 'max': 3.0, 'gruppe': 'Differentialblutbild'},
    {'key': 'lymphozyten_prozent', 'label': 'Lymphozyten (relativ)', 'unit': '%', 'min': 25.0, 'max': 33.0, 'gruppe': 'Differentialblutbild'},
    {'key': 'monozyten_absolut', 'label': 'Monozyten (absolut)', 'unit': 'Tsd/µl', 'min': 0.28, 'max': 0.5, 'gruppe': 'Differentialblutbild'},
    {'key': 'monozyten_prozent', 'label': 'Monozyten (relativ)', 'unit': '%', 'min': 3.0, 'max': 7.0, 'gruppe': 'Differentialblutbild'},
    {'key': 'neutrophile_absolut', 'label': 'Neutrophile Granulozyten (absolut)', 'unit': 'Tsd/µl', 'min': 1.8, 'max': 7.0, 'gruppe': 'Differentialblutbild'},
    {'key': 'neutrophile_prozent', 'label': 'Neutrophile Granulozyten (relativ)', 'unit': '%', 'min': 40.0, 'max': 75.0, 'gruppe': 'Differentialblutbild'},
    {'key': 'segmentkernige', 'label': 'Segmentkernige neutrophile Granulozyten', 'unit': '%', 'min': 54.0, 'max': 62.0, 'gruppe': 'Differentialblutbild'},
    {'key': 'stabkernige', 'label': 'Stabkernige neutrophile Granulozyten', 'unit': '%', 'min': 3.0, 'max': 5.0, 'gruppe': 'Differentialblutbild'},
    // ── Entzündung ──
    {'key': 'bsg', 'label': 'Blutsenkungsgeschwindigkeit (1 h)', 'unit': 'mm/h', 'min': m ? 0.0 : 0.0, 'max': m ? 15.0 : 20.0, 'gruppe': 'Entzündung'},
    {'key': 'crp', 'label': 'C-reaktives Protein (CRP)', 'unit': 'mg/l', 'min': 0.0, 'max': 5.0, 'gruppe': 'Entzündung'},
    {'key': 'interleukin_6', 'label': 'Interleukin-6', 'unit': 'pg/ml', 'min': 0.0, 'max': 7.0, 'gruppe': 'Entzündung'},
    {'key': 'procalcitonin', 'label': 'Procalcitonin', 'unit': 'ng/ml', 'min': 0.0, 'max': 0.5, 'gruppe': 'Entzündung'},
    // ── Leberwerte ──
    {'key': 'alk_phosphatase', 'label': 'Alkalische Phosphatase', 'unit': 'U/l', 'min': 40.0, 'max': 130.0, 'gruppe': 'Leberwerte'},
    {'key': 'ammoniak', 'label': 'Ammoniak', 'unit': 'µg/dl', 'min': 19.0, 'max': 82.0, 'gruppe': 'Leberwerte'},
    {'key': 'bilirubin_direkt', 'label': 'Bilirubin direkt', 'unit': 'mg/dl', 'min': 0.0, 'max': 0.3, 'gruppe': 'Leberwerte'},
    {'key': 'bilirubin_gesamt', 'label': 'Bilirubin gesamt', 'unit': 'mg/dl', 'min': 0.0, 'max': 1.2, 'gruppe': 'Leberwerte'},
    {'key': 'bilirubin_indirekt', 'label': 'Bilirubin indirekt', 'unit': 'mg/dl', 'min': 0.0, 'max': 0.8, 'gruppe': 'Leberwerte'},
    {'key': 'che', 'label': 'Cholinesterase', 'unit': 'kU/l', 'min': m ? 5.3 : 4.3, 'max': m ? 12.9 : 11.3, 'gruppe': 'Leberwerte'},
    {'key': 'g_gt', 'label': 'Gamma-GT', 'unit': 'U/l', 'min': 0.0, 'max': m ? 60.0 : 40.0, 'gruppe': 'Leberwerte'},
    {'key': 'got', 'label': 'GOT (AST)', 'unit': 'U/l', 'min': 0.0, 'max': m ? 50.0 : 35.0, 'gruppe': 'Leberwerte'},
    {'key': 'gpt', 'label': 'GPT (ALT)', 'unit': 'U/l', 'min': 0.0, 'max': m ? 50.0 : 35.0, 'gruppe': 'Leberwerte'},
    {'key': 'ldh', 'label': 'Laktatdehydrogenase', 'unit': 'U/l', 'min': m ? 135.0 : 135.0, 'max': m ? 225.0 : 214.0, 'gruppe': 'Leberwerte'},
    // ── Nierenwerte ──
    {'key': 'ckd_epi', 'label': 'CKD-EPI Kreatinin (eGFR)', 'unit': 'ml/min', 'min': 90.0, 'max': 999.0, 'gruppe': 'Nierenwerte'},
    {'key': 'creatinin', 'label': 'Creatinin (Serum)', 'unit': 'mg/dl', 'min': m ? 0.7 : 0.5, 'max': m ? 1.2 : 0.9, 'gruppe': 'Nierenwerte'},
    {'key': 'cystatin_c', 'label': 'Cystatin C', 'unit': 'mg/l', 'min': 0.5, 'max': 1.0, 'gruppe': 'Nierenwerte'},
    {'key': 'harnstoff', 'label': 'Harnstoff', 'unit': 'mg/dl', 'min': 17.0, 'max': 43.0, 'gruppe': 'Nierenwerte'},
    {'key': 'harnsaeure', 'label': 'Harnsäure (Serum)', 'unit': 'mg/dl', 'min': m ? 3.4 : 2.4, 'max': m ? 7.0 : 5.7, 'gruppe': 'Nierenwerte'},
    // ── Elektrolyte ──
    {'key': 'calcium', 'label': 'Calcium (Serum)', 'unit': 'mmol/l', 'min': 2.2, 'max': 2.65, 'gruppe': 'Elektrolyte'},
    {'key': 'chlorid', 'label': 'Chlorid', 'unit': 'mmol/l', 'min': 95.0, 'max': 105.0, 'gruppe': 'Elektrolyte'},
    {'key': 'kalium', 'label': 'Kalium', 'unit': 'mmol/l', 'min': 3.5, 'max': 5.0, 'gruppe': 'Elektrolyte'},
    {'key': 'kupfer', 'label': 'Kupfer', 'unit': 'µg/dl', 'min': m ? 70.0 : 80.0, 'max': m ? 140.0 : 155.0, 'gruppe': 'Elektrolyte'},
    {'key': 'magnesium', 'label': 'Magnesium', 'unit': 'mmol/l', 'min': m ? 0.73 : 0.77, 'max': m ? 1.06 : 1.03, 'gruppe': 'Elektrolyte'},
    {'key': 'natrium', 'label': 'Natrium', 'unit': 'mmol/l', 'min': 136.0, 'max': 145.0, 'gruppe': 'Elektrolyte'},
    {'key': 'phosphat', 'label': 'Phosphat (anorganisch)', 'unit': 'mmol/l', 'min': 0.84, 'max': 1.45, 'gruppe': 'Elektrolyte'},
    {'key': 'selen', 'label': 'Selen', 'unit': 'µg/l', 'min': 60.0, 'max': 120.0, 'gruppe': 'Elektrolyte'},
    {'key': 'zink', 'label': 'Zink', 'unit': 'µg/dl', 'min': 70.0, 'max': 120.0, 'gruppe': 'Elektrolyte'},
    // ── Fettstoffwechsel ──
    {'key': 'apo_a1', 'label': 'Apolipoprotein A1', 'unit': 'mg/dl', 'min': m ? 110.0 : 125.0, 'max': m ? 205.0 : 215.0, 'gruppe': 'Fettstoffwechsel'},
    {'key': 'apo_b', 'label': 'Apolipoprotein B', 'unit': 'mg/dl', 'min': m ? 55.0 : 55.0, 'max': m ? 140.0 : 125.0, 'gruppe': 'Fettstoffwechsel'},
    {'key': 'cholesterin', 'label': 'Cholesterin gesamt', 'unit': 'mg/dl', 'min': 0.0, 'max': 200.0, 'gruppe': 'Fettstoffwechsel'},
    {'key': 'hdl_cholesterin', 'label': 'HDL-Cholesterin', 'unit': 'mg/dl', 'min': m ? 40.0 : 50.0, 'max': m ? 999.0 : 999.0, 'gruppe': 'Fettstoffwechsel'},
    {'key': 'ldl_cholesterin', 'label': 'LDL-Cholesterin', 'unit': 'mg/dl', 'min': 0.0, 'max': 130.0, 'gruppe': 'Fettstoffwechsel'},
    {'key': 'lipoprotein_a', 'label': 'Lipoprotein (a)', 'unit': 'mg/l', 'min': 0.0, 'max': 300.0, 'gruppe': 'Fettstoffwechsel'},
    {'key': 'non_hdl', 'label': 'Non-HDL-Cholesterin', 'unit': 'mg/dl', 'min': 0.0, 'max': 160.0, 'gruppe': 'Fettstoffwechsel'},
    {'key': 'triglyceride', 'label': 'Triglyceride', 'unit': 'mg/dl', 'min': 0.0, 'max': 150.0, 'gruppe': 'Fettstoffwechsel'},
    // ── Blutzucker ──
    {'key': 'c_peptid', 'label': 'C-Peptid', 'unit': 'ng/ml', 'min': 0.8, 'max': 4.0, 'gruppe': 'Blutzucker'},
    {'key': 'fructosamin', 'label': 'Fructosamin', 'unit': 'µmol/l', 'min': 205.0, 'max': 285.0, 'gruppe': 'Blutzucker'},
    {'key': 'glucose_nuechtern', 'label': 'Glucose nüchtern', 'unit': 'mg/dl', 'min': 70.0, 'max': 100.0, 'gruppe': 'Blutzucker'},
    {'key': 'hba1c_ifcc', 'label': 'HbA1c (IFCC)', 'unit': 'mmol/mol', 'min': 20.0, 'max': 39.0, 'gruppe': 'Blutzucker'},
    {'key': 'hba1c', 'label': 'HbA1c (Langzeit-Blutzucker)', 'unit': '%', 'min': 4.0, 'max': 5.7, 'gruppe': 'Blutzucker'},
    {'key': 'insulin', 'label': 'Insulin (nüchtern)', 'unit': 'µU/ml', 'min': 2.0, 'max': 25.0, 'gruppe': 'Blutzucker'},
    // ── Eisenstoffwechsel ──
    {'key': 'eisen', 'label': 'Eisen (Serum)', 'unit': 'µg/dl', 'min': m ? 35.0 : 23.0, 'max': m ? 168.0 : 134.0, 'gruppe': 'Eisenstoffwechsel'},
    {'key': 'ferritin', 'label': 'Ferritin', 'unit': 'ng/ml', 'min': m ? 30.0 : 15.0, 'max': m ? 400.0 : 150.0, 'gruppe': 'Eisenstoffwechsel'},
    {'key': 'haptoglobin', 'label': 'Haptoglobin', 'unit': 'mg/dl', 'min': 30.0, 'max': 200.0, 'gruppe': 'Eisenstoffwechsel'},
    {'key': 'loeslicher_transferrinrezeptor', 'label': 'Löslicher Transferrinrezeptor', 'unit': 'mg/l', 'min': 0.8, 'max': 1.8, 'gruppe': 'Eisenstoffwechsel'},
    {'key': 'transferrin', 'label': 'Transferrin', 'unit': 'g/l', 'min': 2.0, 'max': 3.6, 'gruppe': 'Eisenstoffwechsel'},
    {'key': 'transferrinsaettigung', 'label': 'Transferrinsättigung', 'unit': '%', 'min': 16.0, 'max': 45.0, 'gruppe': 'Eisenstoffwechsel'},
    // ── Vitamine ──
    {'key': 'folsaeure', 'label': 'Folsäure', 'unit': 'ng/ml', 'min': 3.0, 'max': 17.0, 'gruppe': 'Vitamine'},
    {'key': 'holo_transcobalamin', 'label': 'Holo-Transcobalamin (aktives B12)', 'unit': 'pmol/l', 'min': 50.0, 'max': 999.0, 'gruppe': 'Vitamine'},
    {'key': 'homocystein', 'label': 'Homocystein', 'unit': 'µmol/l', 'min': 5.0, 'max': 15.0, 'gruppe': 'Vitamine'},
    {'key': 'vitamin_a', 'label': 'Vitamin A (Retinol)', 'unit': 'µg/dl', 'min': 30.0, 'max': 80.0, 'gruppe': 'Vitamine'},
    {'key': 'vitamin_b1', 'label': 'Vitamin B1 (Thiamin)', 'unit': 'µg/l', 'min': 28.0, 'max': 85.0, 'gruppe': 'Vitamine'},
    {'key': 'vitamin_b12', 'label': 'Vitamin B12', 'unit': 'pg/ml', 'min': 200.0, 'max': 900.0, 'gruppe': 'Vitamine'},
    {'key': 'vitamin_b6', 'label': 'Vitamin B6 (Pyridoxin)', 'unit': 'µg/l', 'min': 3.6, 'max': 18.0, 'gruppe': 'Vitamine'},
    {'key': 'vitamin_c', 'label': 'Vitamin C (Ascorbinsäure)', 'unit': 'mg/dl', 'min': 0.4, 'max': 1.5, 'gruppe': 'Vitamine'},
    {'key': 'vitamin_d3', 'label': 'Vitamin D3 (25-OH)', 'unit': 'ng/ml', 'min': 30.0, 'max': 100.0, 'gruppe': 'Vitamine'},
    {'key': 'vitamin_e', 'label': 'Vitamin E (Tocopherol)', 'unit': 'mg/l', 'min': 5.0, 'max': 18.0, 'gruppe': 'Vitamine'},
    // ── Schilddrüse ──
    {'key': 'ft4', 'label': 'Freies Thyroxin', 'unit': 'ng/dl', 'min': 0.8, 'max': 1.8, 'gruppe': 'Schilddrüse'},
    {'key': 'ft3', 'label': 'Freies Trijodthyronin', 'unit': 'pg/ml', 'min': 2.0, 'max': 4.4, 'gruppe': 'Schilddrüse'},
    {'key': 'thyreoglobulin', 'label': 'Thyreoglobulin', 'unit': 'ng/ml', 'min': 1.4, 'max': 78.0, 'gruppe': 'Schilddrüse'},
    {'key': 'tg_ak', 'label': 'Thyreoglobulin-Antikörper', 'unit': 'IU/ml', 'min': 0.0, 'max': 115.0, 'gruppe': 'Schilddrüse'},
    {'key': 'tpo_ak', 'label': 'TPO-Antikörper', 'unit': 'IU/ml', 'min': 0.0, 'max': 34.0, 'gruppe': 'Schilddrüse'},
    {'key': 'tsh', 'label': 'TSH (Thyreotropin)', 'unit': 'mIU/l', 'min': 0.4, 'max': 4.0, 'gruppe': 'Schilddrüse'},
    {'key': 'trak', 'label': 'TSH-Rezeptor-Antikörper', 'unit': 'IU/l', 'min': 0.0, 'max': 1.75, 'gruppe': 'Schilddrüse'},
    // ── Hormone ──
    {'key': 'acth', 'label': 'ACTH', 'unit': 'pg/ml', 'min': 7.2, 'max': 63.3, 'gruppe': 'Hormone'},
    {'key': 'aldosteron', 'label': 'Aldosteron', 'unit': 'ng/l', 'min': 30.0, 'max': 160.0, 'gruppe': 'Hormone'},
    {'key': 'beta_hcg', 'label': 'Beta-HCG', 'unit': 'IU/l', 'min': m ? 0.0 : 0.0, 'max': m ? 2.0 : 5.0, 'gruppe': 'Hormone'},
    {'key': 'cortisol', 'label': 'Cortisol (morgens)', 'unit': 'µg/dl', 'min': 6.2, 'max': 19.4, 'gruppe': 'Hormone'},
    {'key': 'dhea_s', 'label': 'DHEA-Sulfat', 'unit': 'µg/dl', 'min': m ? 80.0 : 35.0, 'max': m ? 560.0 : 430.0, 'gruppe': 'Hormone'},
    {'key': 'estradiol', 'label': 'Estradiol', 'unit': 'pg/ml', 'min': 11.0, 'max': 44.0, 'gruppe': 'Hormone'},
    {'key': 'fsh', 'label': 'FSH (Follikelstimulierendes Hormon)', 'unit': 'IU/l', 'min': 1.0, 'max': 7.0, 'gruppe': 'Hormone'},
    {'key': 'igf_1', 'label': 'IGF-1 (Somatomedin C)', 'unit': 'ng/ml', 'min': 0.0, 'max': 0.0, 'gruppe': 'Hormone', 'qualitativ': true},
    {'key': 'lh', 'label': 'LH (Luteinisierendes Hormon)', 'unit': 'IU/l', 'min': 1.7, 'max': 8.6, 'gruppe': 'Hormone'},
    {'key': 'parathormon', 'label': 'Parathormon', 'unit': 'pg/ml', 'min': 15.0, 'max': 65.0, 'gruppe': 'Hormone'},
    {'key': 'progesteron', 'label': 'Progesteron', 'unit': 'ng/ml', 'min': 0.0, 'max': 0.15, 'gruppe': 'Hormone'},
    {'key': 'prolaktin', 'label': 'Prolaktin', 'unit': 'ng/ml', 'min': m ? 3.0 : 4.0, 'max': m ? 15.0 : 23.0, 'gruppe': 'Hormone'},
    {'key': 'renin', 'label': 'Renin', 'unit': 'µIU/ml', 'min': 4.4, 'max': 46.1, 'gruppe': 'Hormone'},
    {'key': 'shbg', 'label': 'SHBG (Sexualhormon-bindendes Globulin)', 'unit': 'nmol/l', 'min': m ? 18.0 : 32.0, 'max': m ? 54.0 : 128.0, 'gruppe': 'Hormone'},
    {'key': 'testosteron', 'label': 'Testosteron gesamt', 'unit': 'ng/ml', 'min': m ? 2.8 : 0.1, 'max': m ? 8.0 : 0.75, 'gruppe': 'Hormone'},
    // ── Gerinnung ──
    {'key': 'antithrombin', 'label': 'Antithrombin III', 'unit': '%', 'min': 80.0, 'max': 130.0, 'gruppe': 'Gerinnung'},
    {'key': 'd_dimere', 'label': 'D-Dimere', 'unit': 'mg/l FEU', 'min': 0.0, 'max': 0.5, 'gruppe': 'Gerinnung'},
    {'key': 'fibrinogen', 'label': 'Fibrinogen', 'unit': 'g/l', 'min': 1.8, 'max': 3.5, 'gruppe': 'Gerinnung'},
    {'key': 'inr', 'label': 'INR', 'unit': '', 'min': 0.85, 'max': 1.15, 'gruppe': 'Gerinnung'},
    {'key': 'ptt', 'label': 'Partielle Thromboplastinzeit', 'unit': 's', 'min': 26.0, 'max': 36.0, 'gruppe': 'Gerinnung'},
    {'key': 'quick', 'label': 'Quick-Wert (Thromboplastinzeit)', 'unit': '%', 'min': 70.0, 'max': 130.0, 'gruppe': 'Gerinnung'},
    {'key': 'thrombinzeit', 'label': 'Thrombinzeit', 'unit': 's', 'min': 16.0, 'max': 24.0, 'gruppe': 'Gerinnung'},
    // ── Herz & Muskel ──
    {'key': 'ck', 'label': 'Creatinkinase gesamt', 'unit': 'U/l', 'min': m ? 0.0 : 0.0, 'max': m ? 190.0 : 170.0, 'gruppe': 'Herz & Muskel'},
    {'key': 'ck_mb', 'label': 'Creatinkinase MB', 'unit': 'U/l', 'min': 0.0, 'max': 24.0, 'gruppe': 'Herz & Muskel'},
    {'key': 'myoglobin', 'label': 'Myoglobin', 'unit': 'ng/ml', 'min': m ? 28.0 : 25.0, 'max': m ? 72.0 : 58.0, 'gruppe': 'Herz & Muskel'},
    {'key': 'nt_pro_bnp', 'label': 'NT-proBNP', 'unit': 'pg/ml', 'min': 0.0, 'max': 125.0, 'gruppe': 'Herz & Muskel'},
    {'key': 'troponin', 'label': 'Troponin (hs)', 'unit': 'ng/l', 'min': 0.0, 'max': 14.0, 'gruppe': 'Herz & Muskel'},
    // ── Bauchspeicheldrüse ──
    {'key': 'amylase', 'label': 'Amylase (Pankreas)', 'unit': 'U/l', 'min': 13.0, 'max': 53.0, 'gruppe': 'Bauchspeicheldrüse'},
    {'key': 'lipase', 'label': 'Lipase', 'unit': 'U/l', 'min': 13.0, 'max': 60.0, 'gruppe': 'Bauchspeicheldrüse'},
    {'key': 'elastase_1', 'label': 'Pankreas-Elastase 1 (Stuhl)', 'unit': 'µg/g', 'min': 200.0, 'max': 999.0, 'gruppe': 'Bauchspeicheldrüse'},
    // ── Eiweiße & Immunglobuline ──
    {'key': 'albumin', 'label': 'Albumin', 'unit': 'g/l', 'min': 35.0, 'max': 53.0, 'gruppe': 'Eiweiße & Immunglobuline'},
    {'key': 'gesamteiweiss', 'label': 'Gesamteiweiß', 'unit': 'g/l', 'min': 66.0, 'max': 83.0, 'gruppe': 'Eiweiße & Immunglobuline'},
    {'key': 'iga', 'label': 'Immunglobulin A', 'unit': 'g/l', 'min': 0.7, 'max': 4.0, 'gruppe': 'Eiweiße & Immunglobuline'},
    {'key': 'ige_gesamt', 'label': 'Immunglobulin E gesamt', 'unit': 'IU/ml', 'min': 0.0, 'max': 100.0, 'gruppe': 'Eiweiße & Immunglobuline'},
    {'key': 'igg', 'label': 'Immunglobulin G', 'unit': 'g/l', 'min': 7.0, 'max': 16.0, 'gruppe': 'Eiweiße & Immunglobuline'},
    {'key': 'igm', 'label': 'Immunglobulin M', 'unit': 'g/l', 'min': 0.4, 'max': 2.3, 'gruppe': 'Eiweiße & Immunglobuline'},
    {'key': 'elektrophorese', 'label': 'Serum-Eiweiß-Elektrophorese', 'unit': '%', 'min': 0.0, 'max': 0.0, 'gruppe': 'Eiweiße & Immunglobuline', 'qualitativ': true},
    // ── Autoimmun & Rheuma ──
    {'key': 'anca', 'label': 'ANCA (c-/p-ANCA)', 'unit': 'Titer', 'min': 0.0, 'max': 0.0, 'gruppe': 'Autoimmun & Rheuma', 'qualitativ': true},
    {'key': 'ana', 'label': 'Antinukleäre Antikörper', 'unit': 'Titer', 'min': 0.0, 'max': 0.0, 'gruppe': 'Autoimmun & Rheuma', 'qualitativ': true},
    {'key': 'ccp_ak', 'label': 'CCP-Antikörper (Anti-CCP)', 'unit': 'U/ml', 'min': 0.0, 'max': 17.0, 'gruppe': 'Autoimmun & Rheuma'},
    {'key': 'hla_b27', 'label': 'HLA-B27', 'unit': '', 'min': 0.0, 'max': 0.0, 'gruppe': 'Autoimmun & Rheuma', 'qualitativ': true},
    {'key': 'rheumafaktor', 'label': 'Rheumafaktor', 'unit': 'IU/ml', 'min': 0.0, 'max': 20.0, 'gruppe': 'Autoimmun & Rheuma'},
    {'key': 'transglutaminase_ak', 'label': 'Transglutaminase-IgA (Zöliakie)', 'unit': 'U/ml', 'min': 0.0, 'max': 7.0, 'gruppe': 'Autoimmun & Rheuma'},
    // ── Knochenstoffwechsel ──
    {'key': 'beta_crosslaps', 'label': 'Beta-CrossLaps (CTX)', 'unit': 'ng/ml', 'min': m ? 0.1 : 0.1, 'max': m ? 0.6 : 0.57, 'gruppe': 'Knochenstoffwechsel'},
    {'key': 'knochen_ap', 'label': 'Knochenspezifische alkalische Phosphatase', 'unit': 'µg/l', 'min': m ? 3.7 : 2.9, 'max': m ? 20.9 : 14.5, 'gruppe': 'Knochenstoffwechsel'},
    {'key': 'osteocalcin', 'label': 'Osteocalcin', 'unit': 'ng/ml', 'min': m ? 14.0 : 11.0, 'max': m ? 42.0 : 43.0, 'gruppe': 'Knochenstoffwechsel'},
    // ── Blutgase ──
    {'key': 'base_excess', 'label': 'Basenüberschuss', 'unit': 'mmol/l', 'min': -2.0, 'max': 2.0, 'gruppe': 'Blutgase'},
    {'key': 'bikarbonat', 'label': 'Bikarbonat (Standard)', 'unit': 'mmol/l', 'min': 22.0, 'max': 26.0, 'gruppe': 'Blutgase'},
    {'key': 'pco2', 'label': 'Kohlendioxidpartialdruck', 'unit': 'mmHg', 'min': m ? 35.0 : 32.0, 'max': m ? 45.0 : 43.0, 'gruppe': 'Blutgase'},
    {'key': 'laktat', 'label': 'Laktat', 'unit': 'mmol/l', 'min': 0.5, 'max': 2.2, 'gruppe': 'Blutgase'},
    {'key': 'ph_wert', 'label': 'pH-Wert (Blutgas)', 'unit': '', 'min': 7.35, 'max': 7.45, 'gruppe': 'Blutgase'},
    {'key': 'po2', 'label': 'Sauerstoffpartialdruck', 'unit': 'mmHg', 'min': 75.0, 'max': 100.0, 'gruppe': 'Blutgase'},
    {'key': 'sauerstoffsaettigung', 'label': 'Sauerstoffsättigung', 'unit': '%', 'min': 94.0, 'max': 99.0, 'gruppe': 'Blutgase'},
    // ── Tumormarker ──
    {'key': 'afp', 'label': 'AFP (Alpha-1-Fetoprotein)', 'unit': 'ng/ml', 'min': 0.0, 'max': 7.0, 'gruppe': 'Tumormarker'},
    {'key': 'ca_125', 'label': 'CA 125', 'unit': 'U/ml', 'min': 0.0, 'max': 35.0, 'gruppe': 'Tumormarker'},
    {'key': 'ca_15_3', 'label': 'CA 15-3', 'unit': 'U/ml', 'min': 0.0, 'max': 25.0, 'gruppe': 'Tumormarker'},
    {'key': 'ca_19_9', 'label': 'CA 19-9', 'unit': 'U/ml', 'min': 0.0, 'max': 37.0, 'gruppe': 'Tumormarker'},
    {'key': 'calcitonin', 'label': 'Calcitonin', 'unit': 'pg/ml', 'min': m ? 2.0 : 2.0, 'max': m ? 48.0 : 10.0, 'gruppe': 'Tumormarker'},
    {'key': 'cea', 'label': 'CEA (Carcinoembryonales Antigen)', 'unit': 'ng/ml', 'min': 0.0, 'max': 5.0, 'gruppe': 'Tumormarker'},
    {'key': 'psa_frei', 'label': 'Freies PSA', 'unit': 'ng/ml', 'min': 0.0, 'max': 0.0, 'gruppe': 'Tumormarker', 'qualitativ': true},
    {'key': 'nse', 'label': 'NSE (Neuronenspezifische Enolase)', 'unit': 'ng/ml', 'min': 0.0, 'max': 17.0, 'gruppe': 'Tumormarker'},
    {'key': 'psa', 'label': 'PSA (Prostataspezifisches Antigen)', 'unit': 'ng/ml', 'min': 0.0, 'max': 4.0, 'gruppe': 'Tumormarker'},
    // ── Blutgruppe & Immunhämatologie ──
    {'key': 'antikoerpersuchtest', 'label': 'Antikörpersuchtest', 'unit': '', 'min': 0.0, 'max': 0.0, 'gruppe': 'Blutgruppe & Immunhämatologie', 'qualitativ': true},
    {'key': 'blutgruppe', 'label': 'Blutgruppe (AB0)', 'unit': '', 'min': 0.0, 'max': 0.0, 'gruppe': 'Blutgruppe & Immunhämatologie', 'qualitativ': true},
    {'key': 'rhesusfaktor', 'label': 'Rhesusfaktor (D)', 'unit': '', 'min': 0.0, 'max': 0.0, 'gruppe': 'Blutgruppe & Immunhämatologie', 'qualitativ': true},
    // ── Infektionen ──
    {'key': 'borrelien_igg', 'label': 'Borrelien IgG', 'unit': 'U/ml', 'min': 0.0, 'max': 0.0, 'gruppe': 'Infektionen', 'qualitativ': true},
    {'key': 'borrelien_igm', 'label': 'Borrelien IgM', 'unit': 'U/ml', 'min': 0.0, 'max': 0.0, 'gruppe': 'Infektionen', 'qualitativ': true},
    {'key': 'cmv_igg', 'label': 'CMV IgG', 'unit': 'U/ml', 'min': 0.0, 'max': 0.0, 'gruppe': 'Infektionen', 'qualitativ': true},
    {'key': 'ebv_vca_igg', 'label': 'EBV VCA IgG', 'unit': 'U/ml', 'min': 0.0, 'max': 0.0, 'gruppe': 'Infektionen', 'qualitativ': true},
    {'key': 'hepatitis_a_igg', 'label': 'Hepatitis A IgG (Anti-HAV IgG)', 'unit': 'S/CO', 'min': 1.0, 'max': 999.0, 'gruppe': 'Infektionen'},
    {'key': 'hepatitis_a_igm', 'label': 'Hepatitis A IgM (Anti-HAV IgM)', 'unit': 'S/CO', 'min': 0.0, 'max': 0.99, 'gruppe': 'Infektionen'},
    {'key': 'hepatitis_b_c_igg', 'label': 'Hepatitis B c IgG (Anti-HBc)', 'unit': 'S/CO', 'min': 0.0, 'max': 0.99, 'gruppe': 'Infektionen'},
    {'key': 'hepatitis_b_s_ag', 'label': 'Hepatitis B s Antigen (HBsAg)', 'unit': 'S/CO', 'min': 0.0, 'max': 0.99, 'gruppe': 'Infektionen'},
    {'key': 'hepatitis_b_s_ak', 'label': 'Hepatitis B s Antikörper (Anti-HBs)', 'unit': 'mIU/ml', 'min': 20.0, 'max': 999.0, 'gruppe': 'Infektionen'},
    {'key': 'hepatitis_c_ig', 'label': 'Hepatitis C Virus Ig (Anti-HCV)', 'unit': 'S/CO', 'min': 0.0, 'max': 0.99, 'gruppe': 'Infektionen'},
    {'key': 'hiv_screening', 'label': 'HIV 1/2 AK Screening', 'unit': 'S/CO', 'min': 0.0, 'max': 0.99, 'gruppe': 'Infektionen'},
    {'key': 'lues_tpha', 'label': 'Lues-Suchtest (TPHA/TPPA)', 'unit': 'Titer', 'min': 0.0, 'max': 0.0, 'gruppe': 'Infektionen', 'qualitativ': true},
    {'key': 'masern_igg', 'label': 'Masern IgG', 'unit': 'mIU/ml', 'min': 0.0, 'max': 0.0, 'gruppe': 'Infektionen', 'qualitativ': true},
    {'key': 'roeteln_igg', 'label': 'Röteln IgG', 'unit': 'IU/ml', 'min': 0.0, 'max': 0.0, 'gruppe': 'Infektionen', 'qualitativ': true},
    {'key': 'tetanus_igg', 'label': 'Tetanus-Antitoxin IgG', 'unit': 'IU/ml', 'min': 0.0, 'max': 0.0, 'gruppe': 'Infektionen', 'qualitativ': true},
    {'key': 'toxoplasmose_igg', 'label': 'Toxoplasmose IgG', 'unit': 'IU/ml', 'min': 0.0, 'max': 0.0, 'gruppe': 'Infektionen', 'qualitativ': true},
    {'key': 'varizellen_igg', 'label': 'Varizellen IgG', 'unit': 'mIU/ml', 'min': 0.0, 'max': 0.0, 'gruppe': 'Infektionen', 'qualitativ': true},
  ];
}