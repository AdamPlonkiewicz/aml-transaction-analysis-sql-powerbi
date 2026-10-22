-- =====================================================
-- 06_rule_smurfing.sql
-- Reguła: Smurfing (wykrywa etykietę SAML-D: Structuring)
--
-- Definicja (literatura): wiele osób ("smerfów") wprowadza małe kwoty
-- do jednego kolektora.
--
-- Profil w danych (03_typology_exploration.sql):
-- wielu nadawców -> 1 odbiorca, każdy nadawca wpłaca tylko raz,
-- brak gotówki (5 kanałów, głównie Cross-border), wpłaty ok. 2-12,5k,
-- seria śr. 8 transakcji w ok. 8 dni, suma serii ok. 44 tys.
--
-- Etapy:
-- 1. Zachowania z literatury (przepływ przez konta pośredników)
-- 2. Podobieństwo kwot w serii
-- 3. Nowi nadawcy: każdy nadawca wpłaca do odbiorcy tylko raz
-- 4. Test progów (nowi nadawcy, podobne kwoty)
-- 5. Reguła finalna i walidacja
-- =====================================================

-- 1. Zachowania z literatury (przepływ przez konta pośredników
-- jakie wpływy otrzymali nadawcy w ciągu 30 dni przed transakcją Structuring?
WITH structuring_tx AS (
    SELECT
        transaction_id,
        sender_id,
        transaction_datetime,
        amount
    FROM aml_transactions_clean
    WHERE laundering_type = 'Structuring'
)
SELECT
    prev.payment_type    AS prev_payment_type,
    prev.laundering_type AS prev_laundering_type,
    COUNT(DISTINCT st.transaction_id) AS tx_count
FROM structuring_tx st
LEFT JOIN aml_transactions_clean prev
    ON  prev.receiver_id = st.sender_id
    AND prev.transaction_datetime < st.transaction_datetime
    AND st.transaction_datetime - prev.transaction_datetime <= INTERVAL '30 days'
GROUP BY prev.payment_type, prev.laundering_type
ORDER BY tx_count DESC;

-- Wynik: ok. 51% transakcji Structuring nie ma żadnego wpływu na konto
-- nadawcy w ciągu 30 dni wcześniej; wpłaty gotówkowe poprzedzają ok. 27%
-- Wpływy to zwykła aktywność kont nadawców (typy Normal_*).



-- Przepływ przez konta pośredników: czy przelew Structuring jest
-- poprzedzony wpływem o zbliżonej kwocie (0-10% więcej) w ciągu 3 dni?
WITH structuring_tx AS (
    SELECT transaction_id, sender_id, transaction_datetime, amount
    FROM aml_transactions_clean
    WHERE laundering_type = 'Structuring'
)
SELECT
    COUNT(DISTINCT st.transaction_id) AS structuring_tx_matched
FROM structuring_tx st
JOIN aml_transactions_clean prev
    ON  prev.receiver_id = st.sender_id
    AND prev.transaction_datetime < st.transaction_datetime
    AND st.transaction_datetime - prev.transaction_datetime <= INTERVAL '3 days'
    AND prev.amount BETWEEN st.amount AND st.amount * 1.1;

-- Wynik: 5 z 1870 transakcji Structuring.
-- Wniosek: w SAML-D nie zamodelowano przepływu przez konta pośredników
-- (wpłata -> szybki przelew dalej); reguła nie opiera się na śledzeniu
-- drogi pieniądza.


-- 2. Podobieństwo kwot w serii
WITH series AS (
	SELECT
		MAX(amount)/MIN(amount) AS max_min_ratio,
		STDDEV(amount) / AVG(amount) AS amount_cv
	FROM aml_transactions_clean
	WHERE laundering_type = 'Structuring'
	GROUP BY receiver_id, DATE_TRUNC('month', transaction_datetime)
)
SELECT
	COUNT(*) AS series_count,
	ROUND(PERCENTILE_CONT(0.5)   WITHIN GROUP (ORDER BY max_min_ratio)::numeric,2) AS ratio_p50,
    ROUND(PERCENTILE_CONT(0.90)  WITHIN GROUP (ORDER BY max_min_ratio)::numeric,2) AS ratio_p90,
    ROUND(MAX(max_min_ratio),2) AS ratio_max,
    ROUND(PERCENTILE_CONT(0.5)   WITHIN GROUP (ORDER BY amount_cv)::numeric,2) AS cv_p50,
    ROUND(PERCENTILE_CONT(0.90)  WITHIN GROUP (ORDER BY amount_cv)::numeric,2) AS cv_p90,
    ROUND(MAX(amount_cv),2) AS cv_max
FROM series; 
-- Podobieństwo kwot w seriach Structuring (seria = odbiorca w danym
-- miesiącu; niskie maksimum potwierdza, że przybliżenie nie skleja
-- różnych serii):
-- stosunek maks./min. kwoty w serii: mediana 1,08, p90 1,10, maks. 1,10;
-- współczynnik zmienności: mediana 0,03, maks. 0,04.
-- Wniosek: wpłaty w serii mają bardzo zbliżone kwoty (różnica <= 10%),
-- choć poziom kwot różni się między seriami (ok. 2k-12,5k).


-- 3. Nowi nadawcy: każdy nadawca wpłaca do odbiorcy tylko raz
-- Czy nadawcy w schemacie Structuring mieli z odbiorcą inne transakcje?
WITH pairs AS (
	SELECT 
		DISTINCT sender_id, receiver_id 
	FROM aml_transactions_clean
	WHERE laundering_type = 'Structuring'
)
SELECT 
	atc.laundering_type,
	COUNT(*) AS tx_count,
	COUNT(DISTINCT (atc.sender_id, atc.receiver_id)) AS pair_count
FROM pairs  p
JOIN aml_transactions_clean atc
	ON p.sender_id = atc.sender_id
	AND p.receiver_id = atc.receiver_id 
GROUP BY atc.laundering_type;
-- Wynik: 1 870 par i 1 870 transakcji - każdy nadawca wysłał do
-- odbiorcy dokładnie jedną transakcję w całym zbiorze (tylko w ramach
-- prania). W chwili wpłaty każdy nadawca jest więc "nowy" dla odbiorcy.
-- Ograniczenie: cecha wynika z modelu generatora; w rzeczywistości
-- smerfy mogą wracać do tego samego kolektora w kolejnych seriach.


-- 4. Test progów (nowi nadawcy, podobne kwoty)
-- Test reguły: dla każdego odbiorcy, w kroczącym oknie 10 dni,
-- liczymy wyłącznie wpłaty od nowych nadawców (pierwsza transakcja
-- danego nadawcy do danego odbiorcy) oraz najmniejszą i największą
-- kwotę w oknie. Porównanie progów: sama liczba nowych nadawców
-- vs liczba nowych nadawców + podobne kwoty (maks. <= 1,10 x min.).
WITH flagged AS (
SELECT
	transaction_id,
    sender_id,
    receiver_id,
    transaction_datetime,
    amount,
    laundering_type,
    CASE
        WHEN ROW_NUMBER() OVER (PARTITION BY receiver_id, sender_id
        ORDER BY transaction_datetime) = 1 THEN 1
        ELSE 0
        END AS is_new_sender
FROM aml_transactions_clean
), new_senders AS (
SELECT 
	transaction_id,
	receiver_id,
   	laundering_type,
   	transaction_datetime,
   	COUNT(*)    OVER w AS tx_count_10d,
    MIN(amount) OVER w AS min_amount_10d,
    MAX(amount) OVER w AS max_amount_10d
FROM flagged 
WHERE is_new_sender = 1 
WINDOW w AS (
	PARTITION BY receiver_id
    ORDER BY transaction_datetime
    RANGE BETWEEN INTERVAL '10 days' PRECEDING AND CURRENT ROW)
)
SELECT 
	laundering_type,
  	COUNT(DISTINCT receiver_id) FILTER (WHERE tx_count_10d >=7) AS rcv_min7,
  	COUNT(DISTINCT receiver_id) FILTER (WHERE tx_count_10d >=7 AND max_amount_10d <= 1.10 * min_amount_10d) AS rcv_min7_amt10,
  	COUNT(DISTINCT receiver_id) FILTER (WHERE tx_count_10d >=5 AND max_amount_10d <= 1.10 * min_amount_10d) AS rcv_min5_amt10
FROM new_senders
GROUP BY laundering_type;
 -- Test progów (odbiorcy; okno 10 dni; tylko wpłaty od nowych nadawców):
-- >= 7 nowych nadawców:              74/75 odbiorców Structuring,
--                                    ok. 15 tys. fałszywych
--                                    (głównie Normal_Fan_In: 12 985)
-- >= 7 + kwoty w granicach 10%:      74/75, 0 fałszywych
-- >= 5 + kwoty w granicach 10%:      75/75, 4 fałszywych (Normal_Fan_In)
-- Warunek podobnych kwot odcina normalnych odbiorców z wieloma nadawcami:
-- kwoty różnią się tam między nadawcami (w praniu różnica <= 10%).
-- Decyzja: >= 5 wpłat od nowych nadawców w 10 dni, maks. kwota
-- <= 1,10 x min. kwota (pełna wykrywalność, 4 fałszywe alarmy).
  
-- 5. Reguła finalna i walidacja  
DROP TABLE IF EXISTS flags_smurfing;

CREATE TABLE flags_smurfing AS
WITH flagged AS (
	SELECT
        transaction_id,
        sender_id,
        receiver_id,
        transaction_datetime,
        amount,
        laundering_type,
        CASE
            WHEN ROW_NUMBER() OVER (PARTITION BY receiver_id, sender_id
                                    ORDER BY transaction_datetime) = 1 THEN 1
            ELSE 0
        END AS is_new_sender
    FROM aml_transactions_clean
   ),new_senders AS (
   	SELECT 
   		transaction_id,
   		receiver_id,
   		laundering_type,
   		transaction_datetime,
   		COUNT(*)    OVER w AS tx_count_10d,
        MIN(amount) OVER w AS min_amount_10d,
        MAX(amount) OVER w AS max_amount_10d
   FROM flagged 
   WHERE is_new_sender = 1 
   WINDOW w AS (
        PARTITION BY receiver_id
        ORDER BY transaction_datetime
        RANGE BETWEEN INTERVAL '10 days' PRECEDING AND CURRENT ROW)  
), triggers AS (
SELECT
	receiver_id,
	transaction_datetime
FROM new_senders
WHERE tx_count_10d >=5 AND max_amount_10d <= 1.10 * min_amount_10d
)
SELECT
	DISTINCT ns.transaction_id
FROM new_senders ns 
JOIN triggers t
ON ns.receiver_id = t.receiver_id 
AND ns.transaction_datetime BETWEEN t.transaction_datetime - INTERVAL '10 days' AND t.transaction_datetime; 



SELECT 
	atc.laundering_type,
	COUNT(*) AS total_tx,
	COUNT(f.transaction_id) AS flagged_tx
FROM aml_transactions_clean atc
LEFT JOIN flags_smurfing f ON atc.transaction_id = f.transaction_id
GROUP BY atc.laundering_type;
-- Walidacja (poziom transakcji, wszystkie typy płatności):
-- Structuring: oflagowane 1 742 z 1 870 (recall 93,2%);
-- Normal_Fan_In: 20 z 2,1 mln; pozostałe typy: 0.

-- Precyzja: 1 742 / 1 762 = 98,9%. Wykryci wszyscy odbiorcy (75/75).
-- Pominięte transakcje: wpłaty z najdłuższych serii (> 10 dni przed
-- wyzwalaczem) oraz serie krótsze niż 5 wpłat.
