/// Was ein Laborwert misst — und was eine Abweichung bedeuten KANN.
///
/// ⚠️ Das ist KEINE Diagnose. Jeder Text sagt, was der Parameter misst und
/// welche Ursachen für eine Abweichung in Frage kommen; er sagt nicht, was
/// beim einzelnen Menschen vorliegt. Maßgeblich bleiben der Befund des Labors
/// und die ärztliche Beurteilung. Die Unterscheidung ist keine Zierde: das
/// Blatt geht an Ärztinnen, Behörden und Gerichte.
///
/// ⚠️ Jeder Eintrag trägt seine QUELLE mit und gibt sie im PDF aus. Nichts
/// hier ist aus dem Gedächtnis geschrieben — 169 Einträge stammen aus dem
/// öffentlichen Gesundheitsportal Österreichs (gesundheit.gv.at), die übrigen
/// 39 aus DocCheck Flexikon bzw. der deutschsprachigen Wikipedia, weil das
/// Portal für sie keine Seite führt.
///
/// ⚠️ Leere Felder sind Absicht. Wo die Quelle zu erhöhten oder erniedrigten
/// Werten nichts sagt, steht nichts — lieber eine Lücke als ein erfundener
/// Satz. Bei MCHC etwa sagt die Quelle selbst, der Wert habe für die
/// Anämiediagnostik untergeordnete Bedeutung.
///
/// ⚠️ Die Schlüssel sind dieselben wie in blut_parameter_liste.dart. Ein
/// umbenannter Schlüssel lässt den Text stumm verschwinden — beim Aufbau
/// dieser Datei stimmten 21 von 161 Schlüsseln nicht, und ohne die Gegenprobe
/// wären die Texte nirgends erschienen.
class BlutBedeutung {
  const BlutBedeutung({
    required this.ist,
    this.hoch = '',
    this.tief = '',
    required this.quelle,
  });

  /// Was der Parameter misst — ein bis zwei Sätze.
  final String ist;

  /// Was ein Wert ÜBER dem Referenzbereich bedeuten kann. Leer = die Quelle
  /// sagt dazu nichts.
  final String hoch;

  /// Was ein Wert UNTER dem Referenzbereich bedeuten kann.
  final String tief;

  /// Woher der Text stammt. Wird im PDF ausgewiesen.
  final String quelle;
}

const Map<String, BlutBedeutung> kBlutBedeutung = {
  'urin_menge': BlutBedeutung(
    ist: 'Gesamtmenge des in 24 Stunden gesammelten Harns; Bezugsgröße für alle Werte aus dem Sammelharn.',
    hoch: 'Große Harnmengen bei hoher Trinkmenge, unter entwässernden Medikamenten, bei Diabetes mellitus oder Diabetes insipidus.',
    tief: 'Kleine Harnmengen bei Flüssigkeitsmangel oder eingeschränkter Nierenfunktion.',
    quelle: 'gesundheit.gv.at (Harnwerte) + IMD Labor Berlin-Potsdam (Referenzbereiche Harn)',
  ),
  'acth': BlutBedeutung(
    ist: 'Hormon der Hirnanhangsdrüse; es reguliert die Bildung der Nebennierenrindenhormone, besonders Kortisol.',
    hoch: 'Nebennierenrindenunterfunktion, etwa beim Morbus Addison.',
    tief: 'Zu viel Kortisol im Blut, etwa beim Cushing-Syndrom.',
    quelle: 'gesundheit.gv.at',
  ),
  'afp': BlutBedeutung(
    ist: 'Eiweißstoff, der in der Leber des ungeborenen Kindes gebildet wird; wird als Tumormarker eingesetzt.',
    hoch: 'Lebererkrankungen (Hepatitis, Zirrhose), Lebertumore oder embryonale Tumore; in der Schwangerschaft auch Mehrlinge oder Neuralrohrdefekte.',
    tief: 'In der Schwangerschaft möglicher Hinweis auf ein Down-Syndrom des Kindes.',
    quelle: 'gesundheit.gv.at',
  ),
  'albumin': BlutBedeutung(
    ist: 'Macht etwa 50 Prozent der Serumeiweißstoffe aus und ist eines der wichtigsten Transportproteine des Blutes.',
    hoch: 'Echte Erhöhungen kommen praktisch nicht vor; meist eine relative Erhöhung durch Flüssigkeitsverlust.',
    tief: 'Lebererkrankungen (verminderte Bildung), akute Entzündungen oder Eiweißmangel durch Mangelernährung.',
    quelle: 'gesundheit.gv.at',
  ),
  'urin_albumin': BlutBedeutung(
    ist: 'Albumin im Harn; empfindlicher Frühmarker für eine Nierenschädigung.',
    hoch: 'Erfordert weiterführende Diagnostik zum Ausschluss einer Nierenerkrankung.',
    quelle: 'gesundheit.gv.at',
  ),
  'urin_albumin_krea': BlutBedeutung(
    ist: 'Albumin bezogen auf Kreatinin im Harn; dadurch von der Trinkmenge unabhängig und aus einer einzelnen Harnprobe beurteilbar.',
    hoch: 'Erhöhte Werte sind ein Frühzeichen einer Nierenschädigung, etwa bei Diabetes oder Bluthochdruck, und müssen ärztlich abgeklärt werden.',
    quelle: 'gesundheit.gv.at (Harnwerte) + IMD Labor Berlin-Potsdam (Referenzbereiche Harn)',
  ),
  'aldosteron': BlutBedeutung(
    ist: 'Hormon der Nebennierenrinde; es regelt zusammen mit Renin den Salz- und Wasserhaushalt und den Blutdruck.',
    hoch: 'Beim primären Hyperaldosteronismus erhöht; bei sekundären Formen sind Aldosteron UND Renin erhöht.',
    tief: 'Erniedrigt etwa im Rahmen eines adrenogenitalen Syndroms, dann bei gleichzeitig erhöhtem Renin.',
    quelle: 'flexikon.doccheck.com (Serum-Aldosteron)',
  ),
  'alk_phosphatase': BlutBedeutung(
    ist: 'Enzym aus Leber, Galle, Knochen, Darm und Plazenta.',
    hoch: 'Erkrankungen von Leber, Gallenwegen oder Knochen — besonders bei Gallensteinen oder Gallestauung; auch Knochenbrüche, -entzündungen oder -tumore. Bei Kindern und Schwangeren sind erhöhte Werte normal.',
    tief: 'Familiäre Hypophosphatasämie, eine seltene erbliche Stoffwechselstörung.',
    quelle: 'gesundheit.gv.at',
  ),
  'med_amiodaron': BlutBedeutung(
    ist: 'Medikament gegen Herzrhythmusstörungen.',
    hoch: 'Über dem therapeutischen Bereich steigt die Gefahr von Nebenwirkungen bis zur Vergiftung.',
    tief: 'Unter dem therapeutischen Bereich wirkt das Medikament möglicherweise nicht ausreichend.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'ammoniak': BlutBedeutung(
    ist: 'Stickstoffhaltige Verbindung, die beim Abbau von Eiweißstoffen im Körper entsteht.',
    hoch: 'Schwerwiegende Lebererkrankungen wie Leberzirrhose oder Lebertumor. Ammoniak wirkt als Zellgift und kann zu Störungen des Nervensystems bis zum Leberkoma führen.',
    tief: 'Erniedrigte Werte sind ohne Bedeutung.',
    quelle: 'gesundheit.gv.at',
  ),
  'amylase': BlutBedeutung(
    ist: 'Verdauungsenzym, das ausschließlich von der Bauchspeicheldrüse gebildet wird.',
    hoch: 'Erkrankungen der Bauchspeicheldrüse — insbesondere eine Entzündung (Pankreatitis) oder Tumorerkrankungen.',
    quelle: 'gesundheit.gv.at',
  ),
  'urin_amylase': BlutBedeutung(
    ist: 'Amylase im Harn; das Verdauungsenzym wird über die Niere ausgeschieden und bleibt dort länger nachweisbar als im Blut.',
    hoch: 'Kann auf eine Bauchspeicheldrüsenentzündung hinweisen, auch wenn der Blutwert schon wieder gesunken ist.',
    quelle: 'gesundheit.gv.at (Harnwerte) + IMD Labor Berlin-Potsdam (Referenzbereiche Harn)',
  ),
  'anca': BlutBedeutung(
    ist: 'Sammelbegriff für Autoantikörper gegen Bestandteile im Zellinneren der neutrophilen Granulozyten.',
    hoch: 'Ein positiver Nachweis kommt bei bestimmten Gefäßentzündungen (Vaskulitiden) vor und wird nach c- und p-ANCA unterschieden.',
    tief: 'Negativ ist der Normalbefund.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'androstendion': BlutBedeutung(
    ist: 'Vorstufe der männlichen und weiblichen Geschlechtshormone; wird in Nebennierenrinde und Keimdrüsen gebildet.',
    hoch: 'Bei Frauen mögliche Ursache von Vermännlichungserscheinungen; kommt beim adrenogenitalen Syndrom, beim PCO-Syndrom und bei hormonbildenden Tumoren vor.',
    tief: 'Verminderte Funktion von Nebennierenrinde oder Keimdrüsen.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'antikoerpersuchtest': BlutBedeutung(
    ist: 'Sucht im Blutplasma nach irregulären Antikörpern gegen Blutgruppenmerkmale — wichtig vor Transfusionen und in der Schwangerschaft.',
    hoch: 'Ein positives Ergebnis erfordert eine genaue Bestimmung, gegen welches Blutgruppensystem sich die Antikörper richten.',
    tief: 'Negativ ist der Normalbefund: keine transfusionsrelevanten Antikörper vorhanden.',
    quelle: 'gesundheit.gv.at',
  ),
  'ana': BlutBedeutung(
    ist: 'Antinukleäre Antikörper — Autoantikörper, die gegen körpereigene Zellkernstrukturen gerichtet sind.',
    hoch: 'Ein positiver Nachweis kann auf eine Autoimmunerkrankung hindeuten, etwa Lupus erythematodes oder Sjögren-Syndrom.',
    tief: 'Negativ ist der Normalbefund und spricht gegen eine Autoimmunerkrankung.',
    quelle: 'gesundheit.gv.at',
  ),
  'antithrombin': BlutBedeutung(
    ist: 'Blutgerinnungsfaktor, der die Gerinnung kontrolliert — ein natürlicher Schutz der Leber gegen Blutgerinnselbildung.',
    tief: 'Lebererkrankungen (verminderte Bildung), Verbrauch bei Verbrauchskoagulopathie oder ein angeborener Mangel mit erhöhter Thromboseneigung.',
    quelle: 'gesundheit.gv.at',
  ),
  'apo_a1': BlutBedeutung(
    ist: 'Das Eiweiß, das die HDL-Partikel zusammenhält; HDL bringt Cholesterin zurück zur Leber.',
    hoch: 'Gilt als günstig für das Herz-Kreislauf-Risiko.',
    tief: 'Niedrige Werte gehen mit einem erhöhten Risiko für Arterienverkalkung einher.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'apo_b': BlutBedeutung(
    ist: 'Das Eiweiß der LDL-Partikel; es entspricht der Anzahl der atherogenen Lipoprotein-Teilchen.',
    hoch: 'Zeigt viele LDL-Teilchen an und gilt als Risikofaktor für Arterienverkalkung.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'base_excess': BlutBedeutung(
    ist: 'Base excess aus der Blutgasanalyse; drückt das Ausmaß von Verschiebungen im Säure-Basen-Haushalt aus.',
    hoch: 'Verschiebung Richtung Alkalose (Basenüberschuss bzw. Säureverlust).',
    tief: 'Verschiebung Richtung Azidose (Basenverlust bzw. Säureüberschuss).',
    quelle: 'gesundheit.gv.at',
  ),
  'basophile_absolut': BlutBedeutung(
    ist: 'Spezialisierte weiße Blutkörperchen; sie spielen bei bestimmten allergischen Erkrankungen eine Rolle.',
    hoch: 'Basophilie — etwa bei chronisch myeloischer Leukämie, anderen Knochenmark-Erkrankungen oder Schilddrüsenunterfunktion.',
    tief: 'Unter anderem bei Schilddrüsenüberfunktion und bestimmten allergischen Hautreaktionen.',
    quelle: 'gesundheit.gv.at',
  ),
  'basophile_prozent': BlutBedeutung(
    ist: 'Spezialisierte weiße Blutkörperchen; sie spielen bei bestimmten allergischen Erkrankungen eine Rolle.',
    hoch: 'Basophilie — etwa bei chronisch myeloischer Leukämie, anderen Knochenmark-Erkrankungen oder Schilddrüsenunterfunktion.',
    tief: 'Unter anderem bei Schilddrüsenüberfunktion und bestimmten allergischen Hautreaktionen.',
    quelle: 'gesundheit.gv.at',
  ),
  'beta_crosslaps': BlutBedeutung(
    ist: 'Abbaufragmente von Typ-1-Kollagen; Messgröße für die Aktivität des Knochenabbaus.',
    hoch: 'Hinweis auf einen gesteigerten Knochenabbau — relevant in der Osteoporose-Diagnostik.',
    quelle: 'gesundheit.gv.at',
  ),
  'beta_hcg': BlutBedeutung(
    ist: 'Wird von der Plazenta gebildet und regt den Gelbkörper zur weiteren Progesteronbildung an.',
    hoch: 'Schwangerschaft (besonders Mehrlinge), Down-Syndrom des Fetus, bestimmte Tumorerkrankungen bei Mann und Frau.',
    tief: 'In der Schwangerschaft ein unzureichender oder fehlender Anstieg — Hinweis auf eine Schwangerschaftskomplikation.',
    quelle: 'gesundheit.gv.at',
  ),
  'bikarbonat': BlutBedeutung(
    ist: 'Bikarbonat (HCO3) aus der Blutgasanalyse — Maß für den Basenbestand des Blutes.',
    hoch: 'Verschiebung des Säure-Basen-Gleichgewichts Richtung Alkalose (Basenüberschuss bzw. Säureverlust).',
    tief: 'Verschiebung Richtung Azidose (Basenverlust bzw. Säureüberschuss).',
    quelle: 'gesundheit.gv.at',
  ),
  'urin_bilirubin': BlutBedeutung(
    ist: 'Bilirubin im Harn.',
    hoch: 'Nachweisbar bei Leberschädigung oder Störungen des Gallenabflusses.',
    quelle: 'gesundheit.gv.at',
  ),
  'bilirubin_direkt': BlutBedeutung(
    ist: 'Die wasserlösliche Form des Bilirubins, eines Abbauprodukts des roten Blutfarbstoffs.',
    hoch: 'Lebererkrankungen oder Störungen des Gallenflusses, etwa durch Gallensteine — Hinweis auf eine Gallestauung (Cholestase).',
    quelle: 'gesundheit.gv.at',
  ),
  'bilirubin_gesamt': BlutBedeutung(
    ist: 'Abbauprodukt des roten Blutfarbstoffs (Hämoglobin).',
    hoch: 'Vermehrter Abbau roter Blutkörperchen (Hämolyse), Lebererkrankungen oder Störungen des Gallenflusses (z. B. Gallensteine).',
    quelle: 'gesundheit.gv.at',
  ),
  'bilirubin_indirekt': BlutBedeutung(
    ist: 'Die nicht wasserlösliche, unkonjugierte Form des Bilirubins — der Anteil, der die Leber noch nicht umgebaut hat.',
    hoch: 'Vermehrter Abbau roter Blutkörperchen (Hämolyse) oder eine gestörte Umwandlung in der Leber, etwa beim harmlosen Morbus Meulengracht. Erscheint nicht im Harn, weil es nicht wasserlöslich ist.',
    quelle: 'flexikon.doccheck.com',
  ),
  'blasten': BlutBedeutung(
    ist: 'Unreife Vorläuferzellen der weißen Blutkörperchen, normalerweise nur im Knochenmark.',
    hoch: 'Blasten im Blut können auf schwere Entzündungen, Leukämien oder eine Chemotherapie hindeuten.',
    tief: 'Im Blut sollten keine Blasten vorhanden sein; im Knochenmark liegt der Anteil normalerweise unter 5 Prozent.',
    quelle: 'gesundheit.gv.at',
  ),
  'blutgruppe': BlutBedeutung(
    ist: 'Bestimmt die Merkmale der roten Blutkörperchen im AB0-System — dem wichtigsten Blutgruppensystem mit den Gruppen A, B, AB und 0.',
    quelle: 'gesundheit.gv.at',
  ),
  'bsg': BlutBedeutung(
    ist: 'Misst, wie schnell die roten Blutkörperchen in der Blutflüssigkeit absinken; ein Suchtest bei Verdacht auf Entzündungs- oder Autoimmunerkrankungen.',
    hoch: 'Entzündungen, Infektionen, Gelenkentzündungen, Verletzungen, Tumore, Blut- oder Lebererkrankungen.',
    tief: 'Für die Medizin sind nur erhöhte Werte von Interesse.',
    quelle: 'gesundheit.gv.at',
  ),
  'borrelien_igg': BlutBedeutung(
    ist: 'Antikörper vom Typ IgG gegen Borrelien; dienen der Diagnose einer Zecken-Borreliose.',
    hoch: 'Entstehen in späteren Stadien und können über Jahre nachweisbar bleiben. Ein positives Ergebnis allein beweist KEINE akute Infektion — es braucht die Beschwerden und weitere Tests.',
    tief: 'Ein negatives Ergebnis schließt eine Zecken-Borreliose nicht mit Sicherheit aus.',
    quelle: 'gesundheit.gv.at',
  ),
  'borrelien_igm': BlutBedeutung(
    ist: 'Antikörper vom Typ IgM gegen Borrelien; dienen der Diagnose einer Zecken-Borreliose.',
    hoch: 'Können in frühen Stadien auftreten, bleiben aber teils über Jahre nachweisbar. Ein positiver Befund ist nicht zwingend Beweis einer akuten Infektion.',
    tief: 'Ein negatives Ergebnis schließt eine Zecken-Borreliose nicht mit Sicherheit aus.',
    quelle: 'gesundheit.gv.at',
  ),
  'c_peptid': BlutBedeutung(
    ist: 'Bruchstück, das bei der Insulinbildung abgespalten wird; es zeigt, wie viel Insulin die Bauchspeicheldrüse noch selbst herstellt.',
    hoch: 'Vermehrte eigene Insulinbildung, etwa bei Insulinresistenz oder einem insulinbildenden Tumor.',
    tief: 'Geringe Restfunktion der Bauchspeicheldrüse, typisch beim Typ-1-Diabetes. ⚠️ Anders als Insulin wird C-Peptid durch gespritztes Insulin nicht verfälscht.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'crp': BlutBedeutung(
    ist: 'C-reaktives Protein — der wichtigste Blutwert zum Feststellen und zur Verlaufskontrolle einer Entzündung im Körper.',
    hoch: 'Entzündungsreaktionen: bakterielle Infektionen, Gelenkentzündungen, Verletzungen, Tumoren. Dauerhaft erhöhte Werte gelten als Risikofaktor für Herz-Kreislauf-Erkrankungen.',
    quelle: 'gesundheit.gv.at',
  ),
  'ca_125': BlutBedeutung(
    ist: 'Eiweißstoff, der in zahlreichen Zellen und Geweben gebildet wird; dient vor allem als Tumormarker. Nicht als Suchtest für eine Tumorerkrankung geeignet.',
    hoch: 'Gutartige Erkrankungen von Eierstöcken, Gebärmutter, Brust, Bauchspeicheldrüse, Leber, Magen, Darm oder Lunge; ebenso Tumorerkrankungen.',
    quelle: 'gesundheit.gv.at',
  ),
  'ca_15_3': BlutBedeutung(
    ist: 'Eiweißstoff aus Schleimhautzellen zahlreicher Gewebe; wird vor allem als Tumormarker eingesetzt.',
    hoch: 'Gutartige Erkrankungen wie Hepatitis, Bronchitis, Lungenentzündung oder Nierenerkrankungen; ebenso Tumorerkrankungen wie Brustkrebs.',
    quelle: 'gesundheit.gv.at',
  ),
  'ca_19_9': BlutBedeutung(
    ist: 'Eiweißstoff aus Zellen von Darm, Leber, Galle, Bauchspeicheldrüse, Eierstöcken und Lunge.',
    hoch: 'Gutartige Erkrankungen (Magengeschwür, Pankreatitis, Hepatitis, Leberzirrhose, Gallensteine) ebenso wie Tumorerkrankungen (Bauchspeicheldrüse, Gallenwege, Magen).',
    quelle: 'gesundheit.gv.at',
  ),
  'calcitonin': BlutBedeutung(
    ist: 'Hormon der Schilddrüse; es regelt den Kalziumstoffwechsel und wirkt als Gegenspieler des Parathormons.',
    hoch: 'Medulläres Schilddrüsenkarzinom (dort als Tumormarker eingesetzt), C-Zell-Hyperplasie, Leberzirrhose oder bestimmte Lungenkrebsarten.',
    quelle: 'gesundheit.gv.at',
  ),
  'calcium': BlutBedeutung(
    ist: 'Einer der wichtigsten Mineralstoffe im Körper; wichtig für Knochen und Zähne sowie für Blutgerinnung und Muskelarbeit.',
    hoch: 'Hormonelle Störungen der Calciumregulation, Knochentumore, bösartige Tumore oder angeborene Erkrankungen. Sehr hohe Werte können lebensbedrohlich sein.',
    tief: 'Vitamin-D-Mangel oder Mangelernährung, Nierenerkrankungen mit vermehrter Ausscheidung, Magen-Darm-Erkrankungen mit verminderter Aufnahme, Parathormonmangel.',
    quelle: 'gesundheit.gv.at',
  ),
  'urin_calcium': BlutBedeutung(
    ist: 'Calcium im Harn; wichtig bei Harnsteinen und bei Störungen des Kalziumhaushalts.',
    hoch: 'Erhöhte Ausscheidung begünstigt Nierensteine; Ursachen sind unter anderem Überfunktion der Nebenschilddrüse oder eine hohe Vitamin-D-Zufuhr.',
    tief: 'Verminderte Ausscheidung, etwa bei Vitamin-D-Mangel.',
    quelle: 'gesundheit.gv.at (Harnwerte) + IMD Labor Berlin-Potsdam (Referenzbereiche Harn)',
  ),
  'ccp_ak': BlutBedeutung(
    ist: 'Autoantikörper gegen zyklische citrullinierte Peptide, Bestandteile des Bindegewebes.',
    hoch: 'Hinweis auf rheumatoide Arthritis, eine Autoimmunerkrankung mit Gelenksentzündungen.',
    quelle: 'gesundheit.gv.at',
  ),
  'cea': BlutBedeutung(
    ist: 'Eiweißstoff, der in Darm, Leber, Bauchspeicheldrüse und Brustdrüse gebildet wird.',
    hoch: 'Tumorerkrankungen (Magen-Darm-Trakt, Brust, Leber, Bauchspeicheldrüse), aber auch gutartige Erkrankungen wie Darmentzündung, Pankreatitis, Hepatitis oder Lungenentzündung. Bei Rauchern häufig erhöht ohne Krankheitswert.',
    quelle: 'gesundheit.gv.at',
  ),
  'chlorid': BlutBedeutung(
    ist: 'Chloridionen sind die wichtigsten negativ geladenen Elektrolyte außerhalb der Körperzellen; wichtig für Wasser-, Elektrolyt- und Säure-Basen-Haushalt.',
    hoch: 'Hyperchlorämie — bei Übersäuerung des Blutes, etwa bei Nierenerkrankungen und Hormonstörungen.',
    tief: 'Hypochlorämie — unter anderem bei schwerem Erbrechen und Hormonstörungen.',
    quelle: 'gesundheit.gv.at',
  ),
  'urin_chlorid': BlutBedeutung(
    ist: 'Chlorid im Harn; ergänzt Natrium und Kalium bei der Beurteilung des Elektrolyt- und Säure-Basen-Haushalts.',
    hoch: 'Vermehrte Ausscheidung, etwa bei hoher Kochsalzzufuhr.',
    tief: 'Verminderte Ausscheidung, etwa bei starkem Erbrechen.',
    quelle: 'gesundheit.gv.at (Harnwerte) + IMD Labor Berlin-Potsdam (Referenzbereiche Harn)',
  ),
  'cholesterin': BlutBedeutung(
    ist: 'Fettartige Substanz, die mit der Nahrung aufgenommen und überall im Körper — vor allem in der Leber — gebildet wird.',
    hoch: 'Angeborene Fettstoffwechselerkrankungen, Diabetes mellitus, Adipositas, Alkoholismus, Schilddrüsenunterfunktion. Gilt als bedeutsamer Risikofaktor für Arterienverkalkung.',
    quelle: 'gesundheit.gv.at',
  ),
  'che': BlutBedeutung(
    ist: 'In der Leber gebildetes Enzym.',
    hoch: 'Wenig diagnostische Aussagekraft; möglich bei Diabetes mellitus, Schilddrüsenunterfunktion oder Eiweißverlusten über die Niere.',
    tief: 'Lässt Rückschlüsse auf Lebererkrankungen oder angeborene Veränderungen des Leberstoffwechsels zu; außerdem können bestimmte Narkosemittel stärker wirken.',
    quelle: 'gesundheit.gv.at',
  ),
  'cmv_igg': BlutBedeutung(
    ist: 'Antikörper vom Typ IgG gegen das Cytomegalievirus; dient der Diagnose einer Infektion und der Bestimmung des Immunitätsstatus.',
    hoch: 'Zeigt eine frühere CMV-Infektion mit lebenslanger Immunität an; ein Anstieg auf das Vierfache binnen zwei Wochen spricht für eine akute Infektion.',
    tief: 'Keine CMV-spezifischen Antikörper — weder Immunität noch nachgewiesene Infektion; eine ganz frische Infektion ist damit nicht sicher ausgeschlossen.',
    quelle: 'gesundheit.gv.at',
  ),
  'coeruloplasmin': BlutBedeutung(
    ist: 'Von der Leber gebildeter Eiweißstoff; er transportiert das Spurenelement Kupfer im Blut.',
    hoch: 'Entzündungen, akute Lebererkrankungen (Hepatitis) oder Bluterkrankungen wie Leukämien und Morbus Hodgkin.',
    tief: 'Morbus Wilson, chronische Lebererkrankungen (Leberzirrhose) oder Nierenerkrankungen mit Eiweißverlust.',
    quelle: 'gesundheit.gv.at',
  ),
  'cortisol': BlutBedeutung(
    ist: 'Hormon der Nebennierenrinde mit vielfältigen Wirkungen auf den gesamten Stoffwechsel.',
    hoch: 'Cushing-Syndrom — mit Fettsucht, Knochenschwund, Diabetes mellitus und Bluthochdruck.',
    tief: 'Morbus Addison bzw. Nebennierenrindeninsuffizienz — mit Ermüdbarkeit, Hautpigmentveränderungen, Gewichtsabnahme und niedrigem Blutdruck.',
    quelle: 'gesundheit.gv.at',
  ),
  'ck': BlutBedeutung(
    ist: 'Enzym, das vor allem in Herz- und Skelettmuskulatur vorkommt.',
    hoch: 'Muskelschädigung in Skelett- oder Herzmuskulatur — Herzinfarkt, Muskelkater nach Sport, Verletzungen.',
    quelle: 'gesundheit.gv.at',
  ),
  'ck_mb': BlutBedeutung(
    ist: 'Isoenzym der Creatin-Kinase, das vor allem in der Herzmuskulatur vorkommt.',
    hoch: 'Bei Herzmuskelschädigung tritt vermehrt CK-MB ins Blut über — wertvoll bei der Erstdiagnose und Verlaufskontrolle eines Herzinfarkts.',
    quelle: 'gesundheit.gv.at',
  ),
  'cyfra_21_1': BlutBedeutung(
    ist: 'Bruchstücke des Zellskelett-Proteins Cytokeratin 19; wird als Tumormarker gemessen.',
    hoch: 'Gutartige Lungenerkrankungen wie Bronchitis oder Lungenentzündung, Erkrankungen von Niere, Harnblase, Leber oder Bauchspeicheldrüse; ebenso Tumorerkrankungen wie das nicht-kleinzellige Lungenkarzinom.',
    quelle: 'gesundheit.gv.at',
  ),
  'cystatin_c': BlutBedeutung(
    ist: 'Eiweißstoff im Blut; gibt Auskunft über die Funktionstüchtigkeit der Nieren.',
    hoch: 'Hinweis auf eine gestörte Nierenfunktion.',
    quelle: 'gesundheit.gv.at',
  ),
  'd_dimere': BlutBedeutung(
    ist: 'Spaltprodukte, die entstehen, wenn sich ein Blutgerinnsel im Körper wieder auflöst.',
    hoch: 'Venenthrombose, Lungenembolie oder Verbrauchskoagulopathie.',
    tief: 'Ein normaler Wert schließt eine Thrombose mit hoher Wahrscheinlichkeit aus.',
    quelle: 'gesundheit.gv.at',
  ),
  'dhea_s': BlutBedeutung(
    ist: 'Männliches Geschlechtshormon aus der Nebennierenrinde; wird u. a. in der Fertilitätsdiagnostik gemessen.',
    hoch: 'Adrenogenitales Syndrom oder Nebennierenrindentumore.',
    tief: 'Funktionsstörungen der Nebennierenrinde (NNR-Insuffizienz).',
    quelle: 'gesundheit.gv.at',
  ),
  'med_digitoxin': BlutBedeutung(
    ist: 'Herzglykosid, verwandt mit Digoxin, aber überwiegend über die Leber ausgeschieden. ⚠️ Geringe therapeutische Breite.',
    hoch: 'Zeichen einer Digitalisintoxikation möglich.',
    tief: 'Unter dem therapeutischen Bereich wirkt das Medikament möglicherweise nicht ausreichend.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'med_digoxin': BlutBedeutung(
    ist: 'Herzglykosid zur Behandlung von Herzschwäche und Vorhofflimmern. ⚠️ Geringe therapeutische Breite — der Abstand zwischen Wirkung und Vergiftung ist klein.',
    hoch: 'Zeichen einer Digitalisintoxikation möglich; schon im therapeutischen Bereich treten bei älteren Menschen Nebenwirkungen auf. Verapamil, Nifedipin, Chinidin und Amiodaron erhöhen den Spiegel.',
    tief: 'Unter dem therapeutischen Bereich wirkt das Medikament möglicherweise nicht ausreichend.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'ebv_vca_igg': BlutBedeutung(
    ist: 'Antikörper vom Typ IgG gegen das Epstein-Barr-Virus; dient der Diagnose und der Bestimmung des Immunitätsstatus.',
    hoch: 'Werden erst in späteren Phasen einer akuten Infektion gebildet und bleiben meist lebenslang nachweisbar — Zeichen einer durchgemachten Infektion.',
    tief: 'Kein Kontakt mit dem Virus bzw. keine Infektion nachweisbar.',
    quelle: 'gesundheit.gv.at',
  ),
  'ckd_epi': BlutBedeutung(
    ist: 'Geschätzte glomeruläre Filtrationsrate — eine Messgröße zur Beurteilung der gesamten Funktionsleistung der Nieren.',
    tief: 'Kann ein Hinweis auf eine gestörte Nierenfunktion sein; bei starker Verminderung sammeln sich harnpflichtige Stoffe im Blut an.',
    quelle: 'gesundheit.gv.at',
  ),
  'eisen': BlutBedeutung(
    ist: 'Das im Körper häufigste Spurenelement; wesentlicher Bestandteil des roten Blutfarbstoffs und wichtig für den Sauerstofftransport.',
    hoch: 'Vermehrte Eisenaufnahme (Hämochromatose), Eisenverwertungsstörungen, hämolytische Anämien.',
    tief: 'Eisenverlust durch Blutungen, zu geringe Aufnahme oder Darmerkrankungen, erhöhter Bedarf, chronische Entzündungen. Führt oft zur Eisenmangelanämie.',
    quelle: 'gesundheit.gv.at',
  ),
  'eosinophile_absolut': BlutBedeutung(
    ist: 'Spezialisierte weiße Blutkörperchen; beteiligt an der Abwehr von Parasiten sowie bei Allergien und Autoimmunreaktionen.',
    hoch: 'Parasitäre Erkrankungen, allergische Erkrankungen, Autoimmunerkrankungen oder das Abklingen akuter Infektionen.',
    tief: 'Knochenmark-Schädigungen, Nebennierenrindenüberfunktion oder bestimmte Medikamente.',
    quelle: 'gesundheit.gv.at',
  ),
  'eosinophile_prozent': BlutBedeutung(
    ist: 'Spezialisierte weiße Blutkörperchen; beteiligt an der Abwehr von Parasiten sowie bei Allergien und Autoimmunreaktionen.',
    hoch: 'Parasitäre Erkrankungen, allergische Erkrankungen, Autoimmunerkrankungen oder das Abklingen akuter Infektionen.',
    tief: 'Knochenmark-Schädigungen, Nebennierenrindenüberfunktion oder bestimmte Medikamente.',
    quelle: 'gesundheit.gv.at',
  ),
  'erythrozyten': BlutBedeutung(
    ist: 'Rote Blutkörperchen — scheibenförmige, kernlose Blutzellen, zuständig für den Sauerstofftransport.',
    hoch: 'Polyglobulie — bei Sauerstoffmangel, Lungenerkrankungen, hormonellen Störungen oder bestimmten Leukämieformen.',
    tief: 'Anämie — durch mangelhafte Bildung (z. B. Eisenmangel), Blutverlust oder gesteigerte Zerstörung der Erythrozyten.',
    quelle: 'gesundheit.gv.at',
  ),
  'urin_erythrozyten': BlutBedeutung(
    ist: 'Rote Blutkörperchen im Harn; kleinste Mengen werden als Mikrohämaturie bezeichnet.',
    hoch: 'Ein positiver Befund erfordert eine mikroskopische Untersuchung des Harnsediments.',
    quelle: 'gesundheit.gv.at',
  ),
  'rdw': BlutBedeutung(
    ist: 'Maß für die Größenverteilung der roten Blutkörperchen, in Prozent.',
    hoch: 'Zusammen mit MCV und MCH ein Hinweis auf die Ursache einer Blutarmut: kleine, blasse Erythrozyten mit hoher RDW sprechen für Eisenmangel.',
    tief: 'Kleine, blasse Erythrozyten mit niedriger RDW sprechen eher für eine Thalassämie.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'estradiol': BlutBedeutung(
    ist: 'Das wichtigste und wirksamste Östrogen der geschlechtsreifen Frau; vor allem in den Eierstöcken gebildet.',
    hoch: 'Vorzeitige Pubertät, Schwangerschaft, Überdosierung östrogenhaltiger Medikamente oder ein hormonproduzierender Tumor.',
    tief: 'Erkrankungen der Eierstöcke, Einnahme der Anti-Baby-Pille, Erkrankungen von Hirnanhangsdrüse oder Hypothalamus.',
    quelle: 'gesundheit.gv.at',
  ),
  'ferritin': BlutBedeutung(
    ist: 'Eiweißstoff zur Speicherung von Eisen im Körper; spiegelt den Eisenhaushalt wider.',
    hoch: 'Vermehrte Eisenaufnahme (Hämochromatose), Eisenüberladung durch Therapie, Infektionen und Entzündungen, Tumorerkrankungen, Leberzirrhose.',
    tief: 'Eisenverlust durch Blutungen, zu geringe Eisenaufnahme, erhöhter Bedarf (Schwangerschaft, Wachstum). Kann zur Eisenmangelanämie führen.',
    quelle: 'gesundheit.gv.at',
  ),
  'fibrinogen': BlutBedeutung(
    ist: 'Vorläufer-Eiweißstoff von Fibrin, dem Hauptbestandteil des Blutgerinnsels.',
    hoch: 'Akute Entzündungen (Verbrennungen, Verletzungen), chronische Entzündungen (Rheuma, Autoimmunerkrankungen) oder Schwangerschaft.',
    tief: 'Lebererkrankungen oder Verbrauchskoagulopathie (DIC) — ein lebensbedrohlicher Zustand.',
    quelle: 'gesundheit.gv.at',
  ),
  'folsaeure': BlutBedeutung(
    ist: 'Wasserlösliches Vitamin, vor allem in grünen Gemüsesorten und Innereien enthalten.',
    hoch: 'Überdosierung von Vitaminpräparaten; Hämolyse (vermehrter Abbau roter Blutkörperchen).',
    tief: 'Fehlernährung, Erkrankungen des Magen-Darm-Traktes, angeborene Stoffwechselerkrankungen. Ein Mangel kann zu Anämie führen; in der Schwangerschaft besteht ein Risiko für Neuralrohrdefekte.',
    quelle: 'gesundheit.gv.at',
  ),
  'psa_frei': BlutBedeutung(
    ist: 'Der nicht an Eiweiß gebundene Anteil des PSA; wird als Verhältnis zum Gesamt-PSA beurteilt.',
    hoch: 'Ein hoher Anteil freies PSA spricht eher für eine gutartige Vergrößerung der Prostata.',
    tief: 'Ein niedriger Anteil erhöht den Verdacht auf ein Prostatakarzinom.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'ft4': BlutBedeutung(
    ist: 'Thyroxin (T4) gehört zusammen mit T3 zu den Schilddrüsenhormonen; T4 ist die Vorstufe von T3.',
    hoch: 'Hinweis auf eine Schilddrüsenüberfunktion (Hyperthyreose).',
    tief: 'Hinweis auf eine Schilddrüsenunterfunktion (Hypothyreose).',
    quelle: 'gesundheit.gv.at',
  ),
  'ft3': BlutBedeutung(
    ist: 'Trijodthyronin (T3) ist das wirksamste Schilddrüsenhormon.',
    hoch: 'Hinweis auf eine Schilddrüsenüberfunktion (Hyperthyreose).',
    tief: 'Hinweis auf eine Schilddrüsenunterfunktion (Hypothyreose).',
    quelle: 'gesundheit.gv.at',
  ),
  'fructosamin': BlutBedeutung(
    ist: 'Verzuckerte Bluteiweiße; sie spiegeln den mittleren Blutzucker der vergangenen ein bis drei Wochen wider.',
    hoch: 'Zeichen erhöhter Blutzuckerwerte in den zurückliegenden Wochen.',
    quelle: 'de.wikipedia.org (Fructosamin)',
  ),
  'fsh': BlutBedeutung(
    ist: 'Follikelstimulierendes Hormon; bei Frauen für die Reifung des Follikels, beim Mann für Bildung und Reifung der Spermien wichtig.',
    hoch: 'Meist Störungen der Keimdrüsen — bei Frauen etwa vorzeitige Pubertät, Wechsel, Autoimmunerkrankungen oder Schädigung der Eierstöcke.',
    tief: 'Erkrankungen oder Funktionsstörungen der Hirnanhangsdrüse — Verletzungen, Tumore, Operationen, Stress, Extremsport, Magersucht.',
    quelle: 'gesundheit.gv.at',
  ),
  'g_gt': BlutBedeutung(
    ist: 'Enzym, das vor allem in der Leber, aber auch in Nieren, Gallengängen und Darm vorkommt.',
    hoch: 'Störungen des Gallenflusses (z. B. Gallensteine), alkoholische oder toxische Leberschädigung.',
    tief: 'Erniedrigte Werte sind ohne Bedeutung.',
    quelle: 'gesundheit.gv.at',
  ),
  'gesamteiweiss': BlutBedeutung(
    ist: 'Der gesamte Eiweißgehalt der Blutflüssigkeit.',
    hoch: 'Erfordert weitere Abklärung durch Serumeiweiß-Elektrophorese, um eine krankhafte Vermehrung der Immunglobuline auszuschließen.',
    tief: 'Lebererkrankungen (z. B. Leberzirrhose), Eiweißverlust über Niere, Darm oder Haut, Eiweißmangelernährung.',
    quelle: 'gesundheit.gv.at',
  ),
  'urin_eiweiss': BlutBedeutung(
    ist: 'Eiweiß im Harn.',
    hoch: 'Ein positiver Nachweis erfordert weiterführende Diagnostik zum Ausschluss einer Nierenerkrankung.',
    quelle: 'gesundheit.gv.at',
  ),
  'gldh': BlutBedeutung(
    ist: 'Enzym, das vor allem in den Mitochondrien der Leberzellen sitzt — es tritt erst aus, wenn Zellen wirklich zugrunde gehen.',
    hoch: 'Stark erhöhte Werte sprechen für einen schweren Leberzellschaden; ergänzt GOT und GPT bei der Frage, wie tief die Schädigung reicht.',
    quelle: 'flexikon.doccheck.com',
  ),
  'glucose_nuechtern': BlutBedeutung(
    ist: 'Traubenzucker im Blut — der wichtigste Labortest zur Diagnose einer Zuckerkrankheit (Diabetes mellitus).',
    hoch: 'Nüchtern über 125 mg/dl spricht für Diabetes mellitus; zwischen 100 und 125 mg/dl besteht ein erhöhtes Risiko.',
    tief: 'Tritt normalerweise nicht auf, da der Körper selbst gegensteuert; möglich bei Insulinüberdosierung, Überdosierung von Diabetes-Medikamenten oder insulinproduzierenden Tumoren.',
    quelle: 'gesundheit.gv.at',
  ),
  'urin_glucose': BlutBedeutung(
    ist: 'Zucker im Harn. Erst wenn die Nierenschwelle im Blut überschritten ist, erscheint Glukose im Harn.',
    hoch: 'Ein positiver Befund kann auf Diabetes mellitus hindeuten.',
    quelle: 'gesundheit.gv.at',
  ),
  'got': BlutBedeutung(
    ist: 'Enzym, das vor allem in der Leber, aber auch in Herz- und Skelettmuskulatur vorkommt (auch AST/ASAT genannt).',
    hoch: 'Leberschaden (Entzündung, Vergiftung, gestörte Blutversorgung, Tumor) oder Schädigung von Muskelzellen, etwa beim Herzinfarkt.',
    tief: 'Erniedrigte Werte sind ohne Bedeutung.',
    quelle: 'gesundheit.gv.at',
  ),
  'gpt': BlutBedeutung(
    ist: 'Enzym, das vor allem in der Leber vorkommt (auch ALT/ALAT genannt). Steigt schon bei leichter Leberschädigung.',
    hoch: 'Leberschaden — Leberentzündung (Hepatitis), Vergiftungen, gestörte Blutversorgung oder Lebertumore.',
    tief: 'Erniedrigte Werte sind ohne Bedeutung.',
    quelle: 'gesundheit.gv.at',
  ),
  'haptoglobin': BlutBedeutung(
    ist: 'In der Leber gebildeter Bluteiweißstoff; Transportprotein für freies Hämoglobin.',
    hoch: 'Entzündung (Haptoglobin ist ein Akute-Phase-Protein) oder eine bösartige Tumorerkrankung.',
    tief: 'Hämolyse (hämolytische Anämie), schwere Lebererkrankungen oder Eiweißmangel.',
    quelle: 'gesundheit.gv.at',
  ),
  'harnstoff': BlutBedeutung(
    ist: 'In der Leber gebildetes Endprodukt des Eiweißstoffwechsels; wird zur Beurteilung von Eiweißstoffwechsel und Nierenfunktion gemessen.',
    hoch: 'Entweder wird zu viel gebildet (Blutungen im Magen-Darm-Bereich, sehr eiweißreiche Kost) oder zu wenig ausgeschieden (gestörte Nierendurchblutung, Nierenversagen).',
    tief: 'Geringe Eiweißzufuhr, chronischer Alkoholismus oder schwere Lebererkrankungen — erniedrigte Werte haben nur geringe diagnostische Bedeutung.',
    quelle: 'gesundheit.gv.at',
  ),
  'urin_harnstoff': BlutBedeutung(
    ist: 'Harnstoff im Harn; Endprodukt des Eiweißstoffwechsels, das über die Niere ausgeschieden wird.',
    hoch: 'Hohe Eiweißzufuhr oder vermehrter Eiweißabbau.',
    tief: 'Geringe Eiweißzufuhr oder eingeschränkte Nierenfunktion.',
    quelle: 'gesundheit.gv.at (Harnwerte) + IMD Labor Berlin-Potsdam (Referenzbereiche Harn)',
  ),
  'harnsaeure': BlutBedeutung(
    ist: 'Endprodukt des Purinstoffwechsels; wird vor allem über die Nieren ausgeschieden.',
    hoch: 'Kann zu Gicht oder Nierensteinen führen. Ursachen: vermehrte Bildung, erhöhte Purinzufuhr mit der Nahrung oder zu geringe Ausscheidung über die Nieren.',
    tief: 'Zu niedrige Werte haben praktisch keine Bedeutung.',
    quelle: 'gesundheit.gv.at',
  ),
  'urin_harnsaeure': BlutBedeutung(
    ist: 'Harnsäure im Harn; zeigt, wie viel Harnsäure die Niere ausscheidet.',
    hoch: 'Erhöhte Ausscheidung begünstigt Harnsäuresteine.',
    tief: 'Verminderte Ausscheidung ist eine mögliche Ursache erhöhter Harnsäure im Blut.',
    quelle: 'gesundheit.gv.at (Harnwerte) + IMD Labor Berlin-Potsdam (Referenzbereiche Harn)',
  ),
  'hba1c_ifcc': BlutBedeutung(
    ist: 'Derselbe Wert wie HbA1c, nur in der internationalen IFCC-Einheit mmol/mol statt in Prozent angegeben.',
    hoch: 'Entsteht durch dauerhaft zu hohe Blutzuckerwerte und kann auf Diabetes mellitus hindeuten.',
    quelle: 'gesundheit.gv.at',
  ),
  'hba1c': BlutBedeutung(
    ist: 'Glykierter („verzuckerter") roter Blutfarbstoff; spiegelt den Blutzucker der vorangegangenen vier bis sechs Wochen wider.',
    hoch: 'Entsteht durch dauerhaft zu hohe Blutzuckerwerte und kann auf Diabetes mellitus hindeuten.',
    quelle: 'gesundheit.gv.at',
  ),
  'hdl_cholesterin': BlutBedeutung(
    ist: 'Das „gute" Cholesterin — es transportiert Cholesterin zurück zur Leber und wirkt als Schutzfaktor vor Arterienverkalkung.',
    hoch: 'Höhere Werte gelten nicht als Risikofaktor.',
    tief: 'Stellt einen Risikofaktor für Arterienverkalkung dar. Ursachen: Übergewicht, Bewegungsmangel, Rauchen, Diabetes oder erhöhte Triglyceride.',
    quelle: 'gesundheit.gv.at',
  ),
  'hepatitis_a_igg': BlutBedeutung(
    ist: 'Antikörper vom Typ IgG gegen das Hepatitis-A-Virus; der wichtigste Test, ob ein Kontakt mit dem Virus stattgefunden hat.',
    hoch: 'Zeigt eine durchgemachte Hepatitis-A-Infektion ODER eine erfolgreiche Impfung an — also Immunität.',
    tief: 'Kein Kontakt mit dem Virus durch Infektion oder Impfung; kein Immunschutz.',
    quelle: 'gesundheit.gv.at',
  ),
  'hepatitis_a_igm': BlutBedeutung(
    ist: 'Antikörper vom Typ IgM gegen das Hepatitis-A-Virus.',
    hoch: 'Hinweis auf eine akute oder kürzlich durchgemachte Hepatitis-A-Erkrankung.',
    tief: 'Keine akute Hepatitis-A-Infektion.',
    quelle: 'gesundheit.gv.at',
  ),
  'hepatitis_b_c_igg': BlutBedeutung(
    ist: 'Anti-HBc — Antikörper gegen das core-Antigen des Hepatitis-B-Virus.',
    hoch: 'Nachweis einer bestehenden oder durchgemachten Infektion mit dem Hepatitis-B-Virus.',
    tief: 'Kein Hinweis auf eine bestehende oder durchgemachte Infektion.',
    quelle: 'gesundheit.gv.at',
  ),
  'hepatitis_b_s_ag': BlutBedeutung(
    ist: 'HBs-Antigen — das Oberflächenprotein des Hepatitis-B-Virus.',
    hoch: 'Ein Nachweis bedeutet, dass eine Infektion mit dem Hepatitis-B-Virus vorliegt.',
    tief: 'Kein Nachweis spricht gegen eine bestehende Hepatitis-B-Infektion.',
    quelle: 'gesundheit.gv.at',
  ),
  'hepatitis_b_s_ak': BlutBedeutung(
    ist: 'Anti-HBs — Antikörper gegen das Oberflächenantigen des Hepatitis-B-Virus.',
    hoch: 'Hinweis auf eine durchgemachte Hepatitis-B-Infektion ODER auf eine Impfung gegen das Virus.',
    tief: 'Kein Schutz durch Impfung oder durchgemachte Infektion nachweisbar.',
    quelle: 'gesundheit.gv.at',
  ),
  'hepatitis_c_ig': BlutBedeutung(
    ist: 'Anti-HCV — Antikörper gegen das Hepatitis-C-Virus; etwa acht Wochen nach einer Infektion nachweisbar.',
    hoch: 'Hinweis auf eine akute, chronische oder durchgemachte Hepatitis-C-Infektion.',
    tief: 'Kein Hinweis auf eine Infektion; in den ersten Wochen nach Ansteckung kann der Test noch negativ sein.',
    quelle: 'gesundheit.gv.at',
  ),
  'hiv_screening': BlutBedeutung(
    ist: 'HIV-Suchtest — Antikörper (in Österreich als Kombinationstest mit Antigen) gegen das humane Immundefizienz-Virus.',
    hoch: 'Ein reaktives Ergebnis muss durch einen Bestätigungstest abgeklärt werden; es ist für sich allein noch keine Diagnose.',
    tief: 'Kein Hinweis auf eine Infektion. Kombinationstests verkürzen das diagnostische Fenster, schließen eine ganz frische Ansteckung aber nicht sicher aus.',
    quelle: 'gesundheit.gv.at',
  ),
  'hla_b27': BlutBedeutung(
    ist: 'Eine erblich festgelegte Variante des Gewebemerkmals HLA-B.',
    hoch: 'Ein positives Ergebnis findet sich gehäuft bei Morbus Bechterew und verwandten Erkrankungen. ⚠️ Der Nachweis allein ist keine Diagnose — viele Träger erkranken nie.',
    tief: 'Negativ macht diese Erkrankungsgruppe weniger wahrscheinlich, schließt sie aber nicht aus.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'holo_transcobalamin': BlutBedeutung(
    ist: 'Vitamin B12 gebunden an sein Transporteiweiß — die für die Zellen verfügbare Form, deshalb „aktives B12" genannt.',
    tief: 'Gilt als der früheste Marker eines Vitamin-B12-Mangels, oft bevor das Gesamt-B12 auffällig wird.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'homocystein': BlutBedeutung(
    ist: 'Schwefelhaltige Aminosäure, die im Stoffwechsel gebildet und rasch wieder abgebaut wird.',
    hoch: 'Steigert das Risiko für Venenthrombosen und Herz-Kreislauf-Erkrankungen. Ursachen: Vitaminmangel (Folsäure, B6, B12), angeborene Gendefekte oder Niereninsuffizienz.',
    quelle: 'gesundheit.gv.at',
  ),
  'haematokrit': BlutBedeutung(
    ist: 'Anteil der Blutzellen am gesamten Blutvolumen, in Prozent.',
    hoch: 'Bei Sauerstoffmangel (z. B. Lungenerkrankungen), hormonellen Störungen oder bestimmten Bluterkrankungen.',
    tief: 'Deutet auf Blutarmut hin — mangelhafte Bildung, Blutverlust oder erhöhter Blutabbau.',
    quelle: 'gesundheit.gv.at',
  ),
  'haemoglobin': BlutBedeutung(
    ist: 'Roter Blutfarbstoff in den roten Blutkörperchen; gewährleistet den Sauerstofftransport im Blut.',
    hoch: 'Polyglobulie — u. a. bei Sauerstoffmangel, Lungenerkrankungen, hormonellen Störungen oder bestimmten Leukämieformen.',
    tief: 'Anämie (Blutarmut) — durch mangelhafte Bildung (z. B. Eisenmangel), Blutverlust oder gesteigerten Blutabbau.',
    quelle: 'gesundheit.gv.at',
  ),
  'igf_1': BlutBedeutung(
    ist: 'Wird vor allem in der Leber unter Einfluss des Wachstumshormons gebildet und vermittelt dessen Wirkung auf Wachstum und Reifung.',
    hoch: 'Wachstumsschübe, Riesenwuchs im Kindesalter, Akromegalie im Erwachsenenalter, Fettsucht oder Schwangerschaft.',
    tief: 'Minderwuchs im Kindesalter oder Funktionsstörungen der Wachstumshormon-Achse.',
    quelle: 'gesundheit.gv.at',
  ),
  'iga': BlutBedeutung(
    ist: 'Antikörper vom Typ Immunglobulin A — vor allem in Körpersekreten wie Speichel, Tränenflüssigkeit und Nasenschleim.',
    hoch: 'Chronische Entzündungsprozesse, Autoimmunerkrankungen oder schwere Lebererkrankungen; bei monoklonaler Vermehrung Verdacht auf ein malignes Lymphom.',
    tief: 'Angeborener IgA-Mangel — der häufigste primäre Antikörpermangel, oft mit erhöhter Infektanfälligkeit; erworben durch Eiweißmangel, Schilddrüsenunterfunktion oder Lymphome.',
    quelle: 'gesundheit.gv.at',
  ),
  'ige_gesamt': BlutBedeutung(
    ist: 'Antikörper vom Typ Immunglobulin E — verantwortlich für die Vermittlung bestimmter allergischer Reaktionen.',
    hoch: 'Möglicher Hinweis auf eine allergische Erkrankung vom Soforttyp (Typ 1).',
    tief: 'Ein niedriger Wert macht eine Typ-1-Allergie unwahrscheinlich, schließt sie aber nicht aus.',
    quelle: 'gesundheit.gv.at',
  ),
  'igg': BlutBedeutung(
    ist: 'Antikörper vom Typ Immunglobulin G — die wichtigsten Abwehrstoffe im Blut; sie vermitteln das immunologische Gedächtnis.',
    hoch: 'Hypergammaglobulinämie — chronische Entzündungsprozesse, Autoimmunerkrankungen oder schwere Lebererkrankungen; bei monoklonaler Vermehrung Verdacht auf eine bösartige Erkrankung des lymphatischen Systems.',
    tief: 'Hypogammaglobulinämie — angeborener Antikörpermangel oder erworben durch Eiweißmangel, Schilddrüsenunterfunktion oder Lymphome.',
    quelle: 'gesundheit.gv.at',
  ),
  'igm': BlutBedeutung(
    ist: 'Antikörper vom Typ Immunglobulin M — werden beim ERSTEN Kontakt mit einem Krankheitserreger gebildet und zeigen die primäre Immunantwort an.',
    hoch: 'Reaktive Prozesse wie chronische Entzündungen und Autoimmunerkrankungen; bei monoklonaler Vermehrung Hinweis auf maligne Lymphome.',
    tief: 'Angeborener oder erworbener Antikörpermangel, etwa durch Eiweißmangel.',
    quelle: 'gesundheit.gv.at',
  ),
  'inr': BlutBedeutung(
    ist: 'Standardisierte Form des Quick-Werts; sie macht Gerinnungsmessungen zwischen Laboren vergleichbar.',
    hoch: 'Das Blut gerinnt langsamer — gewollt unter Marcumar-artigen Gerinnungshemmern, sonst bei Lebererkrankungen oder Vitamin-K-Mangel.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'insulin': BlutBedeutung(
    ist: 'Das einzige blutzuckersenkende Hormon des Körpers.',
    hoch: 'Bei Abklärung einer Unterzuckerung möglicher Hinweis auf einen insulinproduzierenden Tumor; beim Typ-2-Diabetes Zeichen einer verminderten Antwort der Körperzellen auf das Hormon.',
    tief: 'Beim Typ-1-Diabetes Zeichen einer unzureichenden Produktion, weil die insulinbildenden Zellen der Bauchspeicheldrüse zugrunde gehen.',
    quelle: 'gesundheit.gv.at',
  ),
  'interleukin_6': BlutBedeutung(
    ist: 'Entzündungsmarker, der von weißen Blutkörperchen direkt am Ort der Entzündung freigesetzt wird.',
    hoch: 'Deutet auf eine schwere, den gesamten Organismus betreffende Entzündungsreaktion hin, etwa eine Sepsis; die Höhe korreliert mit der Schwere.',
    quelle: 'gesundheit.gv.at',
  ),
  'kalium': BlutBedeutung(
    ist: 'Kaliumionen sind die wichtigsten positiv geladenen Elektrolyte innerhalb der Körperzellen.',
    hoch: 'Hyperkaliämie — Blutübersäuerung (Azidose), erhöhte Kaliumzufuhr, verminderte Ausscheidung durch Hormonstörungen.',
    tief: 'Hypokaliämie — Alkalose, Verluste durch Durchfall, Erbrechen oder Abführmittel, Hormonstörungen oder Nierenerkrankungen.',
    quelle: 'gesundheit.gv.at',
  ),
  'urin_kalium': BlutBedeutung(
    ist: 'Kalium im Harn; zeigt, wie viel Kalium die Niere ausscheidet.',
    hoch: 'Vermehrte Ausscheidung, etwa unter entwässernden Medikamenten oder bei Hormonstörungen.',
    tief: 'Verminderte Ausscheidung; hilft zu unterscheiden, ob ein niedriges Kalium im Blut über die Niere oder den Darm verloren geht.',
    quelle: 'gesundheit.gv.at (Harnwerte) + IMD Labor Berlin-Potsdam (Referenzbereiche Harn)',
  ),
  'urin_keton': BlutBedeutung(
    ist: 'Ketonkörper im Harn.',
    hoch: 'Positiv bei entgleistem Diabetes mellitus oder bei Nulldiät bzw. längerem Fasten.',
    quelle: 'gesundheit.gv.at',
  ),
  'knochen_ap': BlutBedeutung(
    ist: 'Knochenspezifische alkalische Phosphatase; Messgröße für einen gesteigerten Knochenstoffwechsel.',
    hoch: 'Normal in Wachstumsphasen, nach Knochenbrüchen oder in der Schwangerschaft; krankhaft bei Knochentumoren, Metastasen, Osteoporose mit hohem Umsatz, Morbus Paget oder Vitamin-D-Mangel.',
    tief: 'Mangel an Parathormon oder Therapie mit Kortison.',
    quelle: 'gesundheit.gv.at',
  ),
  'pco2': BlutBedeutung(
    ist: 'Menge des im arteriellen Blut gelösten Kohlendioxids; eine wichtige Kenngröße für die Lungenfunktion.',
    hoch: 'Verminderte Abatmung von Kohlendioxid über die Lungen — respiratorische Azidose.',
    tief: 'Zu rasches Atmen (Hyperventilation) mit Säureverlust — respiratorische Alkalose.',
    quelle: 'gesundheit.gv.at',
  ),
  'creatinin': BlutBedeutung(
    ist: 'Kreatinin entsteht aus dem Muskelstoff Kreatin und ist ein wichtiger Messwert für die Nierenfunktion.',
    hoch: 'Gestörte Nierenfunktion bis Nierenversagen; auch bei Flüssigkeitsmangel, fleischreicher Ernährung oder hoher Muskelmasse ohne Nierenschaden.',
    quelle: 'gesundheit.gv.at',
  ),
  'urin_creatinin': BlutBedeutung(
    ist: 'Kreatinin im Harn. Dient vor allem als Bezugsgröße: andere Harnwerte werden darauf umgerechnet, damit die Trinkmenge das Ergebnis nicht verfälscht.',
    hoch: 'Konzentrierter Harn, etwa bei geringer Trinkmenge.',
    tief: 'Stark verdünnter Harn — andere Werte im selben Harn sind dann nur eingeschränkt beurteilbar.',
    quelle: 'gesundheit.gv.at (Harnwerte) + IMD Labor Berlin-Potsdam (Referenzbereiche Harn)',
  ),
  'creatinin_clearance': BlutBedeutung(
    ist: 'Prüft die Nierenfunktion; besonders geeignet, um eine leichte bis mäßige Funktionsstörung zu erkennen.',
    tief: 'Hinweis auf eine gestörte Nierenfunktion.',
    quelle: 'gesundheit.gv.at',
  ),
  'kupfer': BlutBedeutung(
    ist: 'Wichtiges Spurenelement für den Zellstoffwechsel.',
    hoch: 'Entzündungen, Lebererkrankungen oder Bluterkrankungen wie Leukämien.',
    tief: 'Bei gleichzeitig gesteigerter Ausscheidung im Harn ein Hinweis auf Morbus Wilson — mit Blutarmut, Knochen- und Bindegewebsveränderungen sowie neurologischen Störungen.',
    quelle: 'gesundheit.gv.at',
  ),
  'laktat': BlutBedeutung(
    ist: 'Stoffwechselprodukt, das beim Abbau von Traubenzucker unter Sauerstoffmangel entsteht.',
    hoch: 'Sauerstoffmangel im Gewebe, Schock, diabetisches Koma oder körperliche Überbelastung.',
    tief: 'Kommt bei seltenen angeborenen Stoffwechselerkrankungen vor.',
    quelle: 'gesundheit.gv.at',
  ),
  'ldh': BlutBedeutung(
    ist: 'Enzym, das in allen Geweben des Körpers vorkommt; zeigt Schädigungen in Leber, Muskulatur, Nieren und roten Blutkörperchen an.',
    hoch: 'Lebererkrankungen, Herzinfarkt oder Muskelverletzungen, Zerstörung roter Blutkörperchen (Hämolyse), Leukämie — auch eine fehlerhafte Blutabnahme.',
    quelle: 'gesundheit.gv.at',
  ),
  'ldl_cholesterin': BlutBedeutung(
    ist: 'Das „schlechte" Cholesterin — es gilt als Risikofaktor für Arterienverkalkung.',
    hoch: 'Übergewicht, Bewegungsmangel, Rauchen, Diabetes mellitus, erhöhte Triglyceride. Ein erhöhter Wert ist ein Risikofaktor für Atherosklerose.',
    quelle: 'gesundheit.gv.at',
  ),
  'leukozyten': BlutBedeutung(
    ist: 'Weiße Blutkörperchen; sie sind für die Abwehr von Krankheitserregern zuständig und umfassen die Zellen des Immunsystems.',
    hoch: 'Leukozytose — bei Infektionen, Entzündungen, Leukämien oder Lymphomen. Zur Klärung dient das Differenzialblutbild.',
    tief: 'Leukopenie — z. B. bei Knochenmark-Erkrankungen oder anderen Störungen der Blutzellbildung.',
    quelle: 'gesundheit.gv.at',
  ),
  'urin_leukozyten': BlutBedeutung(
    ist: 'Weiße Blutkörperchen im Harn.',
    hoch: 'Kann ein Hinweis auf eine Harnwegsinfektion sein.',
    quelle: 'gesundheit.gv.at',
  ),
  'lh': BlutBedeutung(
    ist: 'Luteinisierendes Hormon; bewirkt bei Frauen Eisprung und Gelbkörperbildung, beim Mann die Testosteronbildung im Hoden.',
    hoch: 'Meist Störung der Keimdrüsen — Funktionsstörung der Eierstöcke, Wechsel; beim Mann etwa Klinefelter-Syndrom.',
    tief: 'Erkrankungen oder Funktionsstörungen der Hirnanhangsdrüse — Verletzungen, Tumore, Operationen, Stress, Extremsport, Magersucht.',
    quelle: 'gesundheit.gv.at',
  ),
  'lipase': BlutBedeutung(
    ist: 'Verdauungsenzym der Bauchspeicheldrüse; wird für die Fettverdauung benötigt.',
    hoch: 'Bauchspeicheldrüsenentzündung, Tumorerkrankungen der Bauchspeicheldrüse oder Darmverschluss. Ein erhöhter Wert ist ein Hinweis, kein Beweis.',
    quelle: 'gesundheit.gv.at',
  ),
  'lipoprotein_a': BlutBedeutung(
    ist: 'Eiweißstoff, der im Blut gemessen werden kann; die Menge ist weitgehend erblich festgelegt.',
    hoch: 'Weist auf ein gesteigertes Risiko für Arterienverkalkung und Thrombosen hin — besonders zusammen mit erhöhtem LDL-Cholesterin.',
    quelle: 'gesundheit.gv.at',
  ),
  'med_lithium': BlutBedeutung(
    ist: 'Medikament zur Stimmungsstabilisierung. ⚠️ Geringe therapeutische Breite — der Spiegel wird regelmäßig kontrolliert.',
    hoch: 'Über dem therapeutischen Bereich steigt die Gefahr von Nebenwirkungen bis zur Vergiftung.',
    tief: 'Unter dem therapeutischen Bereich wirkt das Medikament möglicherweise nicht ausreichend.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'lues_tpha': BlutBedeutung(
    ist: 'Suchtest auf Antikörper gegen Treponema pallidum, den Erreger der Syphilis.',
    hoch: 'Das Immunsystem hatte vermutlich Kontakt mit dem Erreger. Der Test kann auch lange nach einer ausgeheilten Syphilis positiv bleiben.',
    tief: 'Keine Antikörper gegen Treponema pallidum nachweisbar.',
    quelle: 'gesundheit.gv.at',
  ),
  'lymphozyten_absolut': BlutBedeutung(
    ist: 'Zellen des erworbenen Immunsystems; zuständig für die Abwehr von Virus- und Pilzinfektionen und für die Bildung von Antikörpern.',
    hoch: 'Bestimmte Infektionen (etwa Hepatitis), bösartige Bluterkrankungen (Leukämien) oder Lymphome, auch bestimmte Medikamente.',
    tief: 'Bestimmte Infektionen (z. B. Masern), Erkrankungen des Immunsystems (etwa HIV-Infektion) oder eine Kortisontherapie.',
    quelle: 'gesundheit.gv.at',
  ),
  'lymphozyten_prozent': BlutBedeutung(
    ist: 'Zellen des erworbenen Immunsystems; zuständig für die Abwehr von Virus- und Pilzinfektionen und für die Bildung von Antikörpern.',
    hoch: 'Bestimmte Infektionen (etwa Hepatitis), bösartige Bluterkrankungen (Leukämien) oder Lymphome, auch bestimmte Medikamente.',
    tief: 'Bestimmte Infektionen (z. B. Masern), Erkrankungen des Immunsystems (etwa HIV-Infektion) oder eine Kortisontherapie.',
    quelle: 'gesundheit.gv.at',
  ),
  'loeslicher_transferrinrezeptor': BlutBedeutung(
    ist: 'Zeigt den aktuellen Eisenbedarf der blutbildenden Zellen — anders als Ferritin, das die Speicher abbildet.',
    hoch: 'Steigt bei Eisenmangel, weil die blutbildenden Zellen mehr Rezeptoren ausbilden. Hilfreich, wenn Ferritin durch eine Entzündung verfälscht ist.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'magnesium': BlutBedeutung(
    ist: 'Einer der wichtigsten Mineralstoffe; vor allem in den Körperzellen, wichtig für Energiebereitstellung und Zellteilung.',
    hoch: 'Kann auf Nierenversagen oder Hormonerkrankungen wie Morbus Addison hindeuten.',
    tief: 'Geringe Zufuhr, Alkoholismus, Magen-Darm-Erkrankungen, Entwässerungsmedikamente, Diabetes, schwere Durchfälle, Erbrechen, Schilddrüsenunterfunktion.',
    quelle: 'gesundheit.gv.at',
  ),
  'masern_igg': BlutBedeutung(
    ist: 'Masern-Virus-Antikörper vom Typ IgG; dienen der Diagnose und der Bestimmung des Immunitätsstatus.',
    hoch: 'Deuten auf eine durchgemachte Masern-Infektion mit lebenslanger Immunität hin; ein Anstieg auf das Vierfache binnen zwei Wochen spricht für eine akute Infektion.',
    tief: 'Fehlende Immunität gegen Masern — eine Impfung ist angezeigt.',
    quelle: 'gesundheit.gv.at',
  ),
  'mch': BlutBedeutung(
    ist: 'Durchschnittlicher Hämoglobingehalt der roten Blutkörperchen.',
    hoch: 'Hinweis auf eine hyperchrome Anämie, etwa bei chronischem Alkoholmissbrauch.',
    tief: 'Hinweis auf eine hypochrome Anämie, typischerweise bei Eisenmangel.',
    quelle: 'gesundheit.gv.at',
  ),
  'mchc': BlutBedeutung(
    ist: 'Durchschnittliche Hämoglobin-Konzentration der roten Blutkörperchen. Für die Anämiediagnostik von untergeordneter Bedeutung — aussagekräftiger sind MCV und MCH.',
    quelle: 'gesundheit.gv.at',
  ),
  'mcv': BlutBedeutung(
    ist: 'Durchschnittliches Volumen der roten Blutkörperchen.',
    hoch: 'Hinweis auf eine makrozytäre Anämie, z. B. bei Vitamin-B12-Mangel oder chronischem Alkoholmissbrauch.',
    tief: 'Hinweis auf eine mikrozytäre Anämie, typischerweise bei Eisenmangel.',
    quelle: 'gesundheit.gv.at',
  ),
  'mpv': BlutBedeutung(
    ist: 'Durchschnittsvolumen der Blutplättchen.',
    hoch: 'Spricht bei niedriger Thrombozytenzahl eher für einen gesteigerten Verbrauch — der Körper bildet junge, größere Plättchen nach.',
    tief: 'Spricht bei niedriger Thrombozytenzahl eher für eine verminderte Bildung im Knochenmark.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'monozyten_absolut': BlutBedeutung(
    ist: 'Fresszellen bzw. Vorstufen von Fresszellen; sie wirken mit Granulozyten und Lymphozyten zusammen.',
    hoch: 'Bestimmte Infektionen (Tuberkulose, Syphilis), Leberzirrhose, Monozyten-Leukämie, Morbus Hodgkin, auch bestimmte Antibiotika.',
    tief: 'Bestimmte Knochenmark-Erkrankungen, beispielsweise aplastische Anämie.',
    quelle: 'gesundheit.gv.at',
  ),
  'monozyten_prozent': BlutBedeutung(
    ist: 'Fresszellen bzw. Vorstufen von Fresszellen; sie wirken mit Granulozyten und Lymphozyten zusammen.',
    hoch: 'Bestimmte Infektionen (Tuberkulose, Syphilis), Leberzirrhose, Monozyten-Leukämie, Morbus Hodgkin, auch bestimmte Antibiotika.',
    tief: 'Bestimmte Knochenmark-Erkrankungen, beispielsweise aplastische Anämie.',
    quelle: 'gesundheit.gv.at',
  ),
  'myelozyten': BlutBedeutung(
    ist: 'Vorläuferzellen der weißen Blutkörperchen, die normalerweise nur im Knochenmark vorkommen.',
    hoch: 'Ein Nachweis im Blut kann auf schwere Entzündungen, Leukämien oder eine Chemotherapie hinweisen.',
    tief: 'Das Fehlen im Blut ist der Normalzustand — Referenzwerte gibt es dafür nicht.',
    quelle: 'gesundheit.gv.at',
  ),
  'myoglobin': BlutBedeutung(
    ist: 'Roter Muskelfarbstoff in Skelett- und Herzmuskulatur; ermöglicht die Sauerstoffspeicherung im Muskel.',
    hoch: 'Schädigung von Muskelzellen — beim Herzinfarkt steigt der Wert rasch an; auch bei Skelettmuskelerkrankungen.',
    tief: 'Ein normaler Wert 6 bis 10 Stunden nach Beschwerdebeginn schließt einen Herzinfarkt mit hoher Sicherheit aus.',
    quelle: 'gesundheit.gv.at',
  ),
  'natrium': BlutBedeutung(
    ist: 'Natriumionen sind die wichtigsten positiv geladenen Elektrolyte außerhalb der Körperzellen; wichtig zur Beurteilung des Wasser- und Elektrolythaushalts.',
    hoch: 'Hypernatriämie — zu geringe Flüssigkeitszufuhr, übermäßiger Flüssigkeitsverlust (Schwitzen, Durchfall) oder zu große Natriumzufuhr.',
    tief: 'Hyponatriämie — zu große Flüssigkeitszufuhr ohne Natrium, gestörte Flüssigkeitsausscheidung oder Elektrolytverlust (Erbrechen).',
    quelle: 'gesundheit.gv.at',
  ),
  'urin_natrium': BlutBedeutung(
    ist: 'Natrium im Harn; zeigt, wie viel Natrium die Niere ausscheidet.',
    hoch: 'Hohe Kochsalzzufuhr oder vermehrte Ausscheidung, etwa unter entwässernden Medikamenten.',
    tief: 'Der Körper hält Natrium zurück — etwa bei Flüssigkeitsmangel oder verminderter Nierendurchblutung.',
    quelle: 'gesundheit.gv.at (Harnwerte) + IMD Labor Berlin-Potsdam (Referenzbereiche Harn)',
  ),
  'neutrophile_absolut': BlutBedeutung(
    ist: 'Größter Anteil der weißen Blutkörperchen; Hauptaufgabe ist die Abwehr von Krankheitserregern.',
    hoch: 'Neutrophilie — akute Infektionen (z. B. Blinddarm- oder Lungenentzündung), Stress oder Leukämie.',
    tief: 'Neutropenie — Knochenmark-Schädigungen, bestimmte Infektionen (Tuberkulose, Typhus) oder Medikamente.',
    quelle: 'gesundheit.gv.at',
  ),
  'neutrophile_prozent': BlutBedeutung(
    ist: 'Größter Anteil der weißen Blutkörperchen; Hauptaufgabe ist die Abwehr von Krankheitserregern.',
    hoch: 'Neutrophilie — akute Infektionen (z. B. Blinddarm- oder Lungenentzündung), Stress oder Leukämie.',
    tief: 'Neutropenie — Knochenmark-Schädigungen, bestimmte Infektionen (Tuberkulose, Typhus) oder Medikamente.',
    quelle: 'gesundheit.gv.at',
  ),
  'urin_nitrit': BlutBedeutung(
    ist: 'Nitrit im Harn; entsteht, wenn Bakterien Nitrat umwandeln.',
    hoch: 'Ein positives Ergebnis ist ein Hinweis auf einen bakteriellen Harnwegsinfekt.',
    quelle: 'gesundheit.gv.at',
  ),
  'non_hdl': BlutBedeutung(
    ist: 'Gesamtcholesterin minus HDL — fasst alle nicht-schützenden Cholesterinanteile zusammen.',
    hoch: 'Gilt als Risikofaktor für Arterienverkalkung; wird oft statt LDL beurteilt, wenn die Triglyceride hoch sind.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'nse': BlutBedeutung(
    ist: 'Stoffwechselenzym in Zellen des Nervensystems und in neuroendokrinen Zellen; wird als Tumormarker eingesetzt.',
    hoch: 'Gutartige Erkrankungen wie Bronchitis, Lungenentzündung, Gehirn- oder Nierenerkrankungen; ebenso bösartige Tumore wie das kleinzellige Bronchialkarzinom.',
    quelle: 'gesundheit.gv.at',
  ),
  'nt_pro_bnp': BlutBedeutung(
    ist: 'Prohormonfragment aus der Gruppe der natriuretischen Peptide; im Herzen gebildete Hormone, die die Nieren zur Flüssigkeitsausscheidung anregen.',
    hoch: 'Hinweis auf eine Herzmuskelschwäche — je ausgeprägter die Herzinsuffizienz, desto höher der Wert.',
    tief: 'Ein normaler Wert schließt eine Herzinsuffizienz mit hoher Wahrscheinlichkeit aus.',
    quelle: 'gesundheit.gv.at',
  ),
  'osmolalitaet': BlutBedeutung(
    ist: 'Maß für die Gesamtzahl gelöster Teilchen im Blut; zentrale Größe des Wasser- und Salzhaushalts.',
    hoch: 'Flüssigkeitsmangel, zu hohes Natrium oder stark erhöhter Blutzucker.',
    tief: 'Zu viel Wasser im Verhältnis zu den gelösten Teilchen, etwa bei zu niedrigem Natrium.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'osteocalcin': BlutBedeutung(
    ist: 'Eiweißstoff im Knochengewebe; Messgröße für die Aktivität der Knochenneubildung.',
    hoch: 'Nach Knochenbrüchen im Heilungsverlauf normal; krankhaft bei Knochentumoren, Knochenmetastasen oder Osteoporose mit gesteigertem Knochenstoffwechsel.',
    tief: 'Zum Beispiel unter einer Therapie mit Kortison.',
    quelle: 'gesundheit.gv.at',
  ),
  'elastase_1': BlutBedeutung(
    ist: 'Verdauungsenzym der Bauchspeicheldrüse; wird im Stuhl gemessen.',
    tief: 'Ein niedriger Wert spricht für eine verminderte Leistung der Bauchspeicheldrüse (exokrine Pankreasinsuffizienz).',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'parathormon': BlutBedeutung(
    ist: 'Hormon der Nebenschilddrüsen; es regelt den Kalziumstoffwechsel des Körpers.',
    hoch: 'Ein Überschuss wird als Hyperparathyreoidismus bezeichnet.',
    tief: 'Ein Mangel wird als Hypoparathyreoidismus bezeichnet.',
    quelle: 'gesundheit.gv.at',
  ),
  'ptt': BlutBedeutung(
    ist: 'Aktivierte partielle Thromboplastinzeit — Labortest zur Überprüfung, ob das Blut normal gerinnt.',
    hoch: 'Behandlung mit Heparin oder Vitamin-K-Antagonisten, Vitamin-K-Mangel, Gerinnungsstörungen wie Hämophilie, Autoimmunerkrankungen mit Lupus-Antikoagulans.',
    quelle: 'gesundheit.gv.at',
  ),
  'ph_wert': BlutBedeutung(
    ist: 'Der pH-Wert des Blutes aus der Blutgasanalyse; er spiegelt die Wasserstoffionen-Konzentration wider.',
    hoch: 'Alkalose — etwa durch übermäßiges Atmen (Hyperventilation) oder Säureverlust, z. B. bei Erbrechen von Magensaft.',
    tief: 'Azidose — etwa durch Lungenerkrankungen mit verminderter Atemleistung oder Nierenversagen.',
    quelle: 'gesundheit.gv.at',
  ),
  'urin_ph': BlutBedeutung(
    ist: 'pH-Wert des Harns; dient der Beurteilung des Harnsteinrisikos und des Säure-Basen-Haushalts.',
    hoch: 'Kann auf Harnwegsinfekte oder Stoffwechselstörungen hindeuten.',
    tief: 'Kann auf Stoffwechselstörungen hindeuten und begünstigt bestimmte Harnsteine.',
    quelle: 'gesundheit.gv.at',
  ),
  'phosphat': BlutBedeutung(
    ist: 'Neben Calcium der wichtigste Mineralstoff des Körpers; wichtig für den Aufbau von Knochen und Zähnen.',
    hoch: 'Chronische Niereninsuffizienz, Mangel an Parathormon (z. B. nach Schilddrüsenoperationen), Knochentumore oder Knochenmetastasen.',
    tief: 'Fehlernährung oder Magen-Darm-Erkrankungen, hormonelle Störungen der Calcium-Phosphat-Regulation, Vitamin-D-Mangel, bösartige Tumore.',
    quelle: 'gesundheit.gv.at',
  ),
  'urin_phosphat': BlutBedeutung(
    ist: 'Phosphat im Harn; ergänzt Calcium bei der Beurteilung des Knochen- und Mineralstoffwechsels.',
    hoch: 'Vermehrte Ausscheidung, etwa bei Überfunktion der Nebenschilddrüse.',
    tief: 'Verminderte Ausscheidung, etwa bei Phosphatmangel in der Nahrung.',
    quelle: 'gesundheit.gv.at (Harnwerte) + IMD Labor Berlin-Potsdam (Referenzbereiche Harn)',
  ),
  'procalcitonin': BlutBedeutung(
    ist: 'Vorstufe des Schilddrüsenhormons Calcitonin; im Blut erhöht bei schweren Entzündungsreaktionen.',
    hoch: 'Sehr stark erhöht fast ausnahmslos Zeichen einer Sepsis; stark erhöht spricht mit hoher Wahrscheinlichkeit für eine schwere bakterielle Infektion.',
    quelle: 'gesundheit.gv.at',
  ),
  'progesteron': BlutBedeutung(
    ist: 'Weibliches Geschlechtshormon; in der zweiten Zyklushälfte im Eierstock, während der Schwangerschaft von der Plazenta gebildet.',
    hoch: 'Schwangerschaft, progesteronhaltige Medikamente, hormonproduzierender Tumor oder adrenogenitales Syndrom.',
    tief: 'Gelbkörperschwäche, Erkrankungen der Eierstöcke, Störungen der Regulation, Erkrankungen des Hypothalamus, Postmenopause.',
    quelle: 'gesundheit.gv.at',
  ),
  'prolaktin': BlutBedeutung(
    ist: 'Hormon der Hirnanhangsdrüse; fördert bei Frauen Brustdrüsenwachstum und Muttermilchbildung.',
    hoch: 'Prolaktinom, Mangel an hemmenden Faktoren wie Dopamin, bestimmte Medikamente, Schilddrüsenunterfunktion, Stress und körperliche Belastung.',
    tief: 'Erkrankungen oder Funktionsstörungen der Hirnanhangsdrüse; Behandlung mit prolaktinsenkenden Stoffen.',
    quelle: 'gesundheit.gv.at',
  ),
  'promyelozyten': BlutBedeutung(
    ist: 'Vorläuferzellen der weißen Blutkörperchen, normalerweise nur im Knochenmark.',
    hoch: 'Ein Auftreten im Blut deutet auf schwere Entzündungen, Leukämien oder eine Chemotherapie hin.',
    tief: 'Das Fehlen im Blut ist der Normalzustand.',
    quelle: 'gesundheit.gv.at',
  ),
  'psa': BlutBedeutung(
    ist: 'Eiweißstoff, der hauptsächlich in der Vorsteherdrüse (Prostata) gebildet wird.',
    hoch: 'Gutartige Ursachen wie Prostataentzündung oder gutartige Vergrößerung, auch nach einer rektalen Untersuchung; ebenso ein Prostatakarzinom.',
    quelle: 'gesundheit.gv.at',
  ),
  'quick': BlutBedeutung(
    ist: 'Prothrombinzeit — prüft, ob das Blut normal gerinnt, insbesondere die Vitamin-K-abhängigen Gerinnungsfaktoren.',
    tief: 'Lebererkrankungen, Vitamin-K-Mangel oder Behandlung mit einem Vitamin-K-Gegenspieler (z. B. Marcoumar®, Sintrom®).',
    quelle: 'gesundheit.gv.at',
  ),
  'renin': BlutBedeutung(
    ist: 'Enzym, das in der Niere gebildet wird und den Blutdruck über das Renin-Angiotensin-Aldosteron-System steuert.',
    hoch: 'Reninbildende Tumore oder das Bartter-Syndrom; auch bei sekundärem Hyperaldosteronismus.',
    tief: 'Meist beim primären Hyperaldosteronismus.',
    quelle: 'flexikon.doccheck.com (Renin)',
  ),
  'retikulozyten': BlutBedeutung(
    ist: 'Junge, frisch im Knochenmark gebildete rote Blutkörperchen; zeigen, ob das Knochenmark ausreichend neue Erythrozyten bildet.',
    hoch: 'Nach Blutungen oder bei vermehrtem Abbau roter Blutkörperchen (Hämolyse).',
    tief: 'Störung der Blutbildung im Knochenmark — Eisenmangel, Vitaminmangel oder Leukämie.',
    quelle: 'gesundheit.gv.at',
  ),
  'rhesusfaktor': BlutBedeutung(
    ist: 'Das D-Merkmal des Rhesus-Systems, des zweitwichtigsten Blutgruppensystems: vorhanden heißt Rhesus-positiv, nicht vorhanden Rhesus-negativ.',
    quelle: 'gesundheit.gv.at',
  ),
  'rheumafaktor': BlutBedeutung(
    ist: 'Autoantikörper, der gegen körpereigene Antikörper gerichtet ist.',
    hoch: 'Hinweis auf rheumatoide Arthritis — dort in etwa 80 Prozent der Fälle erhöht; auch bei anderen Autoimmunerkrankungen wie Lupus erythematodes oder Sjögren-Syndrom.',
    tief: 'Ein normaler Wert schließt eine rheumatoide Arthritis NICHT aus — etwa 20 Prozent der Erkrankten haben normale Werte.',
    quelle: 'gesundheit.gv.at',
  ),
  'roeteln_igg': BlutBedeutung(
    ist: 'Röteln-Virus-Antikörper; dienen der Diagnose einer Rötelninfektion und der Bestimmung des Immunitätsstatus.',
    hoch: 'Ein ausreichender Titer spricht für Impfschutz. Ein Anstieg auf das Vierfache binnen 10 bis 14 Tagen spricht für eine akute Infektion.',
    tief: 'Kein ausreichender Impfschutz; ein Grenzbereich erfordert eine Auffrischungsimpfung.',
    quelle: 'gesundheit.gv.at',
  ),
  'po2': BlutBedeutung(
    ist: 'Menge des im arteriellen Blut gelösten Sauerstoffs; Kennzahl für die Fähigkeit der Lunge, das Blut mit Sauerstoff anzureichern.',
    hoch: 'Bei Erwachsenen ohne Bedeutung; bei Neugeborenen kann ein zu hoher Wert die Lunge schädigen.',
    tief: 'Störung der Lungenfunktion. Ein Absinken unter 40 mmHg kann zu Bewusstlosigkeit führen.',
    quelle: 'gesundheit.gv.at',
  ),
  'sauerstoffsaettigung': BlutBedeutung(
    ist: 'Gibt an, zu wie viel Prozent der rote Blutfarbstoff mit Sauerstoff angereichert ist.',
    hoch: 'Bei Erwachsenen ohne Bedeutung.',
    tief: 'Störung der Lungenfunktion — ungenügende Anreicherung des Blutes mit Sauerstoff.',
    quelle: 'gesundheit.gv.at',
  ),
  'scc': BlutBedeutung(
    ist: 'Eiweißstoff aus Zellen des Plattenepithels; wird als Tumormarker gemessen.',
    hoch: 'Gutartige Erkrankungen in Kopf-Hals-Bereich, Lunge, Speiseröhre, Gebärmutterhals oder Haut; ebenso Tumorerkrankungen wie Gebärmutterhals-, Lungen-, Kehlkopf- oder Speiseröhrenkrebs.',
    quelle: 'gesundheit.gv.at',
  ),
  'segmentkernige': BlutBedeutung(
    ist: 'Reife Formen der neutrophilen Granulozyten mit gegliedertem Zellkern.',
    hoch: 'Bei bakteriellen Infektionen und Entzündungen.',
    tief: 'Bei Knochenmarkschädigung, bestimmten Infektionen oder unter bestimmten Medikamenten.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'selen': BlutBedeutung(
    ist: 'Spurenelement; Bestandteil selenabhängiger Enzyme wie der Glutathionperoxidase und der Dejodase.',
    hoch: 'Meist Folge einer Zufuhr über Nahrungsergänzungsmittel.',
    tief: 'Die selenabhängigen Enzyme arbeiten schlechter; unter anderem kann die Umwandlung der Schilddrüsenhormone beeinträchtigt sein.',
    quelle: 'flexikon.doccheck.com (Selen, Selenmangel)',
  ),
  'elektrophorese': BlutBedeutung(
    ist: 'Trennt die Bluteiweiße elektrisch in ihre Gruppen auf: Albumin sowie Alpha-1-, Alpha-2-, Beta- und Gamma-Globuline.',
    hoch: 'Die Verteilung der Fraktionen zeigt Muster, die auf Entzündungen, Lebererkrankungen, Eiweißverlust oder eine monoklonale Vermehrung hinweisen können.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'shbg': BlutBedeutung(
    ist: 'Von der Leber gebildeter Bluteiweißstoff; er bindet, speichert und transportiert Testosteron und Östrogene.',
    hoch: 'Lebererkrankungen, Hoden- und Ovarialtumore, Schilddrüsenüberfunktion, Antibabypille oder Hormonersatztherapie, Schwangerschaft, höheres Lebensalter.',
    tief: 'Fettleibigkeit, Schilddrüsenunterfunktion, Nierenerkrankungen mit Eiweißverlust, Lebererkrankungen oder Eiweißmangelernährung.',
    quelle: 'gesundheit.gv.at',
  ),
  'urin_spez_gewicht': BlutBedeutung(
    ist: 'Bewertet die Konzentrationsfähigkeit der Nieren.',
    hoch: 'Konzentrierter Harn, etwa bei geringer Trinkmenge.',
    tief: 'Kann auf eine Nierenfunktionsstörung hinweisen.',
    quelle: 'gesundheit.gv.at',
  ),
  'stabkernige': BlutBedeutung(
    ist: 'Junge Formen der neutrophilen Granulozyten mit stabförmigem Zellkern.',
    hoch: 'Bei Entzündungsprozessen und Infektionskrankheiten — die sogenannte Linksverschiebung.',
    quelle: 'gesundheit.gv.at',
  ),
  'testosteron': BlutBedeutung(
    ist: 'Das wichtigste männliche Sexualhormon; bei Männern in den Hoden, bei Frauen in geringen Mengen in Eierstöcken und Nebennierenrinde gebildet.',
    hoch: 'Bei Männern Testosteronzufuhr oder ein hormonproduzierender Tumor; bei Frauen Vermännlichungserkrankungen oder ein hormonproduzierender Tumor.',
    tief: 'Bei Männern Hypogonadismus oder Hodenerkrankungen; bei Frauen Erkrankungen der Eierstöcke oder der Nebennierenrinde.',
    quelle: 'gesundheit.gv.at',
  ),
  'tetanus_igg': BlutBedeutung(
    ist: 'Antitoxin gegen Tetanus; zeigt den Impfschutz gegen Wundstarrkrampf.',
    hoch: 'Ausreichender Impfschutz.',
    tief: 'Kein ausreichender Schutz — eine Auffrischimpfung ist angezeigt.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'med_theophyllin': BlutBedeutung(
    ist: 'Medikament zur Erweiterung der Bronchien bei Asthma und COPD. ⚠️ Geringe therapeutische Breite.',
    hoch: 'Über dem therapeutischen Bereich steigt die Gefahr von Nebenwirkungen bis zur Vergiftung.',
    tief: 'Unter dem therapeutischen Bereich wirkt das Medikament möglicherweise nicht ausreichend.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'thrombinzeit': BlutBedeutung(
    ist: 'Misst die Umwandlung von Fibrinogen zu Fibrin, den letzten Schritt der Gerinnung.',
    hoch: 'Verlängert bei Fibrinogenmangel sowie unter Heparin oder anderen gerinnungshemmenden Stoffen.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'thrombozyten': BlutBedeutung(
    ist: 'Blutplättchen; sie werden im Knochenmark gebildet und sind für die Blutgerinnung notwendig.',
    hoch: 'Nach körperlicher Anstrengung, Stress oder Operationen, bei Infektionen und Entzündungen, nach Milzentfernung.',
    tief: 'Verminderte Bildung im Knochenmark oder verkürzte Lebensdauer der Blutplättchen; kann zu Blutungsneigung führen.',
    quelle: 'gesundheit.gv.at',
  ),
  'thyreoglobulin': BlutBedeutung(
    ist: 'Eiweiß, das in der Schilddrüse gebildet und dort als Speicherform der Hormone abgelegt wird.',
    hoch: 'Bei Schilddrüsenerkrankungen erhöht; nach vollständiger Entfernung der Schilddrüse dient es als Verlaufsmarker.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'tg_ak': BlutBedeutung(
    ist: 'Antikörper gegen Thyreoglobulin, den Speicherstoff der Schilddrüsenhormone.',
    hoch: 'Erhöhte Werte finden sich vor allem bei Autoimmunerkrankungen der Schilddrüse wie Hashimoto-Thyreoiditis und Morbus Basedow.',
    quelle: 'de.wikipedia.org (Thyreoglobulin-Antikörper)',
  ),
  'toxoplasmose_igg': BlutBedeutung(
    ist: 'Antikörper vom Typ IgG gegen Toxoplasma gondii; dienen der Diagnose und der Bestimmung des Immunitätsstatus.',
    hoch: 'Deuten auf eine frühere oder aktuelle Infektion hin; sie werden erst in späteren Phasen gebildet und bleiben meist lebenslang nachweisbar.',
    tief: 'Keine Immunität gegen den Parasiten — bislang keine Infektion. In der Schwangerschaft besonders relevant.',
    quelle: 'gesundheit.gv.at',
  ),
  'tpo_ak': BlutBedeutung(
    ist: 'Antikörper gegen die Thyreoperoxidase, ein Enzym der Schilddrüse.',
    hoch: 'Erhöhte Werte finden sich bei etwa 90 Prozent der Menschen mit Hashimoto-Thyreoiditis und bei etwa 70 Prozent mit Morbus Basedow.',
    tief: 'Spricht gegen eine autoimmune Schilddrüsenerkrankung, schließt sie aber nicht sicher aus.',
    quelle: 'de.wikipedia.org (Thyreoperoxidase-Antikörper)',
  ),
  'transferrin': BlutBedeutung(
    ist: 'Eiweißstoff zum Transport von Eisen im Blut.',
    hoch: 'Eisenmangel (z. B. durch Blutungen), erhöhter Eisenbedarf wie in der Schwangerschaft oder bei Wachstumsschüben.',
    tief: 'Vermehrte Eisenaufnahme (Hämochromatose), Infektionen, Tumorerkrankungen, Leberzirrhose, Eiweißmangel oder -verlust.',
    quelle: 'gesundheit.gv.at',
  ),
  'transferrinsaettigung': BlutBedeutung(
    ist: 'Aus Eisen und Transferrin berechnet; beziffert die Menge an Eisenmolekülen pro Molekül Transferrin.',
    hoch: 'Eisenüberladung, übermäßige Bluttransfusionen, bestimmte Lebererkrankungen, Hämochromatose.',
    tief: 'Eisenmangel bis hin zur Eisenmangelanämie; Störung der Blutbildung.',
    quelle: 'gesundheit.gv.at',
  ),
  'transglutaminase_ak': BlutBedeutung(
    ist: 'Autoantikörper gegen Gewebs-Transglutaminase; Suchtest bei Verdacht auf Zöliakie.',
    hoch: 'Deutet auf Zöliakie hin — eine Unverträglichkeit gegen Gluten mit Entzündungsreaktionen im Darm.',
    tief: 'Ein negatives Ergebnis spricht gegen diese Autoimmunerkrankung.',
    quelle: 'gesundheit.gv.at',
  ),
  'triglyceride': BlutBedeutung(
    ist: 'Neutralfette — wichtige Energiespeicher im Körper.',
    hoch: 'Angeborene Fettstoffwechselerkrankungen, Diabetes mellitus, Adipositas, Alkoholismus, Schilddrüsenunterfunktion. Erhöht das Atherosklerose-Risiko.',
    tief: 'Eine Verminderung ist ohne Bedeutung.',
    quelle: 'gesundheit.gv.at',
  ),
  'troponin': BlutBedeutung(
    ist: 'Eiweißbausteine aus den Muskelzellen der Herzmuskulatur; normalerweise im Blut nicht nachweisbar.',
    hoch: 'Wichtiger Hinweis auf einen Herzmuskelschaden, insbesondere auf einen Herzinfarkt.',
    tief: 'Ein wiederholt normaler Wert schließt einen Herzinfarkt mit hoher Wahrscheinlichkeit aus.',
    quelle: 'gesundheit.gv.at',
  ),
  'tsh': BlutBedeutung(
    ist: 'Hormon der Hirnanhangsdrüse; es reguliert die Bildung der Schilddrüsenhormone.',
    hoch: 'Deutet auf eine Schilddrüsenunterfunktion hin — die Hirnanhangsdrüse produziert vermehrt TSH, um die unzureichende Hormonbildung anzuregen.',
    tief: 'Weist auf eine Schilddrüsenüberfunktion hin — bei zu viel Schilddrüsenhormon bildet die Hirnanhangsdrüse weniger TSH.',
    quelle: 'gesundheit.gv.at',
  ),
  'trak': BlutBedeutung(
    ist: 'Antikörper gegen den TSH-Rezeptor der Schilddrüse (TRAK).',
    hoch: 'Beweisend für einen Morbus Basedow. Hohe Werte in Remission sprechen für ein hohes Rückfallrisiko.',
    tief: 'Negative Antikörper schließen einen Morbus Basedow nicht mit Sicherheit aus.',
    quelle: 'de.wikipedia.org (Schilddrüsendiagnostik)',
  ),
  'urin_urobilinogen': BlutBedeutung(
    ist: 'Urobilinogen im Harn — ein Abbauprodukt des Bilirubins.',
    hoch: 'Unter anderem bei bestimmten Formen der Gelbsucht nachweisbar.',
    quelle: 'gesundheit.gv.at',
  ),
  'med_vancomycin': BlutBedeutung(
    ist: 'Antibiotikum gegen bestimmte grampositive Bakterien; der Spiegel wird kontrolliert, weil zu hohe Werte Nieren und Gehör schädigen können.',
    hoch: 'Über dem therapeutischen Bereich steigt die Gefahr von Nebenwirkungen bis zur Vergiftung.',
    tief: 'Unter dem therapeutischen Bereich wirkt das Medikament möglicherweise nicht ausreichend.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'varizellen_igg': BlutBedeutung(
    ist: 'Antikörper vom Typ IgG gegen das Varizella-Zoster-Virus (Windpocken, Gürtelrose).',
    hoch: 'Zeigt eine frühere oder aktuelle Infektion an; die Antikörper bleiben meist lebenslang nachweisbar und sprechen für Immunität.',
    tief: 'Keine Immunität gegen VZV nachweisbar; eine Erkrankung ist damit nicht mit Sicherheit ausgeschlossen.',
    quelle: 'gesundheit.gv.at',
  ),
  'vitamin_a': BlutBedeutung(
    ist: 'Fettlösliches Vitamin, vor allem in Innereien und bestimmten Gemüsesorten (z. B. Karotten).',
    hoch: 'Überdosierung durch Vitaminpräparate, etwa bei Therapien gegen Akne oder Schuppenflechte.',
    tief: 'Erkrankungen des Magen-Darm-Traktes, Leber- oder Bauchspeicheldrüsenerkrankungen, Nierenerkrankungen mit Eiweißverlust.',
    quelle: 'gesundheit.gv.at',
  ),
  'vitamin_b1': BlutBedeutung(
    ist: 'Wasserlösliches Vitamin, wichtig für den Energiestoffwechsel der Zellen. Der Körper speichert nur wenig — die Vorräte reichen etwa zwei Wochen.',
    hoch: 'Meist Folge einer Zufuhr über Präparate.',
    tief: 'Ein länger bestehender Mangel führt zur Beriberi; häufig bei chronischem Alkoholkonsum und Mangelernährung.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'vitamin_b12': BlutBedeutung(
    ist: 'Wasserlösliches Vitamin aus Fleisch, Innereien, Eiern und Milchprodukten.',
    hoch: 'Lebererkrankungen, Leukämien.',
    tief: 'Fehlernährung (auch streng vegane Ernährung), Magenerkrankungen oder -operationen (Mangel an Intrinsic Factor), Darmerkrankungen wie Morbus Crohn. Ein Mangel führt zu Anämie.',
    quelle: 'gesundheit.gv.at',
  ),
  'vitamin_b6': BlutBedeutung(
    ist: 'Wasserlösliches Vitamin, beteiligt am Eiweißstoffwechsel und an der Bildung von Botenstoffen.',
    hoch: 'Eine dauerhaft zu hohe Zufuhr über Präparate kann Nerven schädigen.',
    tief: 'Kann zu Blutbildveränderungen, Hautveränderungen und Nervenstörungen führen.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'vitamin_c': BlutBedeutung(
    ist: 'Wasserlösliches Vitamin, vor allem in Zitrusfrüchten und Gemüse wie Paprika.',
    hoch: 'Überdosierung durch Vitaminpräparate.',
    tief: 'Erkrankungen des Magen-Darm-Traktes oder verminderte Zufuhr; ein schwerer Mangel führt zu Skorbut mit Blutungen und Blutbildstörungen.',
    quelle: 'gesundheit.gv.at',
  ),
  'vitamin_d3': BlutBedeutung(
    ist: '25-Hydroxy-Vitamin-D ist die Vorstufe des biologisch aktiven Vitamin D; wird gemessen, um einen Mangel zu beurteilen.',
    hoch: 'Überdosierung von Vitaminpräparaten (Hypervitaminose).',
    tief: 'Vitamin-D-Mangel oder gestörter Vitamin-D-Stoffwechsel; kann zu Rachitis oder Osteomalazie führen — Erkrankungen mit gestörter Skelettmineralisation.',
    quelle: 'gesundheit.gv.at',
  ),
  'vitamin_e': BlutBedeutung(
    ist: 'Fettlösliches Vitamin; wirkt als Schutzstoff gegen die Schädigung von Zellmembranen.',
    hoch: 'Meist Folge einer Zufuhr über Präparate.',
    tief: 'Selten; vor allem bei Fettverdauungsstörungen. Kann Nerven- und Muskelstörungen verursachen.',
    quelle: 'flexikon.doccheck.com / de.wikipedia.org',
  ),
  'zink': BlutBedeutung(
    ist: 'Spurenelement, das für Wundheilung, Immunabwehr, Wachstum und Fruchtbarkeit gebraucht wird.',
    hoch: 'Meist Folge einer Zufuhr über Nahrungsergänzungsmittel.',
    tief: 'Kann zu Wundheilungsstörungen, Immunschwäche sowie Veränderungen an Haut und Nägeln führen. ⚠️ Ein Mangel lässt sich durch den Serumwert weder beweisen noch ausschließen.',
    quelle: 'flexikon.doccheck.com (Zink, Zinkmangel)',
  ),
};
