-- =====================================================
-- 01_data_profiling_and_quality.sql
-- Profilowanie i kontrola jakości surowych danych SAML-D.
--
-- Import: CSV z Kaggle do tabeli aml_transactions_raw (DBeaver),
-- kolumna amount jako NUMERIC(12,2).
--
-- Etapy:
-- 1. Ujednolicenie nazw kolumn
-- 2. Podstawowe statystyki i zgodność z dokumentacją
-- 3. Braki danych, duplikaty, spójność etykiet
-- 4. Rozkład kwot
-- 5. Unikalność numerów kont
-- =====================================================


ALTER TABLE aml_transactions_raw RENAME COLUMN "Time" TO transaction_time;
ALTER TABLE aml_transactions_raw RENAME COLUMN "Date" TO transaction_date;
ALTER TABLE aml_transactions_raw RENAME COLUMN "Sender_account" TO sender_account;
ALTER TABLE aml_transactions_raw RENAME COLUMN "Receiver_account" TO receiver_account;
ALTER TABLE aml_transactions_raw RENAME COLUMN "Amount" TO amount;
ALTER TABLE aml_transactions_raw RENAME COLUMN "Payment_currency" TO payment_currency;
ALTER TABLE aml_transactions_raw RENAME COLUMN "Received_currency" TO received_currency;
ALTER TABLE aml_transactions_raw RENAME COLUMN "Sender_bank_location" TO sender_bank_location;
ALTER TABLE aml_transactions_raw RENAME COLUMN "Receiver_bank_location" TO receiver_bank_location;
ALTER TABLE aml_transactions_raw RENAME COLUMN "Payment_type" TO payment_type;
ALTER TABLE aml_transactions_raw RENAME COLUMN "Is_laundering" TO is_laundering;
ALTER TABLE aml_transactions_raw RENAME COLUMN "Laundering_type" TO laundering_type;

SELECT 
	COUNT(*),
	MIN(transaction_time) AS min_transaction_time,
	MAX(transaction_time) AS  max_transaction_time,
	MIN(transaction_date) AS min_transaction_date,
	MAX(transaction_date) AS max_transaction_date, 
	MIN(amount) AS min_amount,
	MAX(amount) AS max_amount,
	COUNT(DISTINCT sender_account) AS sender_account_count,
	COUNT(DISTINCT receiver_account) AS receiver_account_count,
	COUNT(DISTINCT sender_bank_location) AS sender_bank_location_count,
	COUNT(DISTINCT receiver_bank_location) AS receiver_bank_location_count,
	COUNT(DISTINCT payment_currency) AS payment_currency_count,
	COUNT(DISTINCT received_currency) AS received_currency_count,
	COUNT(DISTINCT payment_type) AS payment_type_count,
	COUNT(DISTINCT laundering_type ) AS laundering_type_count,
	SUM(is_laundering) AS laundering_sum,
	ROUND((SUM(is_laundering)::NUMERIC *100)/COUNT(*),6) AS laundering_pct
FROM aml_transactions_raw;
-- Import zwalidowany: 9,504,852 wierszy, laundering_pct= 0.103873% zgodne z dokumentacją datasetu (Oztas i in., 2023: ~0.1039%)
-- Zakres dat: 2022-10-07 do 2023-08-23 (~10.5 miesiąca)
-- Asymetria: 292,715 unikalnych nadawców vs 652,266 odbiorców (2.2x)


SELECT 
	is_laundering,
	laundering_type,
	COUNT(*) AS transaction_count, 
	ROUND((COUNT(*) *100.0 / SUM(COUNT(*)) OVER ())::numeric,6) AS transaction_pct
FROM aml_transactions_raw 
GROUP BY is_laundering, laundering_type
ORDER BY is_laundering DESC, transaction_count DESC;
-- 28 typów: 11 normalnych i 17 typologii prania.


SELECT 
	COUNT(*) FILTER (WHERE amount IS NULL) AS amount_nulls, 
	COUNT(*) FILTER (WHERE is_laundering IS NULL) AS is_laundering_nulls, 
	COUNT(*) FILTER (WHERE sender_account IS NULL) AS sender_account_nulls, 
	COUNT(*) FILTER (WHERE receiver_account IS NULL) AS receiver_account_nulls,
	
 	COUNT(*) FILTER (WHERE TRIM(payment_type) = '') AS payment_type_blank,
    COUNT(*) FILTER (WHERE payment_type IN ('NULL', 'N/A', '-')) AS payment_type_placeholder,
    COUNT(*) FILTER (WHERE payment_type IS NULL) AS payment_type_nulls,
    
    COUNT(*) FILTER (WHERE TRIM(payment_currency) = '') AS payment_currency_blank,
    COUNT(*) FILTER (WHERE payment_currency IN ('NULL', 'N/A', '-')) AS payment_currency_placeholder,
    COUNT(*) FILTER (WHERE payment_currency IS NULL) AS payment_currency_nulls,
    
    COUNT(*) FILTER (WHERE TRIM(received_currency) = '') AS received_currency_blank,
    COUNT(*) FILTER (WHERE received_currency IN ('NULL', 'N/A', '-')) AS received_currency_placeholder,
    COUNT(*) FILTER (WHERE received_currency IS NULL) AS received_currency_nulls,
    
    COUNT(*) FILTER (WHERE TRIM(sender_bank_location) = '') AS sender_bank_location_blank,
    COUNT(*) FILTER (WHERE sender_bank_location IN ('NULL', 'N/A', '-')) AS sender_bank_location_placeholder,
    COUNT(*) FILTER (WHERE sender_bank_location IS NULL) AS sender_bank_location_nulls,
    
    COUNT(*) FILTER (WHERE TRIM(receiver_bank_location) = '') AS receiver_bank_location_blank,
    COUNT(*) FILTER (WHERE receiver_bank_location IN ('NULL', 'N/A', '-')) AS receiver_bank_location_placeholder,
    COUNT(*) FILTER (WHERE receiver_bank_location IS NULL) AS receiver_bank_location_nulls,
    
    COUNT(*) FILTER (WHERE TRIM(laundering_type) = '') AS laundering_type_blank,
    COUNT(*) FILTER (WHERE laundering_type IN ('NULL', 'N/A', '-')) AS laundering_type_placeholder,
    COUNT(*) FILTER (WHERE laundering_type IS NULL) AS laundering_type_nulls,
    
    COUNT(*) FILTER (WHERE TRIM(transaction_time) = '') AS transaction_time_blank,
    COUNT(*) FILTER (WHERE transaction_time IN ('NULL', 'N/A', '-')) AS transaction_time_placeholder,
    COUNT(*) FILTER (WHERE transaction_time IS NULL) AS transaction_time_nulls,
    
    COUNT(*) FILTER (WHERE TRIM(transaction_date) = '') AS transaction_date_blank,
    COUNT(*) FILTER (WHERE transaction_date IN ('NULL', 'N/A', '-')) AS transaction_date_placeholder,
    COUNT(*) FILTER (WHERE transaction_date IS NULL) AS transaction_date_nulls
FROM aml_transactions_raw;
-- W tabeli nie stwierdzono wartości NULL, pustych pól tekstowych ani tekstowych placeholderów brakujących danych.

SELECT
    transaction_time,
    transaction_date,
    sender_account,
    receiver_account,
    amount,
    payment_currency,
    received_currency,
    sender_bank_location,
    receiver_bank_location,
    payment_type,
    is_laundering,
    laundering_type,
    COUNT(*) AS row_count
FROM aml_transactions_raw
GROUP BY
    transaction_time,
    transaction_date,
    sender_account,
    receiver_account,
    amount,
    payment_currency,
    received_currency,
    sender_bank_location,
    receiver_bank_location,
    payment_type,
    is_laundering,
    laundering_type
HAVING COUNT(*) > 1;
-- Nie wykryto pełnych duplikatów rekordów; zapytanie zwróciło pusty wynik.

SELECT *
FROM aml_transactions_raw 
WHERE sender_account = receiver_account; 
-- w zbiorze nie występują przelewy wewnętrzne pomiędzy kontami klienta.

SELECT *
FROM aml_transactions_raw
WHERE is_laundering = 0 AND laundering_type NOT LIKE 'Normal%'

SELECT *
FROM aml_transactions_raw
WHERE is_laundering = 1 AND laundering_type LIKE 'Normal%'
-- W zbiorze nie ma niespójności: is_laundering jest zgodne z laundering_type.


SELECT
	ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY amount)::numeric,2) AS median_amount,
    ROUND(PERCENTILE_CONT(0.95) WITHIN GROUP (ORDER BY amount)::numeric,2) AS p95_amount,
    ROUND(PERCENTILE_CONT(0.99) WITHIN GROUP (ORDER BY amount)::numeric,2) AS p99_amount,
	ROUND(PERCENTILE_CONT(0.999) WITHIN GROUP (ORDER BY amount)::numeric,2) AS p999_amount,
    MAX(amount) AS max_amount
FROM aml_transactions_raw;
-- Mediana 6,1 tys., p95 22 tys., p99 45 tys., p99,9 343 tys., maks. 12,6 mln
-- – gwałtowny wzrost kwot powyżej p99.

SELECT *
FROM aml_transactions_raw
ORDER BY amount DESC
LIMIT 100;
-- Wszystkie transakcje powyżej 1 mln to Over-Invoicing (54/54)
-- – cecha tej typologii, a nie błąd danych.

SELECT 
	COUNT(*) FILTER (WHERE transaction_time !~ '^\d{2}:\d{2}:\d{2}$') AS bad_time_format,
	COUNT(*) FILTER (WHERE transaction_date !~ '^\d{4}-\d{2}-\d{2}$') AS bad_date_format
FROM aml_transactions_raw;
-- Wszystkie daty i godziny mają poprawny format.


--Sprawdzanie poprawności numerów kont
SELECT sender_account, COUNT(DISTINCT sender_bank_location) AS location_count
FROM aml_transactions_raw
GROUP BY sender_account
HAVING COUNT(DISTINCT sender_bank_location) > 1
LIMIT 20;

SELECT receiver_account, COUNT(DISTINCT receiver_bank_location) AS location_count
FROM aml_transactions_raw
GROUP BY receiver_account
HAVING COUNT(DISTINCT receiver_bank_location) > 1
LIMIT 20;
-- Ten sam numer konta występuje w różnych bankach (lokalizacjach) – sam numer nie jest unikalnym identyfikatorem.

SELECT
    COUNT(DISTINCT sender_account) AS unique_sender_account_numbers,
    COUNT(DISTINCT sender_account || '_' || sender_bank_location) AS unique_sender_account_location_pairs,
    100 - ROUND(COUNT(DISTINCT sender_account)*100.0 / COUNT(DISTINCT sender_account || '_' || sender_bank_location),2) AS un_sen_acc_pct,
    COUNT(DISTINCT receiver_account) AS unique_reciver_account_numbers, 
    COUNT(DISTINCT receiver_account || '_' || receiver_bank_location) AS unique_reciver_account_location_pairs,
    100 - ROUND(COUNT(DISTINCT receiver_account)*100.0 / COUNT(DISTINCT receiver_account || '_' || receiver_bank_location),2) AS un_rec_acc_pct
FROM aml_transactions_raw;
-- liczba kont po uwzględnieniu lokalizacji banku wzrosła o 1,81 % w przypadku sender i 0,62% received

SELECT COUNT(*) FILTER (WHERE sender_account IN (
    SELECT sender_account FROM aml_transactions_raw
    GROUP BY sender_account
    HAVING COUNT(DISTINCT sender_bank_location) > 1
)) AS affected_transactions,
COUNT(*) AS total_transactions
FROM aml_transactions_raw;
-- 17% transakcji dotyczy nadawców, których numer konta powtarza się w różnych bankach.

SELECT COUNT(*) FILTER (WHERE receiver_account IN (
    SELECT receiver_account FROM aml_transactions_raw
    GROUP BY receiver_account
    HAVING COUNT(DISTINCT receiver_bank_location) > 1
)) AS affected_transactions,
COUNT(*) AS total_transactions
FROM aml_transactions_raw;
-- 5,5% transakcji dotyczy odbiorców z powtarzającym się numerem konta.
-- Do dalszej analizy konto należy identyfikować jako numer + lokalizacja banku.
