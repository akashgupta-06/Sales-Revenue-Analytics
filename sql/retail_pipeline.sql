show databases;
DROP DATABASE online_retail;
create database online_retail;
use online_retail;
show tables;

-- ============================
-- 1. RAW TABLE
-- ============================

CREATE TABLE retail_sales (              
    InvoiceNo   VARCHAR(20),
    StockCode   VARCHAR(20),
    Description TEXT,
    Quantity    INT,
    InvoiceDate DATETIME,
    UnitPrice   DECIMAL(10,2),
    CustomerID  VARCHAR(20),
    Country     VARCHAR(50)
);

-- ============================
-- 2. LOAD CSV
-- ============================

LOAD DATA INFILE 'C:\\ProgramData\\MySQL\\MySQL Server 8.0\\Uploads\\online_retail_II.csv'
INTO TABLE retail_sales
CHARACTER SET latin1
FIELDS TERMINATED BY ','
ENCLOSED BY '"'
LINES TERMINATED BY '\n'
IGNORE 1 ROWS
(InvoiceNo, StockCode, Description, Quantity, @InvoiceDate, UnitPrice, CustomerID, Country)
SET InvoiceDate = STR_TO_DATE(@InvoiceDate, '%d-%m-%Y %H:%i');

-- ============================
-- 3. CLEAN ANALYTICS LAYER
-- ============================

CREATE TABLE retail_sales_clean AS
SELECT
    InvoiceNo,
    StockCode,
    Description,
    Quantity,
    InvoiceDate,
    DATE(InvoiceDate) AS OrderDate,
    DATE_FORMAT(InvoiceDate, '%Y-%m') AS OrderMonth,
    UnitPrice,
    CustomerID,
    Country,
    (Quantity * UnitPrice) AS Revenue,
    CASE 
        WHEN InvoiceNo LIKE 'C%' OR Quantity < 0 THEN 1
        ELSE 0
    END AS IsCancelled
FROM retail_sales;

-- Add validity flag 
ALTER TABLE retail_sales_clean
ADD COLUMN IsValid TINYINT;

# Run it 1-5 times until it affects 0 rows

UPDATE retail_sales_clean
SET IsValid = CASE 
    WHEN UnitPrice <= 0 OR Quantity = 0 THEN 0 
    ELSE 1 
END
WHERE IsValid IS NULL
LIMIT 50000;


-- ============================
-- 4. INDEXES 
-- ============================

CREATE INDEX idx_order_month ON retail_sales_clean(OrderMonth);
CREATE INDEX idx_customer ON retail_sales_clean(CustomerID);
CREATE INDEX idx_invoice ON retail_sales_clean(InvoiceNo);
CREATE INDEX idx_country ON retail_sales_clean(Country);

-- ============================
-- 5. BUSINESS KPIs
-- ============================

-- 1. Total Revenue (Excluding Returns)
SELECT 
    SUM(Revenue) AS Total_Revenue
FROM retail_sales_clean
WHERE IsCancelled = 0 AND IsValid = 1;

-- 2. Revenue Lost Due to Returns
SELECT 
    SUM(Revenue) AS Return_Revenue_Impact
FROM retail_sales_clean
WHERE IsCancelled = 1 AND IsValid = 1;

-- 3. Net Revenue
SELECT
    SUM(CASE WHEN IsCancelled = 0 THEN Revenue ELSE 0 END) -
    ABS(SUM(CASE WHEN IsCancelled = 1 THEN Revenue ELSE 0 END)) 
    AS Net_Revenue
FROM retail_sales_clean
WHERE IsValid = 1;

-- 4. Monthly Revenue Trend
SELECT 
    OrderMonth,
    SUM(CASE WHEN IsCancelled = 0 THEN Revenue ELSE 0 END) AS Monthly_Revenue,
    SUM(CASE WHEN IsCancelled = 1 THEN Revenue ELSE 0 END) AS Return_Impact
FROM retail_sales_clean
WHERE IsValid = 1
GROUP BY OrderMonth
ORDER BY OrderMonth;

-- 5. Top 10 Countries by Revenue
SELECT 
    Country,
    SUM(Revenue) AS Revenue
FROM retail_sales_clean
WHERE IsCancelled = 0 AND IsValid = 1
GROUP BY Country
ORDER BY Revenue DESC
LIMIT 10;

-- 6. Top 10 Products by Revenue
SELECT 
    Description,
    SUM(Revenue) AS Revenue
FROM retail_sales_clean
WHERE IsCancelled = 0 AND IsValid = 1
GROUP BY Description
ORDER BY Revenue DESC
LIMIT 10;

-- 7. Total Unique Customers
SELECT COUNT(DISTINCT CustomerID) AS Unique_Customers
FROM retail_sales_clean
WHERE CustomerID IS NOT NULL AND IsValid = 1;

-- 8. Customers with More Than One Order
SELECT COUNT(*) AS Repeat_Customers
FROM (
    SELECT CustomerID
    FROM retail_sales_clean
    WHERE CustomerID IS NOT NULL AND IsValid = 1
    GROUP BY CustomerID
    HAVING COUNT(DISTINCT InvoiceNo) > 1
) t;

-- ============================
-- ADVANCED METRICS
-- ============================

-- Average Order Value (AOV)
SELECT 
    SUM(Revenue) / COUNT(DISTINCT InvoiceNo) AS Avg_Order_Value
FROM retail_sales_clean
WHERE IsCancelled = 0 
  AND IsValid = 1
  AND InvoiceNo IS NOT NULL;

-- Customer Lifetime Revenue (Top 20)
SELECT 
    CustomerID,
    SUM(Revenue) AS Lifetime_Revenue
FROM retail_sales_clean
WHERE IsCancelled = 0 
  AND IsValid = 1
  AND CustomerID IS NOT NULL
GROUP BY CustomerID
ORDER BY Lifetime_Revenue DESC
LIMIT 20;

-- Monthly Growth Rate
SELECT 
    OrderMonth,
    SUM(CASE WHEN IsCancelled = 0 THEN Revenue ELSE 0 END) AS Monthly_Revenue,
    LAG(SUM(CASE WHEN IsCancelled = 0 THEN Revenue ELSE 0 END)) 
        OVER (ORDER BY OrderMonth) AS Prev_Month,
    ROUND(
        (SUM(CASE WHEN IsCancelled = 0 THEN Revenue ELSE 0 END) -
         LAG(SUM(CASE WHEN IsCancelled = 0 THEN Revenue ELSE 0 END)) 
         OVER (ORDER BY OrderMonth))
        /
        LAG(SUM(CASE WHEN IsCancelled = 0 THEN Revenue ELSE 0 END)) 
        OVER (ORDER BY OrderMonth) * 100, 2
    ) AS Growth_Percent
FROM retail_sales_clean
WHERE IsValid = 1
GROUP BY OrderMonth;

-- Multi-line Invoices
SELECT InvoiceNo, COUNT(*) AS LineItems
FROM retail_sales_clean
GROUP BY InvoiceNo
HAVING COUNT(*) > 1;

select *from retail_sales_clean;
