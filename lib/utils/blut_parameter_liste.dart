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
/// ⚠️ `such` traegt alles, wonach jemand suchen wuerde: Bezeichnung, Kurzform,
/// der Text in Klammern und die Gruppe. Ohne die Kurzformen findet „Ery" das
/// Feld „Erythrozyten" nicht — und genau so tippt man, wenn man ein Feld unter
/// 170 sucht.
///
/// [maennlich] steuert die geschlechtsabhaengigen Bereiche.
List<Map<String, dynamic>> blutParameterListe(bool maennlich) {
  final m = maennlich;
  // ignore: unnecessary_statements
  m;
  return [
    // ── Blutbild ──
    {'key': 'erythrozyten', 'label': 'Erythrozyten', 'unit': 'Mio/µl', 'min': m ? 4.3 : 3.8, 'max': m ? 5.9 : 5.2, 'gruppe': 'Blutbild', 'such': 'Ery Erys Erythrozyten Kleines Blutbild RBC'},
    {'key': 'rdw', 'label': 'Erythrozytenverteilungsbreite', 'unit': '%', 'min': 11.5, 'max': 14.5, 'gruppe': 'Blutbild', 'such': 'EVB Erythrozytenverteilungsbreite Kleines Blutbild RDW RDW-CV'},
    {'key': 'haematokrit', 'label': 'Hämatokrit', 'unit': '%', 'min': m ? 40.0 : 35.0, 'max': m ? 52.0 : 47.0, 'gruppe': 'Blutbild', 'such': 'HCT Hkt Hämatokrit Kleines Blutbild'},
    {'key': 'haemoglobin', 'label': 'Hämoglobin', 'unit': 'g/dl', 'min': m ? 13.5 : 12.0, 'max': m ? 17.5 : 16.0, 'gruppe': 'Blutbild', 'such': 'HGB Hb Hämoglobin Kleines Blutbild'},
    {'key': 'leukozyten', 'label': 'Leukozyten', 'unit': 'Tsd/µl', 'min': 4.0, 'max': 10.0, 'gruppe': 'Blutbild', 'such': 'Kleines Blutbild Leuko Leukos Leukozyten WBC'},
    {'key': 'mch', 'label': 'MCH', 'unit': 'pg', 'min': 27.0, 'max': 33.0, 'gruppe': 'Blutbild', 'such': 'HbE Kleines Blutbild MCH MCH (mittlerer Hämoglobingehalt) mittlerer Hämoglobingehalt'},
    {'key': 'mchc', 'label': 'MCHC', 'unit': 'g/dl', 'min': 32.0, 'max': 36.0, 'gruppe': 'Blutbild', 'such': 'Kleines Blutbild MCHC MCHC (mittlere Hämoglobinkonzentration) mittlere Hämoglobinkonzentration'},
    {'key': 'mcv', 'label': 'MCV', 'unit': 'fl', 'min': 80.0, 'max': 100.0, 'gruppe': 'Blutbild', 'such': 'Kleines Blutbild MCV MCV (mittleres Erythrozytenvolumen) mittleres Erythrozytenvolumen'},
    {'key': 'mpv', 'label': 'Mittleres Thrombozytenvolumen', 'unit': 'fl', 'min': 7.0, 'max': 12.0, 'gruppe': 'Blutbild', 'such': 'Kleines Blutbild MPV Mittleres Thrombozytenvolumen'},
    {'key': 'retikulozyten', 'label': 'Retikulozyten', 'unit': '‰', 'min': 5.0, 'max': 15.0, 'gruppe': 'Blutbild', 'such': 'Kleines Blutbild RET Retikulozyten Retis'},
    {'key': 'thrombozyten', 'label': 'Thrombozyten', 'unit': 'Tsd/µl', 'min': 150.0, 'max': 400.0, 'gruppe': 'Blutbild', 'such': 'Kleines Blutbild PLT Thrombo Thrombozyten'},
    // ── Differentialblutbild ──
    {'key': 'basophile_absolut', 'label': 'Basophile Granulozyten (absolut)', 'unit': 'Tsd/µl', 'min': 0.015, 'max': 0.05, 'gruppe': 'Differentialblutbild', 'such': 'Basophile Granulozyten Basophile Granulozyten (absolut) Differentialblutbild absolut'},
    {'key': 'basophile_prozent', 'label': 'Basophile Granulozyten (relativ)', 'unit': '%', 'min': 0.0, 'max': 1.0, 'gruppe': 'Differentialblutbild', 'such': 'BA Baso Basophile Granulozyten Basophile Granulozyten (relativ) Differentialblutbild relativ'},
    {'key': 'eosinophile_absolut', 'label': 'Eosinophile Granulozyten (absolut)', 'unit': 'Tsd/µl', 'min': 0.05, 'max': 0.25, 'gruppe': 'Differentialblutbild', 'such': 'Differentialblutbild Eosinophile Granulozyten Eosinophile Granulozyten (absolut) absolut'},
    {'key': 'eosinophile_prozent', 'label': 'Eosinophile Granulozyten (relativ)', 'unit': '%', 'min': 1.0, 'max': 3.0, 'gruppe': 'Differentialblutbild', 'such': 'Differentialblutbild EO Eos Eosinophile Granulozyten Eosinophile Granulozyten (relativ) relativ'},
    {'key': 'lymphozyten_absolut', 'label': 'Lymphozyten (absolut)', 'unit': 'Tsd/µl', 'min': 1.5, 'max': 3.0, 'gruppe': 'Differentialblutbild', 'such': 'Differentialblutbild Lymphozyten Lymphozyten (absolut) absolut'},
    {'key': 'lymphozyten_prozent', 'label': 'Lymphozyten (relativ)', 'unit': '%', 'min': 25.0, 'max': 33.0, 'gruppe': 'Differentialblutbild', 'such': 'Differentialblutbild LYM Lympho Lymphozyten Lymphozyten (relativ) relativ'},
    {'key': 'monozyten_absolut', 'label': 'Monozyten (absolut)', 'unit': 'Tsd/µl', 'min': 0.28, 'max': 0.5, 'gruppe': 'Differentialblutbild', 'such': 'Differentialblutbild Monozyten Monozyten (absolut) absolut'},
    {'key': 'monozyten_prozent', 'label': 'Monozyten (relativ)', 'unit': '%', 'min': 3.0, 'max': 7.0, 'gruppe': 'Differentialblutbild', 'such': 'Differentialblutbild MO Mono Monozyten Monozyten (relativ) relativ'},
    {'key': 'neutrophile_absolut', 'label': 'Neutrophile Granulozyten (absolut)', 'unit': 'Tsd/µl', 'min': 1.8, 'max': 7.0, 'gruppe': 'Differentialblutbild', 'such': 'ANC Differentialblutbild Neutrophile Granulozyten Neutrophile Granulozyten (absolut) absolut'},
    {'key': 'neutrophile_prozent', 'label': 'Neutrophile Granulozyten (relativ)', 'unit': '%', 'min': 40.0, 'max': 75.0, 'gruppe': 'Differentialblutbild', 'such': 'Differentialblutbild NEUT Neutro Neutrophile Granulozyten Neutrophile Granulozyten (relativ) relativ'},
    {'key': 'segmentkernige', 'label': 'Segmentkernige neutrophile Granulozyten', 'unit': '%', 'min': 54.0, 'max': 62.0, 'gruppe': 'Differentialblutbild', 'such': 'Differentialblutbild Segmentkernige neutrophile Granulozyten Segmk.'},
    {'key': 'stabkernige', 'label': 'Stabkernige neutrophile Granulozyten', 'unit': '%', 'min': 3.0, 'max': 5.0, 'gruppe': 'Differentialblutbild', 'such': 'Differentialblutbild Stabk. Stabkernige neutrophile Granulozyten'},
    // ── Entzündung ──
    {'key': 'bsg', 'label': 'Blutsenkungsgeschwindigkeit (1 h)', 'unit': 'mm/h', 'min': m ? 0.0 : 0.0, 'max': m ? 15.0 : 20.0, 'gruppe': 'Entzündung', 'such': '1 h BKS BSG Blutsenkungsgeschwindigkeit Blutsenkungsgeschwindigkeit (1 h) ESR Entzündungswerte'},
    {'key': 'crp', 'label': 'C-reaktives Protein (CRP)', 'unit': 'mg/l', 'min': 0.0, 'max': 5.0, 'gruppe': 'Entzündung', 'such': 'C-reaktives Protein CRP Entzündungswerte'},
    {'key': 'interleukin_6', 'label': 'Interleukin-6', 'unit': 'pg/ml', 'min': 0.0, 'max': 7.0, 'gruppe': 'Entzündung', 'such': 'Entzündungswerte IL-6 Interleukin-6'},
    {'key': 'procalcitonin', 'label': 'Procalcitonin', 'unit': 'ng/ml', 'min': 0.0, 'max': 0.5, 'gruppe': 'Entzündung', 'such': 'Entzündungswerte PCT Procalcitonin'},
    // ── Leberwerte ──
    {'key': 'alk_phosphatase', 'label': 'Alkalische Phosphatase', 'unit': 'U/l', 'min': 40.0, 'max': 130.0, 'gruppe': 'Leberwerte', 'such': 'ALP AP Alkalische Phosphatase Leberwerte'},
    {'key': 'ammoniak', 'label': 'Ammoniak', 'unit': 'µg/dl', 'min': 19.0, 'max': 82.0, 'gruppe': 'Leberwerte', 'such': 'Ammoniak Leberwerte NH3'},
    {'key': 'bilirubin_direkt', 'label': 'Bilirubin direkt', 'unit': 'mg/dl', 'min': 0.0, 'max': 0.3, 'gruppe': 'Leberwerte', 'such': 'Bili dir. Bilirubin direkt Bilirubin direkt (konjugiert) Leberwerte konjugiert'},
    {'key': 'bilirubin_gesamt', 'label': 'Bilirubin gesamt', 'unit': 'mg/dl', 'min': 0.0, 'max': 1.2, 'gruppe': 'Leberwerte', 'such': 'Bili ges. Bilirubin gesamt Leberwerte'},
    {'key': 'bilirubin_indirekt', 'label': 'Bilirubin indirekt', 'unit': 'mg/dl', 'min': 0.0, 'max': 0.8, 'gruppe': 'Leberwerte', 'such': 'Bili indir. Bilirubin indirekt Bilirubin indirekt (unkonjugiert) Leberwerte unkonjugiert'},
    {'key': 'che', 'label': 'Cholinesterase', 'unit': 'kU/l', 'min': m ? 5.3 : 4.3, 'max': m ? 12.9 : 11.3, 'gruppe': 'Leberwerte', 'such': 'CHE Cholinesterase Leberwerte PCHE'},
    {'key': 'g_gt', 'label': 'Gamma-GT', 'unit': 'U/l', 'min': 0.0, 'max': m ? 60.0 : 40.0, 'gruppe': 'Leberwerte', 'such': 'GGT Gamma-GT Leberwerte y-GT γ-GT'},
    {'key': 'gldh', 'label': 'GLDH (Glutamatdehydrogenase)', 'unit': 'U/l', 'min': m ? 0.0 : 0.0, 'max': m ? 7.0 : 5.0, 'gruppe': 'Leberwerte', 'such': 'GLDH GLDH (Glutamatdehydrogenase) Glutamatdehydrogenase Leberwerte'},
    {'key': 'got', 'label': 'GOT (AST)', 'unit': 'U/l', 'min': 0.0, 'max': m ? 50.0 : 35.0, 'gruppe': 'Leberwerte', 'such': 'ASAT AST GOT GOT (AST) Leberwerte'},
    {'key': 'gpt', 'label': 'GPT (ALT)', 'unit': 'U/l', 'min': 0.0, 'max': m ? 50.0 : 35.0, 'gruppe': 'Leberwerte', 'such': 'ALAT ALT GPT GPT (ALT) Leberwerte'},
    {'key': 'ldh', 'label': 'Laktatdehydrogenase', 'unit': 'U/l', 'min': m ? 135.0 : 135.0, 'max': m ? 225.0 : 214.0, 'gruppe': 'Leberwerte', 'such': 'LDH Laktatdehydrogenase Leberwerte'},
    // ── Nierenwerte ──
    {'key': 'ckd_epi', 'label': 'CKD-EPI Kreatinin (eGFR)', 'unit': 'ml/min', 'min': 90.0, 'max': 999.0, 'gruppe': 'Nierenwerte', 'such': 'CKD-EPI GFR Nierenwerte eGFR eGFR (CKD-EPI)'},
    {'key': 'creatinin', 'label': 'Creatinin (Serum)', 'unit': 'mg/dl', 'min': m ? 0.7 : 0.5, 'max': m ? 1.2 : 0.9, 'gruppe': 'Nierenwerte', 'such': 'Crea Krea Kreatinin Kreatinin (Serum) Nierenwerte Serum'},
    {'key': 'cystatin_c', 'label': 'Cystatin C', 'unit': 'mg/l', 'min': 0.5, 'max': 1.0, 'gruppe': 'Nierenwerte', 'such': 'CysC Cystatin C Nierenwerte'},
    {'key': 'harnstoff', 'label': 'Harnstoff', 'unit': 'mg/dl', 'min': 17.0, 'max': 43.0, 'gruppe': 'Nierenwerte', 'such': 'BUN Harnstoff Nierenwerte Urea'},
    {'key': 'harnsaeure', 'label': 'Harnsäure (Serum)', 'unit': 'mg/dl', 'min': m ? 3.4 : 2.4, 'max': m ? 7.0 : 5.7, 'gruppe': 'Nierenwerte', 'such': 'HS Harnsäure Harnsäure (Serum) Nierenwerte Serum Urat'},
    // ── Elektrolyte ──
    {'key': 'calcium', 'label': 'Calcium (Serum)', 'unit': 'mmol/l', 'min': 2.2, 'max': 2.65, 'gruppe': 'Elektrolyte', 'such': 'Ca Calcium Calcium (Serum) Elektrolyte & Mineralstoffe Serum'},
    {'key': 'chlorid', 'label': 'Chlorid', 'unit': 'mmol/l', 'min': 95.0, 'max': 105.0, 'gruppe': 'Elektrolyte', 'such': 'Chlorid Cl Elektrolyte & Mineralstoffe'},
    {'key': 'kalium', 'label': 'Kalium', 'unit': 'mmol/l', 'min': 3.5, 'max': 5.0, 'gruppe': 'Elektrolyte', 'such': 'Elektrolyte & Mineralstoffe K Kalium'},
    {'key': 'kupfer', 'label': 'Kupfer', 'unit': 'µg/dl', 'min': m ? 70.0 : 80.0, 'max': m ? 140.0 : 155.0, 'gruppe': 'Elektrolyte', 'such': 'Cu Elektrolyte & Mineralstoffe Kupfer'},
    {'key': 'magnesium', 'label': 'Magnesium', 'unit': 'mmol/l', 'min': m ? 0.73 : 0.77, 'max': m ? 1.06 : 1.03, 'gruppe': 'Elektrolyte', 'such': 'Elektrolyte & Mineralstoffe Magnesium Mg'},
    {'key': 'natrium', 'label': 'Natrium', 'unit': 'mmol/l', 'min': 136.0, 'max': 145.0, 'gruppe': 'Elektrolyte', 'such': 'Elektrolyte & Mineralstoffe Na Natrium'},
    {'key': 'osmolalitaet', 'label': 'Osmolalität (Serum)', 'unit': 'mosm/kg', 'min': 280.0, 'max': 300.0, 'gruppe': 'Elektrolyte', 'such': 'Elektrolyte & Mineralstoffe Osmo Osmolalität Osmolalität (Serum) Serum'},
    {'key': 'phosphat', 'label': 'Phosphat (anorganisch)', 'unit': 'mmol/l', 'min': 0.84, 'max': 1.45, 'gruppe': 'Elektrolyte', 'such': 'Elektrolyte & Mineralstoffe PHOS Phosphat Phosphat (anorganisch) Pi anorganisch'},
    {'key': 'selen', 'label': 'Selen', 'unit': 'µg/l', 'min': 60.0, 'max': 120.0, 'gruppe': 'Elektrolyte', 'such': 'Elektrolyte & Mineralstoffe Se Selen'},
    {'key': 'zink', 'label': 'Zink', 'unit': 'µg/dl', 'min': 70.0, 'max': 120.0, 'gruppe': 'Elektrolyte', 'such': 'Elektrolyte & Mineralstoffe Zink Zn'},
    // ── Fettstoffwechsel ──
    {'key': 'apo_a1', 'label': 'Apolipoprotein A1', 'unit': 'mg/dl', 'min': m ? 110.0 : 125.0, 'max': m ? 205.0 : 215.0, 'gruppe': 'Fettstoffwechsel', 'such': 'ApoA1 Apolipoprotein A1 Fettstoffwechsel'},
    {'key': 'apo_b', 'label': 'Apolipoprotein B', 'unit': 'mg/dl', 'min': m ? 55.0 : 55.0, 'max': m ? 140.0 : 125.0, 'gruppe': 'Fettstoffwechsel', 'such': 'ApoB Apolipoprotein B Fettstoffwechsel'},
    {'key': 'cholesterin', 'label': 'Cholesterin gesamt', 'unit': 'mg/dl', 'min': 0.0, 'max': 200.0, 'gruppe': 'Fettstoffwechsel', 'such': 'Chol Cholesterin gesamt Fettstoffwechsel'},
    {'key': 'hdl_cholesterin', 'label': 'HDL-Cholesterin', 'unit': 'mg/dl', 'min': m ? 40.0 : 50.0, 'max': m ? 999.0 : 999.0, 'gruppe': 'Fettstoffwechsel', 'such': 'Fettstoffwechsel HDL HDL-Cholesterin'},
    {'key': 'ldl_cholesterin', 'label': 'LDL-Cholesterin', 'unit': 'mg/dl', 'min': 0.0, 'max': 130.0, 'gruppe': 'Fettstoffwechsel', 'such': 'Fettstoffwechsel LDL LDL-Cholesterin'},
    {'key': 'lipoprotein_a', 'label': 'Lipoprotein (a)', 'unit': 'mg/l', 'min': 0.0, 'max': 300.0, 'gruppe': 'Fettstoffwechsel', 'such': 'Fettstoffwechsel LPA Lipoprotein Lipoprotein (a) Lp(a) a'},
    {'key': 'non_hdl', 'label': 'Non-HDL-Cholesterin', 'unit': 'mg/dl', 'min': 0.0, 'max': 160.0, 'gruppe': 'Fettstoffwechsel', 'such': 'Fettstoffwechsel Non-HDL Non-HDL-Cholesterin'},
    {'key': 'triglyceride', 'label': 'Triglyceride', 'unit': 'mg/dl', 'min': 0.0, 'max': 150.0, 'gruppe': 'Fettstoffwechsel', 'such': 'Fettstoffwechsel TG TRIG Triglyceride'},
    // ── Blutzucker ──
    {'key': 'c_peptid', 'label': 'C-Peptid', 'unit': 'ng/ml', 'min': 0.8, 'max': 4.0, 'gruppe': 'Blutzucker', 'such': 'C-Peptid CP Kohlenhydratstoffwechsel'},
    {'key': 'fructosamin', 'label': 'Fructosamin', 'unit': 'µmol/l', 'min': 205.0, 'max': 285.0, 'gruppe': 'Blutzucker', 'such': 'Fructosamin Kohlenhydratstoffwechsel'},
    {'key': 'glucose_nuechtern', 'label': 'Glucose nüchtern', 'unit': 'mg/dl', 'min': 70.0, 'max': 100.0, 'gruppe': 'Blutzucker', 'such': 'BZ Glu Glucose nüchtern Kohlenhydratstoffwechsel NBZ'},
    {'key': 'hba1c_ifcc', 'label': 'HbA1c (IFCC)', 'unit': 'mmol/mol', 'min': 20.0, 'max': 39.0, 'gruppe': 'Blutzucker', 'such': 'HbA1c HbA1c (IFCC) HbA1c IFCC IFCC Kohlenhydratstoffwechsel'},
    {'key': 'hba1c', 'label': 'HbA1c (Langzeit-Blutzucker)', 'unit': '%', 'min': 4.0, 'max': 5.7, 'gruppe': 'Blutzucker', 'such': 'HbA1c HbA1c (Langzeit-Blutzucker) Kohlenhydratstoffwechsel Langzeit-Blutzucker'},
    {'key': 'insulin', 'label': 'Insulin (nüchtern)', 'unit': 'µU/ml', 'min': 2.0, 'max': 25.0, 'gruppe': 'Blutzucker', 'such': 'INS Insulin Insulin (nüchtern) Kohlenhydratstoffwechsel nüchtern'},
    // ── Eisenstoffwechsel ──
    {'key': 'eisen', 'label': 'Eisen (Serum)', 'unit': 'µg/dl', 'min': m ? 35.0 : 23.0, 'max': m ? 168.0 : 134.0, 'gruppe': 'Eisenstoffwechsel', 'such': 'Eisen Eisen (Serum) Eisenstoffwechsel Fe Serum'},
    {'key': 'ferritin', 'label': 'Ferritin', 'unit': 'ng/ml', 'min': m ? 30.0 : 15.0, 'max': m ? 400.0 : 150.0, 'gruppe': 'Eisenstoffwechsel', 'such': 'Eisenstoffwechsel FERR Ferritin'},
    {'key': 'haptoglobin', 'label': 'Haptoglobin', 'unit': 'mg/dl', 'min': 30.0, 'max': 200.0, 'gruppe': 'Eisenstoffwechsel', 'such': 'Eisenstoffwechsel Haptoglobin Hp'},
    {'key': 'loeslicher_transferrinrezeptor', 'label': 'Löslicher Transferrinrezeptor', 'unit': 'mg/l', 'min': 0.8, 'max': 1.8, 'gruppe': 'Eisenstoffwechsel', 'such': 'Eisenstoffwechsel Löslicher Transferrinrezeptor sTfR'},
    {'key': 'transferrin', 'label': 'Transferrin', 'unit': 'g/l', 'min': 2.0, 'max': 3.6, 'gruppe': 'Eisenstoffwechsel', 'such': 'Eisenstoffwechsel TF Transferrin'},
    {'key': 'transferrinsaettigung', 'label': 'Transferrinsättigung', 'unit': '%', 'min': 16.0, 'max': 45.0, 'gruppe': 'Eisenstoffwechsel', 'such': 'Eisenstoffwechsel TSAT TfS Transferrinsättigung'},
    // ── Vitamine ──
    {'key': 'folsaeure', 'label': 'Folsäure', 'unit': 'ng/ml', 'min': 3.0, 'max': 17.0, 'gruppe': 'Vitamine', 'such': 'Folat Folsäure Folsäure (Vitamin B9) Vitamin B9 Vitamine'},
    {'key': 'holo_transcobalamin', 'label': 'Holo-Transcobalamin (aktives B12)', 'unit': 'pmol/l', 'min': 50.0, 'max': 999.0, 'gruppe': 'Vitamine', 'such': 'Holo-TC Holo-Transcobalamin Holo-Transcobalamin (aktives B12) Vitamine aktives B12'},
    {'key': 'homocystein', 'label': 'Homocystein', 'unit': 'µmol/l', 'min': 5.0, 'max': 15.0, 'gruppe': 'Vitamine', 'such': 'HCY Homocystein Vitamine'},
    {'key': 'vitamin_a', 'label': 'Vitamin A (Retinol)', 'unit': 'µg/dl', 'min': 30.0, 'max': 80.0, 'gruppe': 'Vitamine', 'such': 'Retinol Vitamin A Vitamin A (Retinol) Vitamine'},
    {'key': 'vitamin_b1', 'label': 'Vitamin B1 (Thiamin)', 'unit': 'µg/l', 'min': 28.0, 'max': 85.0, 'gruppe': 'Vitamine', 'such': 'B1 Thiamin Vitamin B1 Vitamin B1 (Thiamin) Vitamine'},
    {'key': 'vitamin_b12', 'label': 'Vitamin B12', 'unit': 'pg/ml', 'min': 200.0, 'max': 900.0, 'gruppe': 'Vitamine', 'such': 'B12 Cobalamin Vitamin B12 Vitamin B12 (Cobalamin) Vitamine'},
    {'key': 'vitamin_b6', 'label': 'Vitamin B6 (Pyridoxin)', 'unit': 'µg/l', 'min': 3.6, 'max': 18.0, 'gruppe': 'Vitamine', 'such': 'B6 Pyridoxin Vitamin B6 Vitamin B6 (Pyridoxin) Vitamine'},
    {'key': 'vitamin_c', 'label': 'Vitamin C (Ascorbinsäure)', 'unit': 'mg/dl', 'min': 0.4, 'max': 1.5, 'gruppe': 'Vitamine', 'such': 'Ascorbinsäure Vitamin C Vitamin C (Ascorbinsäure) Vitamine'},
    {'key': 'vitamin_d3', 'label': 'Vitamin D3 (25-OH)', 'unit': 'ng/ml', 'min': 30.0, 'max': 100.0, 'gruppe': 'Vitamine', 'such': '25-OH-D3 25-OH-Vitamin D Calcidiol Vitamin D3 Vitamin D3 (25-OH-Vitamin D) Vitamine'},
    {'key': 'vitamin_e', 'label': 'Vitamin E (Tocopherol)', 'unit': 'mg/l', 'min': 5.0, 'max': 18.0, 'gruppe': 'Vitamine', 'such': 'Tocopherol Vitamin E Vitamin E (Tocopherol) Vitamine'},
    // ── Schilddrüse ──
    {'key': 'ft4', 'label': 'Freies Thyroxin', 'unit': 'ng/dl', 'min': 0.8, 'max': 1.8, 'gruppe': 'Schilddrüse', 'such': 'Freies Thyroxin Schilddrüse fT4'},
    {'key': 'ft3', 'label': 'Freies Trijodthyronin', 'unit': 'pg/ml', 'min': 2.0, 'max': 4.4, 'gruppe': 'Schilddrüse', 'such': 'Freies Trijodthyronin Schilddrüse fT3'},
    {'key': 'thyreoglobulin', 'label': 'Thyreoglobulin', 'unit': 'ng/ml', 'min': 1.4, 'max': 78.0, 'gruppe': 'Schilddrüse', 'such': 'Schilddrüse Tg Thyreoglobulin'},
    {'key': 'tg_ak', 'label': 'Thyreoglobulin-Antikörper', 'unit': 'IU/ml', 'min': 0.0, 'max': 115.0, 'gruppe': 'Schilddrüse', 'such': 'Anti-Tg Schilddrüse TAK Thyreoglobulin-Antikörper'},
    {'key': 'tpo_ak', 'label': 'TPO-Antikörper', 'unit': 'IU/ml', 'min': 0.0, 'max': 34.0, 'gruppe': 'Schilddrüse', 'such': 'Anti-TPO MAK Schilddrüse TPO-Antikörper'},
    {'key': 'tsh', 'label': 'TSH (Thyreotropin)', 'unit': 'mIU/l', 'min': 0.4, 'max': 4.0, 'gruppe': 'Schilddrüse', 'such': 'Schilddrüse TSH TSH (Thyreotropin) Thyreotropin'},
    {'key': 'trak', 'label': 'TSH-Rezeptor-Antikörper', 'unit': 'IU/l', 'min': 0.0, 'max': 1.75, 'gruppe': 'Schilddrüse', 'such': 'Schilddrüse TRAK TSH-Rezeptor-Antikörper'},
    // ── Hormone ──
    {'key': 'acth', 'label': 'ACTH', 'unit': 'pg/ml', 'min': 7.2, 'max': 63.3, 'gruppe': 'Hormone', 'such': 'ACTH Hormone'},
    {'key': 'aldosteron', 'label': 'Aldosteron', 'unit': 'ng/l', 'min': 30.0, 'max': 160.0, 'gruppe': 'Hormone', 'such': 'Aldosteron Hormone'},
    {'key': 'androstendion', 'label': 'Androstendion', 'unit': 'µg/l', 'min': 0.0, 'max': 3.1, 'gruppe': 'Hormone', 'such': 'Androstendion Hormone'},
    {'key': 'beta_hcg', 'label': 'Beta-HCG', 'unit': 'IU/l', 'min': m ? 0.0 : 0.0, 'max': m ? 2.0 : 5.0, 'gruppe': 'Hormone', 'such': 'Beta-HCG Hormone ß-HCG'},
    {'key': 'cortisol', 'label': 'Cortisol (morgens)', 'unit': 'µg/dl', 'min': 6.2, 'max': 19.4, 'gruppe': 'Hormone', 'such': 'Cortisol Cortisol (morgens) Hormone morgens'},
    {'key': 'dhea_s', 'label': 'DHEA-Sulfat', 'unit': 'µg/dl', 'min': m ? 80.0 : 35.0, 'max': m ? 560.0 : 430.0, 'gruppe': 'Hormone', 'such': 'DHEA-S DHEA-Sulfat Hormone'},
    {'key': 'estradiol', 'label': 'Estradiol', 'unit': 'pg/ml', 'min': 11.0, 'max': 44.0, 'gruppe': 'Hormone', 'such': 'E2 Estradiol Hormone'},
    {'key': 'fsh', 'label': 'FSH (Follikelstimulierendes Hormon)', 'unit': 'IU/l', 'min': 1.0, 'max': 7.0, 'gruppe': 'Hormone', 'such': 'FSH FSH (Follikelstimulierendes Hormon) Follikelstimulierendes Hormon Hormone'},
    {'key': 'igf_1', 'label': 'IGF-1 (Somatomedin C)', 'unit': 'ng/ml', 'min': 0.0, 'max': 0.0, 'gruppe': 'Hormone', 'qualitativ': true, 'such': 'Hormone IGF-1 IGF-1 (Somatomedin C) Somatomedin C'},
    {'key': 'lh', 'label': 'LH (Luteinisierendes Hormon)', 'unit': 'IU/l', 'min': 1.7, 'max': 8.6, 'gruppe': 'Hormone', 'such': 'Hormone LH LH (Luteinisierendes Hormon) Luteinisierendes Hormon'},
    {'key': 'parathormon', 'label': 'Parathormon', 'unit': 'pg/ml', 'min': 15.0, 'max': 65.0, 'gruppe': 'Hormone', 'such': 'Hormone PTH Parathormon iPTH'},
    {'key': 'progesteron', 'label': 'Progesteron', 'unit': 'ng/ml', 'min': 0.0, 'max': 0.15, 'gruppe': 'Hormone', 'such': 'Hormone Progesteron'},
    {'key': 'prolaktin', 'label': 'Prolaktin', 'unit': 'ng/ml', 'min': m ? 3.0 : 4.0, 'max': m ? 15.0 : 23.0, 'gruppe': 'Hormone', 'such': 'Hormone PRL Prolaktin'},
    {'key': 'renin', 'label': 'Renin', 'unit': 'µIU/ml', 'min': 4.4, 'max': 46.1, 'gruppe': 'Hormone', 'such': 'Hormone Renin'},
    {'key': 'shbg', 'label': 'SHBG (Sexualhormon-bindendes Globulin)', 'unit': 'nmol/l', 'min': m ? 18.0 : 32.0, 'max': m ? 54.0 : 128.0, 'gruppe': 'Hormone', 'such': 'Hormone SHBG SHBG (Sexualhormon-bindendes Globulin) Sexualhormon-bindendes Globulin'},
    {'key': 'testosteron', 'label': 'Testosteron gesamt', 'unit': 'ng/ml', 'min': m ? 2.8 : 0.1, 'max': m ? 8.0 : 0.75, 'gruppe': 'Hormone', 'such': 'Hormone Testosteron gesamt'},
    // ── Gerinnung ──
    {'key': 'antithrombin', 'label': 'Antithrombin III', 'unit': '%', 'min': 80.0, 'max': 130.0, 'gruppe': 'Gerinnung', 'such': 'AT III Antithrombin III Gerinnung'},
    {'key': 'd_dimere', 'label': 'D-Dimere', 'unit': 'mg/l FEU', 'min': 0.0, 'max': 0.5, 'gruppe': 'Gerinnung', 'such': 'D-Dimer D-Dimere Gerinnung'},
    {'key': 'fibrinogen', 'label': 'Fibrinogen', 'unit': 'g/l', 'min': 1.8, 'max': 3.5, 'gruppe': 'Gerinnung', 'such': 'FBG Fibrinogen Gerinnung'},
    {'key': 'inr', 'label': 'INR', 'unit': '', 'min': 0.85, 'max': 1.15, 'gruppe': 'Gerinnung', 'such': 'Gerinnung INR'},
    {'key': 'ptt', 'label': 'Partielle Thromboplastinzeit', 'unit': 's', 'min': 26.0, 'max': 36.0, 'gruppe': 'Gerinnung', 'such': 'Gerinnung PTT Partielle Thromboplastinzeit aPTT'},
    {'key': 'quick', 'label': 'Quick-Wert (Thromboplastinzeit)', 'unit': '%', 'min': 70.0, 'max': 130.0, 'gruppe': 'Gerinnung', 'such': 'Gerinnung Quick Quick-Wert Quick-Wert (Thromboplastinzeit) TPZ Thromboplastinzeit'},
    {'key': 'thrombinzeit', 'label': 'Thrombinzeit', 'unit': 's', 'min': 16.0, 'max': 24.0, 'gruppe': 'Gerinnung', 'such': 'Gerinnung PTZ TZ Thrombinzeit'},
    // ── Herz & Muskel ──
    {'key': 'ck', 'label': 'Creatinkinase gesamt', 'unit': 'U/l', 'min': m ? 0.0 : 0.0, 'max': m ? 190.0 : 170.0, 'gruppe': 'Herz & Muskel', 'such': 'CK Creatinkinase gesamt Herz & Muskel'},
    {'key': 'ck_mb', 'label': 'Creatinkinase MB', 'unit': 'U/l', 'min': 0.0, 'max': 24.0, 'gruppe': 'Herz & Muskel', 'such': 'CK-MB Creatinkinase MB Herz & Muskel'},
    {'key': 'myoglobin', 'label': 'Myoglobin', 'unit': 'ng/ml', 'min': m ? 28.0 : 25.0, 'max': m ? 72.0 : 58.0, 'gruppe': 'Herz & Muskel', 'such': 'Herz & Muskel Myoglobin'},
    {'key': 'nt_pro_bnp', 'label': 'NT-proBNP', 'unit': 'pg/ml', 'min': 0.0, 'max': 125.0, 'gruppe': 'Herz & Muskel', 'such': 'Herz & Muskel NT-proBNP'},
    {'key': 'troponin', 'label': 'Troponin (hs)', 'unit': 'ng/l', 'min': 0.0, 'max': 14.0, 'gruppe': 'Herz & Muskel', 'such': 'Herz & Muskel Troponin Troponin (hs) hs hs-cTnI hs-cTnT'},
    // ── Bauchspeicheldrüse ──
    {'key': 'amylase', 'label': 'Amylase (Pankreas)', 'unit': 'U/l', 'min': 13.0, 'max': 53.0, 'gruppe': 'Bauchspeicheldrüse', 'such': 'AMY Amylase Amylase (Pankreas) Bauchspeicheldrüse P-AMY Pankreas'},
    {'key': 'lipase', 'label': 'Lipase', 'unit': 'U/l', 'min': 13.0, 'max': 60.0, 'gruppe': 'Bauchspeicheldrüse', 'such': 'Bauchspeicheldrüse LIP Lipase'},
    {'key': 'elastase_1', 'label': 'Pankreas-Elastase 1 (Stuhl)', 'unit': 'µg/g', 'min': 200.0, 'max': 999.0, 'gruppe': 'Bauchspeicheldrüse', 'such': 'Bauchspeicheldrüse Pankreas-Elastase 1 Pankreas-Elastase 1 (Stuhl) Stuhl'},
    // ── Eiweiße & Immunglobuline ──
    {'key': 'albumin', 'label': 'Albumin', 'unit': 'g/l', 'min': 35.0, 'max': 53.0, 'gruppe': 'Eiweiße & Immunglobuline', 'such': 'ALB Albumin Eiweiße & Immunglobuline'},
    {'key': 'gesamteiweiss', 'label': 'Gesamteiweiß', 'unit': 'g/l', 'min': 66.0, 'max': 83.0, 'gruppe': 'Eiweiße & Immunglobuline', 'such': 'EW Eiweiße & Immunglobuline Gesamteiweiß TP'},
    {'key': 'iga', 'label': 'Immunglobulin A', 'unit': 'g/l', 'min': 0.7, 'max': 4.0, 'gruppe': 'Eiweiße & Immunglobuline', 'such': 'Eiweiße & Immunglobuline IgA Immunglobulin A'},
    {'key': 'ige_gesamt', 'label': 'Immunglobulin E gesamt', 'unit': 'IU/ml', 'min': 0.0, 'max': 100.0, 'gruppe': 'Eiweiße & Immunglobuline', 'such': 'Eiweiße & Immunglobuline IgE Immunglobulin E gesamt'},
    {'key': 'igg', 'label': 'Immunglobulin G', 'unit': 'g/l', 'min': 7.0, 'max': 16.0, 'gruppe': 'Eiweiße & Immunglobuline', 'such': 'Eiweiße & Immunglobuline IgG Immunglobulin G'},
    {'key': 'igm', 'label': 'Immunglobulin M', 'unit': 'g/l', 'min': 0.4, 'max': 2.3, 'gruppe': 'Eiweiße & Immunglobuline', 'such': 'Eiweiße & Immunglobuline IgM Immunglobulin M'},
    {'key': 'elektrophorese', 'label': 'Serum-Eiweiß-Elektrophorese', 'unit': '%', 'min': 0.0, 'max': 0.0, 'gruppe': 'Eiweiße & Immunglobuline', 'qualitativ': true, 'such': 'Eiweiße & Immunglobuline SPE Serum-Eiweiß-Elektrophorese'},
    // ── Autoimmun & Rheuma ──
    {'key': 'anca', 'label': 'ANCA (c-/p-ANCA)', 'unit': 'Titer', 'min': 0.0, 'max': 0.0, 'gruppe': 'Autoimmun & Rheuma', 'qualitativ': true, 'such': 'ANCA ANCA (c-/p-ANCA) Autoimmun & Rheuma c- p-ANCA'},
    {'key': 'ana', 'label': 'Antinukleäre Antikörper', 'unit': 'Titer', 'min': 0.0, 'max': 0.0, 'gruppe': 'Autoimmun & Rheuma', 'qualitativ': true, 'such': 'ANA Antinukleäre Antikörper Autoimmun & Rheuma'},
    {'key': 'ccp_ak', 'label': 'CCP-Antikörper (Anti-CCP)', 'unit': 'U/ml', 'min': 0.0, 'max': 17.0, 'gruppe': 'Autoimmun & Rheuma', 'such': 'ACPA Anti-CCP Autoimmun & Rheuma CCP-Antikörper CCP-Antikörper (Anti-CCP)'},
    {'key': 'hla_b27', 'label': 'HLA-B27', 'unit': '', 'min': 0.0, 'max': 0.0, 'gruppe': 'Autoimmun & Rheuma', 'qualitativ': true, 'such': 'Autoimmun & Rheuma HLA-B27'},
    {'key': 'rheumafaktor', 'label': 'Rheumafaktor', 'unit': 'IU/ml', 'min': 0.0, 'max': 20.0, 'gruppe': 'Autoimmun & Rheuma', 'such': 'Autoimmun & Rheuma RF Rheumafaktor'},
    {'key': 'transglutaminase_ak', 'label': 'Transglutaminase-IgA (Zöliakie)', 'unit': 'U/ml', 'min': 0.0, 'max': 7.0, 'gruppe': 'Autoimmun & Rheuma', 'such': 'Autoimmun & Rheuma Transglutaminase-IgA Transglutaminase-IgA (Zöliakie) Zöliakie tTG-IgA'},
    // ── Knochenstoffwechsel ──
    {'key': 'beta_crosslaps', 'label': 'Beta-CrossLaps (CTX)', 'unit': 'ng/ml', 'min': m ? 0.1 : 0.1, 'max': m ? 0.6 : 0.57, 'gruppe': 'Knochenstoffwechsel', 'such': 'Beta-CrossLaps Beta-CrossLaps (CTX) CTX Knochenstoffwechsel ß-CTX'},
    {'key': 'knochen_ap', 'label': 'Knochenspezifische alkalische Phosphatase', 'unit': 'µg/l', 'min': m ? 3.7 : 2.9, 'max': m ? 20.9 : 14.5, 'gruppe': 'Knochenstoffwechsel', 'such': 'BAP Knochenspezifische alkalische Phosphatase Knochenstoffwechsel Ostase'},
    {'key': 'osteocalcin', 'label': 'Osteocalcin', 'unit': 'ng/ml', 'min': m ? 14.0 : 11.0, 'max': m ? 42.0 : 43.0, 'gruppe': 'Knochenstoffwechsel', 'such': 'Knochenstoffwechsel OC Osteocalcin'},
    // ── Blutgase ──
    {'key': 'base_excess', 'label': 'Basenüberschuss', 'unit': 'mmol/l', 'min': -2.0, 'max': 2.0, 'gruppe': 'Blutgase', 'such': 'BE Basenüberschuss Blutgase'},
    {'key': 'bikarbonat', 'label': 'Bikarbonat (Standard)', 'unit': 'mmol/l', 'min': 22.0, 'max': 26.0, 'gruppe': 'Blutgase', 'such': 'Bikarbonat Bikarbonat (Standard) Blutgase HCO3- Standard'},
    {'key': 'pco2', 'label': 'Kohlendioxidpartialdruck', 'unit': 'mmHg', 'min': m ? 35.0 : 32.0, 'max': m ? 45.0 : 43.0, 'gruppe': 'Blutgase', 'such': 'Blutgase Kohlendioxidpartialdruck pCO2'},
    {'key': 'laktat', 'label': 'Laktat', 'unit': 'mmol/l', 'min': 0.5, 'max': 2.2, 'gruppe': 'Blutgase', 'such': 'Blutgase LAC Laktat'},
    {'key': 'ph_wert', 'label': 'pH-Wert (Blutgas)', 'unit': '', 'min': 7.35, 'max': 7.45, 'gruppe': 'Blutgase', 'such': 'Blutgas Blutgase pH pH-Wert pH-Wert (Blutgas)'},
    {'key': 'po2', 'label': 'Sauerstoffpartialdruck', 'unit': 'mmHg', 'min': 75.0, 'max': 100.0, 'gruppe': 'Blutgase', 'such': 'Blutgase Sauerstoffpartialdruck pO2'},
    {'key': 'sauerstoffsaettigung', 'label': 'Sauerstoffsättigung', 'unit': '%', 'min': 94.0, 'max': 99.0, 'gruppe': 'Blutgase', 'such': 'Blutgase Sauerstoffsättigung SpO2 sO2'},
    // ── Tumormarker ──
    {'key': 'afp', 'label': 'AFP (Alpha-1-Fetoprotein)', 'unit': 'ng/ml', 'min': 0.0, 'max': 7.0, 'gruppe': 'Tumormarker', 'such': 'AFP AFP (Alpha-1-Fetoprotein) Alpha-1-Fetoprotein Tumormarker'},
    {'key': 'ca_125', 'label': 'CA 125', 'unit': 'U/ml', 'min': 0.0, 'max': 35.0, 'gruppe': 'Tumormarker', 'such': 'CA 125 CA125 Tumormarker'},
    {'key': 'ca_15_3', 'label': 'CA 15-3', 'unit': 'U/ml', 'min': 0.0, 'max': 25.0, 'gruppe': 'Tumormarker', 'such': 'CA 15-3 CA15-3 Tumormarker'},
    {'key': 'ca_19_9', 'label': 'CA 19-9', 'unit': 'U/ml', 'min': 0.0, 'max': 37.0, 'gruppe': 'Tumormarker', 'such': 'CA 19-9 CA19-9 Tumormarker'},
    {'key': 'calcitonin', 'label': 'Calcitonin', 'unit': 'pg/ml', 'min': m ? 2.0 : 2.0, 'max': m ? 48.0 : 10.0, 'gruppe': 'Tumormarker', 'such': 'CT Calcitonin Tumormarker'},
    {'key': 'cea', 'label': 'CEA (Carcinoembryonales Antigen)', 'unit': 'ng/ml', 'min': 0.0, 'max': 5.0, 'gruppe': 'Tumormarker', 'such': 'CEA CEA (Carcinoembryonales Antigen) Carcinoembryonales Antigen Tumormarker'},
    {'key': 'psa_frei', 'label': 'Freies PSA', 'unit': 'ng/ml', 'min': 0.0, 'max': 0.0, 'gruppe': 'Tumormarker', 'qualitativ': true, 'such': 'Freies PSA Tumormarker fPSA'},
    {'key': 'nse', 'label': 'NSE (Neuronenspezifische Enolase)', 'unit': 'ng/ml', 'min': 0.0, 'max': 17.0, 'gruppe': 'Tumormarker', 'such': 'NSE NSE (Neuronenspezifische Enolase) Neuronenspezifische Enolase Tumormarker'},
    {'key': 'psa', 'label': 'PSA (Prostataspezifisches Antigen)', 'unit': 'ng/ml', 'min': 0.0, 'max': 4.0, 'gruppe': 'Tumormarker', 'such': 'PSA PSA (Prostataspezifisches Antigen) Prostataspezifisches Antigen Tumormarker'},
    // ── Medikamentenspiegel ──
    {'key': 'med_amiodaron', 'label': 'Amiodaron', 'unit': 'mg/l', 'min': 0.7, 'max': 2.0, 'gruppe': 'Medikamentenspiegel', 'such': 'Amiodaron Medikamentenspiegel'},
    {'key': 'med_digitoxin', 'label': 'Digitoxin', 'unit': 'µg/l', 'min': 10.0, 'max': 30.0, 'gruppe': 'Medikamentenspiegel', 'such': 'Digitoxin Medikamentenspiegel'},
    {'key': 'med_digoxin', 'label': 'Digoxin', 'unit': 'µg/l', 'min': 0.8, 'max': 2.0, 'gruppe': 'Medikamentenspiegel', 'such': 'Digoxin Medikamentenspiegel'},
    {'key': 'med_lithium', 'label': 'Lithium', 'unit': 'mmol/l', 'min': 0.4, 'max': 1.3, 'gruppe': 'Medikamentenspiegel', 'such': 'Li Lithium Medikamentenspiegel'},
    {'key': 'med_theophyllin', 'label': 'Theophyllin', 'unit': 'mg/l', 'min': 8.0, 'max': 20.0, 'gruppe': 'Medikamentenspiegel', 'such': 'Medikamentenspiegel Theophyllin'},
    {'key': 'med_vancomycin', 'label': 'Vancomycin', 'unit': 'µg/ml', 'min': 5.0, 'max': 40.0, 'gruppe': 'Medikamentenspiegel', 'such': 'Medikamentenspiegel Vanco Vancomycin'},
    // ── Urin ──
    {'key': 'urin_menge', 'label': '24-h-Sammelmenge', 'unit': 'ml/d', 'min': 800.0, 'max': 2200.0, 'gruppe': 'Urin', 'such': '24-h-Sammelmenge 24h SU Sammelurin Urin'},
    {'key': 'urin_albumin', 'label': 'Albumin im Urin', 'unit': 'mg/l', 'min': 0.0, 'max': 30.0, 'gruppe': 'Urin', 'such': 'Albumin im Urin Albuminurie Mikroalbumin Urin'},
    {'key': 'urin_albumin_krea', 'label': 'Albumin-Kreatinin-Quotient (Urin)', 'unit': 'mg/g Krea', 'min': 0.0, 'max': 30.0, 'gruppe': 'Urin', 'such': 'ACR Albumin-Kreatinin-Quotient Albumin-Kreatinin-Quotient (Urin) Albumin/Krea Urin'},
    {'key': 'urin_amylase', 'label': 'Amylase im Urin', 'unit': 'U/l', 'min': 0.0, 'max': 460.0, 'gruppe': 'Urin', 'such': 'Amylase U Amylase im Urin Urin'},
    {'key': 'urin_bilirubin', 'label': 'Bilirubin (Urin)', 'unit': '', 'min': 0.0, 'max': 0.0, 'gruppe': 'Urin', 'qualitativ': true, 'such': 'Bili U Bilirubin Bilirubin (Urin) Urin'},
    {'key': 'urin_calcium', 'label': 'Calcium im Urin', 'unit': 'mg/l', 'min': m ? 0.0 : 0.0, 'max': m ? 224.0 : 184.0, 'gruppe': 'Urin', 'such': 'Ca U Calcium im Urin Urin'},
    {'key': 'urin_chlorid', 'label': 'Chlorid im Urin', 'unit': 'mmol/l', 'min': 54.0, 'max': 158.0, 'gruppe': 'Urin', 'such': 'Chlorid im Urin Cl U Urin'},
    {'key': 'urin_erythrozyten', 'label': 'Erythrozyten im Urin', 'unit': 'Mpt/l', 'min': 0.0, 'max': 6.0, 'gruppe': 'Urin', 'such': 'Ery U Erythrozyten im Urin Hämaturie Urin'},
    {'key': 'urin_eiweiss', 'label': 'Gesamteiweiß im Urin', 'unit': 'mg/l', 'min': 23.0, 'max': 100.0, 'gruppe': 'Urin', 'such': 'Gesamteiweiß im Urin Protein U Proteinurie Urin'},
    {'key': 'urin_glucose', 'label': 'Glukose im Urin', 'unit': 'mg/dl', 'min': 1.8, 'max': 16.6, 'gruppe': 'Urin', 'such': 'Glukose im Urin Glukosurie Urin'},
    {'key': 'urin_harnstoff', 'label': 'Harnstoff im Urin', 'unit': 'g/l', 'min': 15.0, 'max': 26.0, 'gruppe': 'Urin', 'such': 'Harnstoff im Urin Urea U Urin'},
    {'key': 'urin_harnsaeure', 'label': 'Harnsäure im Urin', 'unit': 'mg/l', 'min': m ? 219.0 : 180.0, 'max': m ? 593.0 : 593.0, 'gruppe': 'Urin', 'such': 'HS U Harnsäure im Urin Urin'},
    {'key': 'urin_kalium', 'label': 'Kalium im Urin', 'unit': 'mmol/l', 'min': 25.0, 'max': 93.0, 'gruppe': 'Urin', 'such': 'K U Kalium im Urin Urin'},
    {'key': 'urin_keton', 'label': 'Ketone / Aceton (Urin)', 'unit': '', 'min': 0.0, 'max': 0.0, 'gruppe': 'Urin', 'qualitativ': true, 'such': 'Aceton Ketone / Aceton Ketone / Aceton (Urin) Ketonkörper Urin'},
    {'key': 'urin_creatinin', 'label': 'Kreatinin im Urin', 'unit': 'g/l', 'min': m ? 0.58 : 0.44, 'max': m ? 1.61 : 1.06, 'gruppe': 'Urin', 'such': 'Krea U Kreatinin im Urin Urin'},
    {'key': 'urin_leukozyten', 'label': 'Leukozyten im Urin', 'unit': 'Mpt/l', 'min': 0.0, 'max': 6.0, 'gruppe': 'Urin', 'such': 'Leuko U Leukozyten im Urin Leukozyturie Urin'},
    {'key': 'urin_natrium', 'label': 'Natrium im Urin', 'unit': 'mmol/l', 'min': 64.0, 'max': 172.0, 'gruppe': 'Urin', 'such': 'Na U Natrium im Urin Urin'},
    {'key': 'urin_nitrit', 'label': 'Nitrit (Urin)', 'unit': '', 'min': 0.0, 'max': 0.0, 'gruppe': 'Urin', 'qualitativ': true, 'such': 'Nitrit Nitrit (Urin) Urin'},
    {'key': 'urin_ph', 'label': 'pH-Wert (Urin)', 'unit': '', 'min': 6.0, 'max': 7.0, 'gruppe': 'Urin', 'such': 'Urin pH U pH-Wert pH-Wert (Urin)'},
    {'key': 'urin_phosphat', 'label': 'Phosphat im Urin', 'unit': 'mg/dl', 'min': 46.0, 'max': 115.0, 'gruppe': 'Urin', 'such': 'PO4 U Phosphat im Urin Urin'},
    {'key': 'urin_spez_gewicht', 'label': 'Spezifisches Gewicht (Urin)', 'unit': 'g/l', 'min': 1.022, 'max': 1.035, 'gruppe': 'Urin', 'such': 'Dichte U Spezifisches Gewicht Spezifisches Gewicht (Urin) Urin'},
    {'key': 'urin_urobilinogen', 'label': 'Urobilinogen (Urin)', 'unit': '', 'min': 0.0, 'max': 0.0, 'gruppe': 'Urin', 'qualitativ': true, 'such': 'Urin Urobilinogen Urobilinogen (Urin)'},
    // ── Blutgruppe & Immunhämatologie ──
    {'key': 'antikoerpersuchtest', 'label': 'Antikörpersuchtest', 'unit': '', 'min': 0.0, 'max': 0.0, 'gruppe': 'Blutgruppe & Immunhämatologie', 'qualitativ': true, 'such': 'AKS Antikörpersuchtest Blutgruppe & Immunhämatologie Coombs'},
    {'key': 'blutgruppe', 'label': 'Blutgruppe (AB0)', 'unit': '', 'min': 0.0, 'max': 0.0, 'gruppe': 'Blutgruppe & Immunhämatologie', 'qualitativ': true, 'such': 'AB0 Blutgruppe Blutgruppe & Immunhämatologie Blutgruppe (AB0)'},
    {'key': 'rhesusfaktor', 'label': 'Rhesusfaktor (D)', 'unit': '', 'min': 0.0, 'max': 0.0, 'gruppe': 'Blutgruppe & Immunhämatologie', 'qualitativ': true, 'such': 'Blutgruppe & Immunhämatologie D Rh RhD Rhesusfaktor Rhesusfaktor (D)'},
    // ── Infektionen ──
    {'key': 'borrelien_igg', 'label': 'Borrelien IgG', 'unit': 'U/ml', 'min': 0.0, 'max': 0.0, 'gruppe': 'Infektionen', 'qualitativ': true, 'such': 'Borrelien IgG Infektionsserologie'},
    {'key': 'borrelien_igm', 'label': 'Borrelien IgM', 'unit': 'U/ml', 'min': 0.0, 'max': 0.0, 'gruppe': 'Infektionen', 'qualitativ': true, 'such': 'Borrelien IgM Infektionsserologie'},
    {'key': 'cmv_igg', 'label': 'CMV IgG', 'unit': 'U/ml', 'min': 0.0, 'max': 0.0, 'gruppe': 'Infektionen', 'qualitativ': true, 'such': 'CMV CMV IgG Infektionsserologie'},
    {'key': 'ebv_vca_igg', 'label': 'EBV VCA IgG', 'unit': 'U/ml', 'min': 0.0, 'max': 0.0, 'gruppe': 'Infektionen', 'qualitativ': true, 'such': 'EBV EBV VCA IgG Infektionsserologie'},
    {'key': 'hepatitis_a_igg', 'label': 'Hepatitis A IgG (Anti-HAV IgG)', 'unit': 'S/CO', 'min': 1.0, 'max': 999.0, 'gruppe': 'Infektionen', 'such': 'Anti-HAV IgG Hepatitis A IgG Hepatitis A IgG (Anti-HAV IgG) Infektionsserologie'},
    {'key': 'hepatitis_a_igm', 'label': 'Hepatitis A IgM (Anti-HAV IgM)', 'unit': 'S/CO', 'min': 0.0, 'max': 0.99, 'gruppe': 'Infektionen', 'such': 'Anti-HAV IgM Hepatitis A IgM Hepatitis A IgM (Anti-HAV IgM) Infektionsserologie'},
    {'key': 'hepatitis_b_c_igg', 'label': 'Hepatitis B c IgG (Anti-HBc)', 'unit': 'S/CO', 'min': 0.0, 'max': 0.99, 'gruppe': 'Infektionen', 'such': 'Anti-HBc Hepatitis B core Hepatitis B core (Anti-HBc) Infektionsserologie'},
    {'key': 'hepatitis_b_s_ag', 'label': 'Hepatitis B s Antigen (HBsAg)', 'unit': 'S/CO', 'min': 0.0, 'max': 0.99, 'gruppe': 'Infektionen', 'such': 'HBsAg Hepatitis B s Antigen Hepatitis B s Antigen (HBsAg) Infektionsserologie'},
    {'key': 'hepatitis_b_s_ak', 'label': 'Hepatitis B s Antikörper (Anti-HBs)', 'unit': 'mIU/ml', 'min': 20.0, 'max': 999.0, 'gruppe': 'Infektionen', 'such': 'Anti-HBs Hepatitis B s Antikörper Hepatitis B s Antikörper (Anti-HBs) Infektionsserologie'},
    {'key': 'hepatitis_c_ig', 'label': 'Hepatitis C Virus Ig (Anti-HCV)', 'unit': 'S/CO', 'min': 0.0, 'max': 0.99, 'gruppe': 'Infektionen', 'such': 'Anti-HCV Hepatitis C Antikörper Hepatitis C Antikörper (Anti-HCV) Infektionsserologie'},
    {'key': 'hiv_screening', 'label': 'HIV 1/2 AK Screening', 'unit': 'S/CO', 'min': 0.0, 'max': 0.99, 'gruppe': 'Infektionen', 'such': 'HIV HIV 1/2 Ag/Ak Screening Infektionsserologie'},
    {'key': 'lues_tpha', 'label': 'Lues-Suchtest (TPHA/TPPA)', 'unit': 'Titer', 'min': 0.0, 'max': 0.0, 'gruppe': 'Infektionen', 'qualitativ': true, 'such': 'Infektionsserologie Lues-Suchtest Lues-Suchtest (TPHA/TPPA) TPHA TPPA'},
    {'key': 'masern_igg', 'label': 'Masern IgG', 'unit': 'mIU/ml', 'min': 0.0, 'max': 0.0, 'gruppe': 'Infektionen', 'qualitativ': true, 'such': 'Infektionsserologie Masern IgG'},
    {'key': 'roeteln_igg', 'label': 'Röteln IgG', 'unit': 'IU/ml', 'min': 0.0, 'max': 0.0, 'gruppe': 'Infektionen', 'qualitativ': true, 'such': 'Infektionsserologie Röteln IgG'},
    {'key': 'tetanus_igg', 'label': 'Tetanus-Antitoxin IgG', 'unit': 'IU/ml', 'min': 0.0, 'max': 0.0, 'gruppe': 'Infektionen', 'qualitativ': true, 'such': 'Infektionsserologie Tetanus-Antitoxin IgG'},
    {'key': 'toxoplasmose_igg', 'label': 'Toxoplasmose IgG', 'unit': 'IU/ml', 'min': 0.0, 'max': 0.0, 'gruppe': 'Infektionen', 'qualitativ': true, 'such': 'Infektionsserologie Toxoplasmose IgG'},
    {'key': 'varizellen_igg', 'label': 'Varizellen IgG', 'unit': 'mIU/ml', 'min': 0.0, 'max': 0.0, 'gruppe': 'Infektionen', 'qualitativ': true, 'such': 'Infektionsserologie VZV Varizellen IgG'},
  ];
}
