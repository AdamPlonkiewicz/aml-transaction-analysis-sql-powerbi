-- =====================================================
-- Eksploracja typologii: Structuring, Smurfing, Fan_In, Cash_Withdrawal
--
-- Cel:
-- Rozpoznanie, jak autorzy zbioru SAML-D zamodelowali trzy
-- typologie, zanim powstaną reguły wykrywania.
-- Pełne definicje typologii autorów nie są publicznie dostępne,
-- dlatego kształt każdej typologii odczytujemy z danych.
--
-- Definicje w literaturze AML:
-- - Structuring: jedna osoba dzieli gotówkę na wpłaty poniżej
--   progu raportowego, aby uniknąć zgłoszenia (faza lokowania).
-- - Smurfing: wiele osób ("smerfów") wprowadza małe kwoty
--   do jednego kolektora; próg nie jest osią definicji (faza lokowania).
-- - Fan_In: wiele kont przelewa środki do jednego odbiorcy (etap integracji/maskowania).
-- - Cash_Withdrawal: wypłata gotówki z konta, na które wcześniej
--   wpłynęły środki z prania (etap integracji/wyjścia z systemu).
--
-- Hipoteza do weryfikacji:
-- Etykiety Structuring i Smurfing w SAML-D są zamienione
-- względem literatury (etykieta Structuring odpowiada
-- smurfingowi, etykieta Smurfing - structuringowi).
--
-- Etykieta laundering_type służy tu wyłącznie do rozpoznania
-- kształtu przepływu (kto, do kogo, jakim kanałem, w jakim czasie,
-- jakimi kwotami).

-- =====================================================
-- A. Profile typologii (odbiorcy / nadawcy, kanały, kwoty)
-- =====================================================

-- A1. Profil odbiorców transakcji Structuring
SELECT
    receiver_id,
    COUNT(*) AS tx_count,
    COUNT(DISTINCT sender_id) AS unique_senders,
    COUNT(DISTINCT payment_type) AS payment_t_count,
    SUM(amount) AS total_amount,
    MIN(amount) AS min_amount,
    MAX(amount) AS max_amount,
    ROUND(AVG(amount),2) AS avg_amount,
    ROUND(STDDEV(amount),2) AS amount_stddev,
    MAX(transaction_datetime) - MIN(transaction_datetime) AS activity_duration,
    COUNT(DISTINCT DATE_TRUNC('month', transaction_datetime)) AS active_months
FROM aml_transactions_clean
WHERE laundering_type = 'Structuring'
GROUP BY receiver_id
ORDER BY tx_count DESC;

-- Liczba transakcji jest równa liczbie nadawców w każdym przypadku:
-- każdy nadawca wysyła do danego odbiorcy tylko raz.
-- Schemat "wielu nadawców -> jeden odbiorca" odpowiada smurfingowi
-- w literaturze, a nie podręcznikowemu structuringowi.
-- Rozpiętość kwot (ok. 2k-12,5k; średnio 3k-9k) wskazuje na brak
-- stałego progu kwotowego, co znów przemawia w stronę smurfingu
-- gdzie obserwuje się masowe wprowadzanie gotówki przez wiele osób 
-- niskimi kwotami.
-- Wiele typów płatności (1-5), typ zależy od lokalizacji odbiorcy: UK 4-5 kanałów,
-- zagraniczni 1-3. Typowy Structuring posiada jeden typ - wpłaty gotówkowe. 
-- Aktywność trwa od kilku dni do ok. 10 miesięcy (1-5 różnych miesięcy).
SELECT
    payment_type,
    COUNT(*)                    AS tx_count,
    COUNT(DISTINCT receiver_id) AS receiver_count
FROM aml_transactions_clean
WHERE laundering_type = 'Structuring'
GROUP BY payment_type
ORDER BY tx_count DESC;
-- Wynik: brak wpłat gotówkowych. Środki wpływają 5 kanałami
-- bezgotówkowymi; najczęściej Cross-border (723 z 1870, ok. 39%,
-- u 71 z 75 odbiorców), pozostałe kanały po ok. 15%.

-- A2. Profil odbiorców transakcji Smurfing
SELECT
    receiver_id,
    COUNT(*) AS tx_count,
    COUNT(DISTINCT sender_id) AS unique_senders,
    COUNT(DISTINCT payment_type) AS payment_t_count,
    SUM(amount) AS total_amount,
    MIN(amount) AS min_amount,
    MAX(amount) AS max_amount,
    ROUND(AVG(amount),2) AS avg_amount,
    ROUND(STDDEV(amount),2) AS amount_stddev,
    MAX(transaction_datetime) - MIN(transaction_datetime) AS activity_duration,
    COUNT(DISTINCT DATE_TRUNC('month', transaction_datetime)) AS active_months
FROM aml_transactions_clean
WHERE laundering_type = 'Smurfing'
GROUP BY receiver_id
ORDER BY tx_count DESC;

-- Każdy odbiorca ma dokładnie jednego nadawcę i jeden typ płatności.
-- Kwoty pojedynczych wpłat 1k-7k (średnio ok. 2,5-3,5k), daleko poniżej
-- progu raportowego; suma serii przekracza próg (nawet serie
-- jednomiesięczne: 11k-31k). Odbiorcy prawie wyłącznie w UK.
-- Transakcje występują seriami ok. 7-9 dni, powtarzanymi do 4 miesięcy.
-- Wniosek: schemat "jedna osoba -> jedno konto, wiele małych wpłat
-- poniżej progu" odpowiada structuringowi w literaturze.
-- Potwierdza to hipotezę o zamianie etykiet Structuring i Smurfing.

SELECT
    payment_type,
    COUNT(*)                    AS tx_count,
    COUNT(DISTINCT receiver_id) AS receiver_count
FROM aml_transactions_clean
WHERE laundering_type = 'Smurfing'
GROUP BY payment_type;
-- Potwierdzono jeden typ płatności - "Cash Deposit"

WITH senders AS (
	SELECT DISTINCT sender_id
	FROM aml_transactions_clean
	WHERE laundering_type = 'Smurfing'
)
SELECT 
	s.sender_id,
	COUNT(DISTINCT atc.receiver_id) AS receiver_count,
	COUNT(*) AS tx_count
FROM aml_transactions_clean atc
JOIN senders s ON atc.sender_id = s.sender_id 
GROUP BY s.sender_id 
ORDER BY receiver_count DESC;

-- Wynik: 63 różnych nadawców dla 63 odbiorców (każdy odbiorca ma
-- własnego wpłacającego). Nadawcy to zwykłe konta z normalną
-- aktywnością (3-32 odbiorców, 7-387 transakcji w okresie),
-- a nie techniczne "konto gotówki" generatora.
-- Wniosek: jedna osoba wpłaca gotówkę seriami małych kwot
-- na jedno konto - wzorzec structuringu z literatury.

-- A3. Profil odbiorców transakcji Fan-In
SELECT
    receiver_id,
    COUNT(*) AS tx_count,
    COUNT(DISTINCT sender_id) AS unique_senders,
    COUNT(DISTINCT payment_type) AS payment_t_count,
    SUM(amount) AS total_amount,
    MIN(amount) AS min_amount,
    MAX(amount) AS max_amount,
    ROUND(AVG(amount),2) AS avg_amount,
    ROUND(STDDEV(amount),2) AS amount_stddev,
    MAX(transaction_datetime) - MIN(transaction_datetime) AS activity_duration,
    COUNT(DISTINCT DATE_TRUNC('month', transaction_datetime)) AS active_months
FROM aml_transactions_clean
WHERE laundering_type = 'Fan_In'
GROUP BY receiver_id
ORDER BY tx_count DESC;

-- Wynik Fan_In: tak jak w etykiecie Structuring, każdy nadawca wysyła do
-- odbiorcy tylko raz (tx_count = unique_senders w każdym wierszu).
-- Różnice względem etykiety Structuring:
-- - mniej transakcji na odbiorcę (2-12 vs 7-47),
-- - jednorazowy zryw trwający do ok. 10 dni;
--   active_months = 2 wynika z przejścia przez granicę miesiąca,
-- - duża zmienność kwot: pojedyncze wpłaty do ok. 65k
--   (Structuring ok. do 12,5k),
-- - odbiorcy niemal wyłącznie w UK (1 z 40 poza UK).
-- Wniosek: typologie odróżnia wielkość i rozrzut kwot,
-- nie sam schemat "wielu nadawców -> jeden odbiorca".

SELECT 
	payment_type,
	COUNT(*) type_count,
	COUNT(DISTINCT receiver_id) AS receiver_count
FROM aml_transactions_clean 
WHERE laundering_type = 'Fan_In'
GROUP BY payment_type 
ORDER BY type_count DESC;


-- A4. Profil nadawców transakcji Cash_Withdrawal
SELECT
    sender_id,
    COUNT(*) AS tx_count,
    COUNT(DISTINCT receiver_id ) AS unique_receivers,
    COUNT(DISTINCT payment_type) AS payment_t_count,
    SUM(amount) AS total_amount,
    MIN(amount) AS min_amount,
    MAX(amount) AS max_amount,
    ROUND(AVG(amount),2) AS avg_amount,
    ROUND(STDDEV(amount),2) AS amount_stddev,
    MAX(transaction_datetime) - MIN(transaction_datetime) AS activity_duration,
    COUNT(DISTINCT DATE_TRUNC('month', transaction_datetime)) AS active_months
FROM aml_transactions_clean
WHERE laundering_type = 'Cash_Withdrawal'
GROUP BY sender_id
ORDER BY tx_count DESC;

SELECT
    payment_type,
    COUNT(*)                    AS tx_count,
    COUNT(DISTINCT receiver_id) AS receiver_count
FROM aml_transactions_clean
WHERE laundering_type = 'Cash_Withdrawal'
GROUP BY payment_type;
-- Wynik: wszystkie 1334 transakcje to Cash Withdrawal; 88 odbiorców
-- dla 88 nadawców - każde konto wypłaca do własnego, osobnego
-- odbiorcy (brak wspólnego technicznego konta "bankomatu").
-- Profil: każdy nadawca 1 odbiorca, wyłącznie UK, bardzo małe kwoty
-- ok. 15-350 GBP (wyraźny sufit ok. 350), średnio ok. 150;
-- suma na konto 0,3k-6,4k.
-- Wypłaty seriami: 4-10 transakcji w ciągu 3-6 dni,
-- u części kont powtarzane przez 2-4 miesiące.

-- =====================================================
-- B. Odstępy między transakcjami konta (wyznaczenie serii)
-- =====================================================
WITH tx AS (
	SELECT 
		laundering_type,
		CASE WHEN laundering_type = 'Cash_Withdrawal'
		THEN sender_id
		ELSE receiver_id
		END AS account_id,
		transaction_datetime
	FROM aml_transactions_clean 
	WHERE laundering_type IN ('Structuring', 'Smurfing', 'Fan_In', 'Cash_Withdrawal')
), gaps AS (
	SELECT 
		laundering_type,
		account_id,
		EXTRACT(EPOCH FROM
    	transaction_datetime - LAG(transaction_datetime)
        OVER (PARTITION BY laundering_type, account_id ORDER BY transaction_datetime)
) / 86400 AS gap_days
	FROM  tx
)
SELECT
	laundering_type,
    CASE
        WHEN gap_days IS NULL THEN 'first transaction'
        WHEN gap_days < 1  THEN '< 1 day'
        WHEN gap_days < 3  THEN '1-3 days'
        WHEN gap_days < 7  THEN '3-7 days'
        WHEN gap_days < 14 THEN '7-14 days'
        WHEN gap_days < 30 THEN '14-30 days'
        ELSE '30+ days'
    END AS gap_bucket,
    COUNT(*) AS tx_count
FROM gaps
GROUP BY gap_bucket,laundering_type
ORDER BY laundering_type, MIN(gap_days) NULLS FIRST;
-- Wynik: we wszystkich typologiach transakcje konta występują seriami.
-- Wewnątrz serii odstępy są krótkie (głównie < 3 dni); przedział
-- 7-14 dni jest praktycznie pusty (0-4 transakcje).
-- Liczba serii = pierwsza transakcja konta + odstępy > 14 dni:
-- Structuring ok. 220, Cash_Withdrawal ok. 195, Smurfing ok. 142.
-- Fan_In: brak odstępów > 7 dni, czyli jedna seria (zryw) na konto.
-- Wniosek: granica serii = przerwa > 14 dni.

-- =====================================================
-- C. Parametry serii (liczba transakcji, czas trwania, suma)
-- =====================================================
WITH tx AS (
	SELECT 
		laundering_type,
		amount,
		CASE WHEN laundering_type = 'Cash_Withdrawal'
		THEN sender_id
		ELSE receiver_id
		END AS account_id,
		transaction_datetime
	FROM aml_transactions_clean 
	WHERE laundering_type IN ('Structuring', 'Smurfing', 'Fan_In', 'Cash_Withdrawal')
), series AS (
    SELECT
        laundering_type,
        account_id,
        DATE_TRUNC('month', transaction_datetime) AS series_month,
        COUNT(*) AS series_tx,
        EXTRACT(EPOCH FROM MAX(transaction_datetime) - MIN(transaction_datetime))
            / 86400 AS series_days,
        SUM(amount) AS series_amount
    FROM tx
    GROUP BY laundering_type, account_id, DATE_TRUNC('month', transaction_datetime)
)
SELECT
	laundering_type,
    COUNT(*)                            AS series_count,
    MIN(series_tx)                      AS min_tx,
    MAX(series_tx)                      AS max_tx,
    ROUND(AVG(series_tx), 2)            AS avg_tx,
    ROUND(MIN(series_days)::numeric, 2) AS min_days,
    ROUND(MAX(series_days)::numeric, 2) AS max_days,
    ROUND(AVG(series_days)::numeric, 2) AS avg_days,
    ROUND(AVG(series_amount), 2) AS avg_series_amount
FROM series
GROUP BY laundering_type;
-- Wynik (seria = konto w danym miesiącu; serie przecięte granicą
-- miesiąca zaniżają minimum, stąd min_tx = 1 przy Cash_Withdrawal i Fan_In):
-- Cash_Withdrawal: śr. 6,8 transakcji (maks. 10), ok. 5 dni (maks. 7),
--   suma serii ok. 1,1 tys.
-- Smurfing: śr. 6,4 transakcji (3-8), ok. 8 dni (maks. 9), suma ok. 18 tys.
-- Structuring: śr. 8,3 transakcji (maks. 10), ok. 8 dni (maks. 12),
--   suma ok. 44 tys.
-- Fan_In: śr. 6,5 transakcji (maks. 12), do ok. 11 dni, suma ok. 80 tys.
-- Wniosek: podobna liczba transakcji w serii, typologie różnią się
-- głównie kwotami i kanałem płatności.

-- =====================================================
-- PODSUMOWANIE EKSPLORACJI
-- =====================================================
--
-- Etykieta SAML-D | Odpowiednik w literaturze | Kluczowe cechy w danych
-- ----------------+---------------------------+------------------------------------
-- Smurfing        | Structuring               | 1 nadawca -> 1 odbiorca, wyłącznie
--                 |                           | Cash Deposit, wpłaty ok. 1-7k,
--                 |                           | seria śr. 6 transakcji w ok. 8 dni,
--                 |                           | suma serii ok. 18 tys.
-- Structuring     | Smurfing                  | wielu nadawców -> 1 odbiorca, każdy
--                 |                           | nadawca wpłaca tylko raz, brak gotówki
--                 |                           | (5 kanałów, głównie Cross-border),
--                 |                           | wpłaty ok. 2-12,5k, seria śr. 8
--                 |                           | transakcji w ok. 8 dni, suma ok. 44 tys.
-- Fan_In          | Fan-in (kształt przepływu)| wielu nadawców -> 1 odbiorca, jeden
--                 |                           | zryw do ok. 10 dni, kwoty do ok. 65k,
--                 |                           | prawie tylko UK
-- Cash_Withdrawal | Wypłata gotówki           | 1 konto -> 1 odbiorca, wyłącznie
--                 |                           | Cash Withdrawal, wypłaty ok. 15-350,
--                 |                           | seria śr. 7 transakcji w ok. 5 dni,
--                 |                           | suma serii ok. 1,1 tys.
--
-- Wnioski:
-- 1. Etykiety Structuring i Smurfing są zamienione względem literatury.
--    Reguły nazywamy zgodnie z literaturą; w nagłówku każdej reguły
--    podajemy, którą etykietę SAML-D wykrywa.
-- 2. Wszystkie typologie występują seriami: krótkie odstępy wewnątrz
--    serii (głównie < 3 dni), przerwa > 14 dni oddziela kolejne serie.
-- 3. Liczba transakcji w serii jest podobna (śr. 6-8); typologie różnią
--    się kwotami, kanałem płatności i liczbą nadawców.
-- 4. Fan_In bez osobnej reguły: w danych napływających na bieżąco nie
--    da się odróżnić jednorazowego zrywu od pierwszej serii innej
--    typologii, a rozpoznanie wymagałoby analizy dalszego przepływu
--    środków (poza zakresem projektu).
--
-- Reguły do zbudowania:
-- - Structuring (etykieta Smurfing)  - etap lokowania
-- - Smurfing (etykieta Structuring)  - etap lokowania
-- - Cash_Withdrawal                  - etap integracji / wyjścia środków
-- =====================================================
