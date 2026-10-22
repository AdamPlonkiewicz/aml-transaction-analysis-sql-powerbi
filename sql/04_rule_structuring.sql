-- =====================================================
-- 04_rule_structuring.sql
-- Reguła: Structuring (wykrywa etykietę SAML-D: Smurfing)
--
-- Definicja (literatura): jedna osoba dzieli gotówkę na wiele wpłat
-- poniżej progu raportowego, tak aby łączna kwota go przekraczała.
--
-- Profil w danych (03_typology_exploration.sql):
-- 1 nadawca -> 1 odbiorca, wyłącznie Cash Deposit, wpłaty ok. 1-7k,
-- seria śr. 6 transakcji (3-8) w ok. 8 dni, suma serii ok. 18 tys.
--
-- Etapy:
-- 1. Weryfikacja progu: pojedyncze wpłaty vs suma serii
-- 2. Scenariusz reguły i progi
-- 3. Kontrola na całym zbiorze (liczba alertów)
-- 4. Walidacja z etykietą
--
-- Próg raportowy: założenie robocze 10 000 GBP (dane z symulacji UK
-- nie zawierają progu; w Polsce np. 15 000 EUR).
-- =====================================================

-- 1. Weryfikacja progu: pojedyncze wpłaty vs suma serii
WITH series AS (
	SELECT
       	receiver_id ,
       	date_trunc('month', transaction_datetime) AS series_month,
       	SUM(amount) AS series_amount
    FROM aml_transactions_clean
    WHERE laundering_type = 'Smurfing'
    GROUP BY receiver_id, DATE_TRUNC('month', transaction_datetime)
)
SELECT
	MIN(series_amount) AS min_sum,
	PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY series_amount ) AS median_sum,
	MAX(series_amount) AS max_sum,
	COUNT(*) AS series_count,
	COUNT(*) FILTER (WHERE series_amount >= 10000) AS series_above_10K
FROM series;
-- Wynik: 144 ze 145 serii ma sumę >= 10 000 GBP (mediana ok. 17,2 tys.,
-- maks. ok. 31,3 tys.); jedyna seria poniżej progu (ok. 6,1 tys.)
-- to seria ucięta końcem okresu danych 23.08.2023.
-- Każda pojedyncza wpłata jest poniżej progu (maks. ok. 7k).
-- Wniosek: dane odpowiadają definicji structuringu - kwota rozbita
-- na wpłaty poniżej progu, suma serii przekracza próg.

-- 2. Scenariusz reguły i progi
WITH cash_dep AS (
	SELECT
		transaction_id,
		sender_id,
		receiver_id,
		laundering_type,
		COUNT(*) OVER (PARTITION BY sender_id, receiver_id ORDER BY transaction_datetime RANGE BETWEEN INTERVAL '10 days' PRECEDING AND CURRENT ROW) AS tx_count_10d,
		SUM(amount) OVER (PARTITION BY sender_id, receiver_id ORDER BY transaction_datetime RANGE BETWEEN INTERVAL '10 days' PRECEDING AND CURRENT ROW) AS sum_amount_10d,
		MAX(amount) OVER (PARTITION BY sender_id, receiver_id ORDER BY transaction_datetime RANGE BETWEEN INTERVAL '10 days' PRECEDING AND CURRENT ROW) AS max_amount_10d
	FROM aml_transactions_clean 
	WHERE payment_type  = 'Cash Deposit'
)
SELECT
	laundering_type,
	COUNT(*) AS alert_count,
	COUNT(DISTINCT (sender_id, receiver_id)) AS pair_count
FROM cash_dep
WHERE tx_count_10d >=4 AND sum_amount_10d >= 10000 AND max_amount_10d < 10000
GROUP BY laundering_type;
-- Wynik (>= 4 wpłaty, suma >= 10 000, każda < 10 000, okno 10 dni):
-- wykryte wszystkie 63 pary Smurfing (444 transakcje);
-- fałszywe alarmy: 57 par z normalnymi wpłatami gotówkowymi (61 transakcji).
-- Precyzja na poziomie par ok. 52%, na poziomie transakcji ok. 88%.

WITH cash_dep AS (
	SELECT
		transaction_id,
		sender_id,
		receiver_id,
		laundering_type,
		COUNT(*) OVER (PARTITION BY sender_id, receiver_id ORDER BY transaction_datetime RANGE BETWEEN INTERVAL '10 days' PRECEDING AND CURRENT ROW) AS tx_count_10d,
		SUM(amount) OVER (PARTITION BY sender_id, receiver_id ORDER BY transaction_datetime RANGE BETWEEN INTERVAL '10 days' PRECEDING AND CURRENT ROW) AS sum_amount_10d,
		MAX(amount) OVER (PARTITION BY sender_id, receiver_id ORDER BY transaction_datetime RANGE BETWEEN INTERVAL '10 days' PRECEDING AND CURRENT ROW) AS max_amount_10d
	FROM aml_transactions_clean 
	WHERE payment_type  = 'Cash Deposit'
)
SELECT
	laundering_type,
	COUNT(*) AS alert_count,
	COUNT(DISTINCT (sender_id, receiver_id)) AS pair_count
FROM cash_dep
WHERE tx_count_10d >=5 AND sum_amount_10d >= 10000 AND max_amount_10d < 10000
GROUP BY laundering_type;
-- Wynik (>= 5 wpłat, suma >= 10 000, każda < 10 000, okno 10 dni):
-- wykryte wszystkie 63 pary Smurfing (347 transakcji);
-- fałszywe alarmy: 4 pary normalnych wpłat gotówkowych (5 transakcji).
-- Precyzja: ok. 94% (pary), ok. 99% (transakcje); wykrycie 100% par.

-- 3. Reguła finalna
DROP TABLE IF EXISTS flags_structuring;

CREATE TABLE flags_structuring AS
WITH cash_dep AS (
	SELECT
		transaction_datetime,
		transaction_id,
		sender_id,
		receiver_id,
		laundering_type,
		COUNT(*) OVER (PARTITION BY sender_id, receiver_id ORDER BY transaction_datetime RANGE BETWEEN INTERVAL '10 days' PRECEDING AND CURRENT ROW) AS tx_count_10d,
		SUM(amount) OVER (PARTITION BY sender_id, receiver_id ORDER BY transaction_datetime RANGE BETWEEN INTERVAL '10 days' PRECEDING AND CURRENT ROW) AS sum_amount_10d,
		MAX(amount) OVER (PARTITION BY sender_id, receiver_id ORDER BY transaction_datetime RANGE BETWEEN INTERVAL '10 days' PRECEDING AND CURRENT ROW) AS max_amount_10d
	FROM aml_transactions_clean 
	WHERE payment_type  = 'Cash Deposit'
), triggers AS (
SELECT
	sender_id,
	receiver_id,
	transaction_datetime
FROM cash_dep
WHERE tx_count_10d >=5 AND sum_amount_10d >= 10000 AND max_amount_10d < 10000
)
SELECT
	DISTINCT cd.transaction_id
FROM cash_dep cd
JOIN triggers t
ON cd.sender_id = t.sender_id
AND cd.receiver_id = t.receiver_id 
AND cd.transaction_datetime BETWEEN t.transaction_datetime - INTERVAL '10 days' AND t.transaction_datetime; 

-- 4. Walidacja z etykietą
SELECT 
	atc.laundering_type,
	COUNT(*) AS total_tx,
	COUNT(f.transaction_id) AS flagged_tx
FROM aml_transactions_clean atc
LEFT JOIN flags_structuring f ON atc.transaction_id = f.transaction_id
WHERE atc.payment_type  = 'Cash Deposit'
GROUP BY atc.laundering_type ;
-- Walidacja (poziom transakcji, wpłaty gotówkowe):
-- Smurfing: oflagowane 925 z 932 (wykrywalność 99,2%);
-- Normal_Cash_Deposits: 21 z 223 801 (0,009%);
-- Deposit-Send: 0 z 473 (inna typologia, poprawnie pominięta).
-- Precyzja: 925 / 946 = 97,8%.
-- 7 pominiętych wpłat: krótkie serie (3-4 wpłaty) poniżej progu 5,
-- w tym seria ucięta końcem okresu danych (3 wpłaty, suma ok. 6,1 tys.).
-- Obniżenie progu do 4 kosztowałoby 53 dodatkowe fałszywe pary.

