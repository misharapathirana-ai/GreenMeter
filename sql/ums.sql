-- phpMyAdmin SQL Dump
-- version 5.2.1
-- https://www.phpmyadmin.net/
--
-- Host: 127.0.0.1
-- Generation Time: Jan 09, 2026 at 12:33 PM
-- Server version: 8.0.41
-- PHP Version: 8.2.12

SET SQL_MODE = "NO_AUTO_VALUE_ON_ZERO";
START TRANSACTION;
SET time_zone = "+00:00";


/*!40101 SET @OLD_CHARACTER_SET_CLIENT=@@CHARACTER_SET_CLIENT */;
/*!40101 SET @OLD_CHARACTER_SET_RESULTS=@@CHARACTER_SET_RESULTS */;
/*!40101 SET @OLD_COLLATION_CONNECTION=@@COLLATION_CONNECTION */;
/*!40101 SET NAMES utf8mb4 */;

--
-- Database: `ums`
--

DELIMITER $$
--
-- Procedures
--
CREATE DEFINER=`root`@`localhost` PROCEDURE `GenerateBillForReading` (IN `p_reading_id` INT, OUT `p_bill_id` INT)   BEGIN
    DECLARE v_amount, v_fixed DECIMAL(10,2);
    DECLARE v_due_date DATE;
    DECLARE v_util_id, v_rate1_slab_max INT DEFAULT 30;
    DECLARE v_rate1, v_rate2 DECIMAL(6,2);
    DECLARE v_consumption DECIMAL(10,2);
    
    -- Validate reading exists
    SELECT r.consumption, m.util_id
    INTO v_consumption, v_util_id
    FROM Reading r
    JOIN Meter m ON r.meter_id = m.meter_id
    WHERE r.reading_id = p_reading_id;
    
    IF v_consumption IS NULL THEN
        SIGNAL SQLSTATE '45000' SET MESSAGE_TEXT = 'Error: Reading ID not found.';
    END IF;
    
    -- Get tariff rates (2-slab model)
    SELECT 
        MAX(CASE WHEN min_unit = 0 THEN rate_per_unit END),
        MAX(CASE WHEN min_unit > 0 THEN rate_per_unit END),
        MAX(fixed_charge)
    INTO v_rate1, v_rate2, v_fixed
    FROM Tariff
    WHERE util_id = v_util_id;
    
    -- Calculate amount
    IF v_consumption <= v_rate1_slab_max THEN
        SET v_amount = v_consumption * v_rate1 + v_fixed;
    ELSE
        SET v_amount = (v_rate1_slab_max * v_rate1) + ((v_consumption - v_rate1_slab_max) * v_rate2) + v_fixed;
    END IF;
    
    -- Set due date: 15 days from today
    SET v_due_date = DATE_ADD(CURDATE(), INTERVAL 15 DAY);
    
    -- Insert bill
    START TRANSACTION;
    INSERT INTO Bill (reading_id, issue_date, due_date, amount)
    VALUES (p_reading_id, CURDATE(), v_due_date, v_amount);
    
    SET p_bill_id = LAST_INSERT_ID();
    COMMIT;
    
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `GetDefaultersList` ()  READS SQL DATA BEGIN
    SELECT 
        c.cust_id,
        c.name AS customer,
        c.address,
        u.name AS utility,
        b.bill_id,
        b.amount,
        b.total_due,
        b.issue_date,
        b.due_date,
        DATEDIFF(CURDATE(), b.due_date) AS days_overdue
    FROM Bill b
    JOIN Reading r ON b.reading_id = r.reading_id
    JOIN Meter m ON r.meter_id = m.meter_id
    JOIN Customer c ON m.cust_id = c.cust_id
    JOIN UtilityType u ON m.util_id = u.util_id
    WHERE b.status = 'unpaid'
      AND b.due_date <= DATE_SUB(CURDATE(), INTERVAL 7 DAY)
    ORDER BY days_overdue DESC, b.amount DESC;
END$$

CREATE DEFINER=`root`@`localhost` PROCEDURE `GetMonthlyReport` (IN `yr` INT, IN `mo` INT)  READS SQL DATA BEGIN
    SELECT 
        utility,
        method,
        transactions,
        CONCAT('LKR ', FORMAT(revenue, 2)) AS revenue_display  -- ← 'revenue_display'
    FROM MonthlyRevenueReport
    WHERE year = yr AND month = mo
    ORDER BY utility, FIELD(method, 'cash', 'card', 'online');
END$$

--
-- Functions
--
CREATE DEFINER=`root`@`localhost` FUNCTION `CalculateBillAmount` (`rid` INT) RETURNS DECIMAL(10,2) DETERMINISTIC READS SQL DATA BEGIN
    DECLARE cons DECIMAL(10,2);
    DECLARE util_id_val INT;
    DECLARE rate1, rate2, fixed DECIMAL(6,2);
    DECLARE amount DECIMAL(10,2) DEFAULT 0.00;
    
    -- Get consumption and utility type
    SELECT r.consumption, m.util_id
    INTO cons, util_id_val
    FROM Reading r
    JOIN Meter m ON r.meter_id = m.meter_id
    WHERE r.reading_id = rid;
    
    -- Get slab 1 (0–30) rate and fixed charge
    SELECT rate_per_unit, fixed_charge
    INTO rate1, fixed
    FROM Tariff
    WHERE util_id = util_id_val AND min_unit = 0;
    
    -- Get slab 2 (31+) rate
    SELECT rate_per_unit
    INTO rate2
    FROM Tariff
    WHERE util_id = util_id_val AND min_unit > 0
    LIMIT 1;
    
    -- Calculate amount
    IF cons <= 30 THEN
        SET amount = cons * rate1 + fixed;
    ELSE
        SET amount = (30 * rate1) + ((cons - 30) * rate2) + fixed;
    END IF;
    
    RETURN amount;
END$$

CREATE DEFINER=`root`@`localhost` FUNCTION `CalculateLateFee` (`bid` INT) RETURNS DECIMAL(6,2) DETERMINISTIC READS SQL DATA BEGIN
    DECLARE amt, paid_total DECIMAL(10,2);
    DECLARE due_date_val DATE;
    
    -- Get bill amount and due date
    SELECT amount, due_date INTO amt, due_date_val
    FROM Bill
    WHERE bill_id = bid;
    
    -- Get total paid so far
    SELECT COALESCE(SUM(amount_paid), 0) INTO paid_total
    FROM Payment
    WHERE bill_id = bid;
    
    -- If unpaid and overdue → 5% of outstanding
    IF paid_total < amt AND CURDATE() > due_date_val THEN
        RETURN ROUND((amt - paid_total) * 0.05, 2);
    ELSE
        RETURN 0.00;
    END IF;
END$$

DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `bill`
--

CREATE TABLE `bill` (
  `bill_id` int NOT NULL,
  `reading_id` int NOT NULL,
  `issue_date` date NOT NULL DEFAULT (curdate()),
  `due_date` date NOT NULL,
  `amount` decimal(10,2) NOT NULL,
  `late_fee` decimal(6,2) DEFAULT '0.00',
  `total_due` decimal(10,2) GENERATED ALWAYS AS ((`amount` + `late_fee`)) STORED,
  `status` enum('unpaid','paid') COLLATE utf8mb4_general_ci DEFAULT 'unpaid',
  `notes` text COLLATE utf8mb4_general_ci
) ;

--
-- Dumping data for table `bill`
--

INSERT INTO `bill` (`bill_id`, `reading_id`, `issue_date`, `due_date`, `amount`, `late_fee`, `status`, `notes`) VALUES
(1, 2, '2025-11-22', '2025-12-01', 35.75, 0.00, 'unpaid', NULL),
(2, 2, '2025-11-22', '2025-12-07', 275.00, 0.00, 'unpaid', NULL),
(3, 1, '2025-10-05', '2025-10-20', 3610.50, 0.00, 'unpaid', 'Oct 2025 - Nimal Perera (Elec)'),
(4, 3, '2025-10-05', '2025-10-20', 665.00, 0.00, 'paid', 'Oct 2025 - Nimal Perera (Water)'),
(5, 4, '2025-10-05', '2025-10-20', 3228.00, 0.00, 'unpaid', 'Oct 2025 - Chamari Silva (Elec)'),
(6, 5, '2025-10-05', '2025-10-20', 1950.00, 0.00, 'paid', 'Oct 2025 - Chamari Silva (Gas)'),
(7, 6, '2025-10-05', '2025-10-20', 2778.00, 0.00, 'unpaid', 'Oct 2025 - Rajitha Fernando (Elec)'),
(8, 7, '2025-10-05', '2025-10-20', 3228.00, 0.00, 'unpaid', 'Oct 2025 - Dinusha Gunawardena (Elec)'),
(9, 8, '2025-10-05', '2025-10-20', 665.00, 0.00, 'paid', 'Oct 2025 - Dinusha Gunawardena (Water)'),
(10, 9, '2025-10-05', '2025-10-20', 3678.00, 0.00, 'paid', 'Oct 2025 - Tharindu Jayasinghe (Elec)'),
(11, 10, '2025-10-05', '2025-10-20', 845.00, 0.00, 'paid', 'Oct 2025 - Tharindu Jayasinghe (Water)'),
(12, 11, '2025-10-05', '2025-10-20', 2310.00, 0.00, 'paid', 'Oct 2025 - Tharindu Jayasinghe (Gas)'),
(13, 12, '2025-10-05', '2025-10-20', 2328.00, 0.00, 'unpaid', 'Oct 2025 - Yasodha Rajapakse (Elec)'),
(14, 13, '2025-10-05', '2025-10-20', 9120.00, 0.00, 'paid', 'Oct 2025 - ABC Traders (Elec)'),
(15, 14, '2025-10-05', '2025-10-20', 1080.00, 0.00, 'paid', 'Oct 2025 - ABC Traders (Water)'),
(16, 15, '2025-10-05', '2025-10-20', 7870.00, 0.00, 'paid', 'Oct 2025 - Kandy Bakery (Elec)'),
(17, 15, '2025-10-05', '2025-10-20', 9120.00, 0.00, 'unpaid', 'Oct 2025 - Galle Seafood (Elec)'),
(18, 19, '2025-11-25', '2025-12-10', 8180.00, 0.00, 'unpaid', NULL),
(19, 20, '2025-11-25', '2025-12-10', 345.00, 0.00, 'paid', NULL),
(20, 21, '2025-11-25', '2025-12-10', 70350.00, 0.00, 'unpaid', NULL),
(21, 22, '2025-12-11', '2025-12-26', 10174.20, 0.00, 'unpaid', NULL),
(22, 23, '2025-12-11', '2025-12-26', 17400.00, 0.00, 'unpaid', NULL),
(23, 24, '2025-12-17', '2026-01-01', 172.50, 0.00, 'unpaid', NULL),
(24, 25, '2025-12-17', '2026-01-01', 541.50, 0.00, 'unpaid', NULL),
(25, 26, '2025-12-17', '2026-01-01', 1078.50, 0.00, 'unpaid', NULL),
(26, 27, '2026-01-09', '2026-01-24', 3030.00, 0.00, 'unpaid', NULL);

-- --------------------------------------------------------

--
-- Table structure for table `customer`
--

CREATE TABLE `customer` (
  `cust_id` int NOT NULL,
  `name` varchar(100) COLLATE utf8mb4_general_ci NOT NULL,
  `address` text COLLATE utf8mb4_general_ci NOT NULL,
  `type` enum('household','business','government') COLLATE utf8mb4_general_ci NOT NULL,
  `reg_date` date DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `customer`
--

INSERT INTO `customer` (`cust_id`, `name`, `address`, `type`, `reg_date`) VALUES
(1, 'John Doe', '123 Galle Road, Colombo', 'household', '2025-11-04'),
(2, 'Bob Mack', 'Colombo 07', 'business', NULL),
(3, 'Nimal Perera', '12 Galle Road, Colombo 03', 'household', '2023-01-15'),
(4, 'Chamari Silva', '45 Kandy Road, Kandy', 'household', '2023-02-20'),
(5, 'Rajitha Fernando', '78 Galle Face, Colombo 05', 'household', '2023-03-10'),
(6, 'Dinusha Gunawardena', '23 Temple Road, Kandy', 'household', '2023-04-05'),
(7, 'Tharindu Jayasinghe', '56 Marine Drive, Colombo 03', 'household', '2023-05-12'),
(8, 'Yasodha Rajapakse', '89 Nawala Road, Nugegoda', 'household', '2023-06-18'),
(9, 'ABC Traders Pvt Ltd', '100 Union Place, Colombo 02', 'business', '2022-11-30'),
(10, 'Kandy Bakery & Confectionery', '34 Peradeniya Road, Kandy', 'business', '2023-01-25'),
(11, 'Galle Seafood Exporters', '12 Harbor Road, Galle', 'business', '2023-03-22'),
(12, 'Colombo Municipal Council', 'Town Hall, Colombo 07', 'government', '2022-10-01'),
(13, 'Kandy District Secretariat', 'Secretariat Road, Kandy', 'government', '2022-10-05'),
(14, 'University of Peradeniya', 'Peradeniya, Kandy', 'government', '2022-09-15'),
(15, 'Jayalath Alwis', '12 Galle Road, Colombo 03', 'household', NULL),
(16, 'Samantha Perera', '45 Kandy Road, Kandy', 'household', NULL),
(17, 'ABC Traders Pvt Ltd', '100 Union Place, Colombo 02', 'business', NULL),
(18, 'Janani Perera', '42/1 Galle Road, Colombo', 'household', NULL),
(19, 'Janani Peris', '39/4 Galle Road Colombo', 'household', NULL);

-- --------------------------------------------------------

--
-- Stand-in structure for view `dailyrevenuereport`
-- (See below for the actual view)
--
CREATE TABLE `dailyrevenuereport` (
`payment_date` date
,`method` enum('cash','card','online','cheque')
,`num_transactions` bigint
,`total_collected` decimal(32,2)
);

-- --------------------------------------------------------

--
-- Table structure for table `meter`
--

CREATE TABLE `meter` (
  `meter_id` int NOT NULL,
  `cust_id` int NOT NULL,
  `util_id` int NOT NULL,
  `install_date` date NOT NULL,
  `status` enum('active','inactive','disconnected') COLLATE utf8mb4_general_ci DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `meter`
--

INSERT INTO `meter` (`meter_id`, `cust_id`, `util_id`, `install_date`, `status`) VALUES
(1, 1, 2, '2025-11-02', 'active'),
(2, 1, 1, '2023-01-20', 'active'),
(3, 1, 2, '2023-01-20', 'active'),
(4, 2, 1, '2023-02-25', 'active'),
(5, 2, 3, '2023-02-25', 'active'),
(6, 3, 1, '2023-03-15', 'active'),
(7, 4, 1, '2023-04-10', 'active'),
(8, 4, 2, '2023-04-10', 'active'),
(9, 5, 1, '2023-05-20', 'active'),
(10, 5, 2, '2023-05-20', 'active'),
(11, 5, 3, '2023-05-20', 'active'),
(12, 6, 1, '2023-06-25', 'active'),
(13, 7, 1, '2022-12-05', 'active'),
(14, 7, 2, '2022-12-05', 'active'),
(15, 8, 1, '2023-02-01', 'active'),
(16, 9, 1, '2023-04-01', 'active'),
(17, 9, 2, '2023-04-01', 'active'),
(18, 10, 1, '2022-10-10', 'active'),
(19, 10, 2, '2022-10-10', 'active');

-- --------------------------------------------------------

--
-- Stand-in structure for view `monthlyrevenuereport`
-- (See below for the actual view)
--
CREATE TABLE `monthlyrevenuereport` (
`year` int
,`month` int
,`utility` varchar(20)
,`method` enum('cash','card','online','cheque')
,`transactions` bigint
,`revenue` decimal(32,2)
);

-- --------------------------------------------------------

--
-- Table structure for table `payment`
--

CREATE TABLE `payment` (
  `payment_id` int NOT NULL,
  `bill_id` int NOT NULL,
  `amount_paid` decimal(10,2) NOT NULL,
  `payment_date` date NOT NULL DEFAULT (curdate()),
  `method` enum('cash','card','online','cheque') COLLATE utf8mb4_general_ci NOT NULL,
  `receipt_no` varchar(50) COLLATE utf8mb4_general_ci DEFAULT NULL,
  `notes` text COLLATE utf8mb4_general_ci
) ;

--
-- Dumping data for table `payment`
--

INSERT INTO `payment` (`payment_id`, `bill_id`, `amount_paid`, `payment_date`, `method`, `receipt_no`, `notes`) VALUES
(1, 4, 665.00, '2025-11-25', 'cash', NULL, NULL),
(2, 11, 845.00, '2025-11-26', 'cash', NULL, NULL),
(3, 18, 8100.00, '2025-11-26', 'card', NULL, NULL),
(4, 14, 9120.00, '2025-12-11', 'cash', NULL, NULL),
(5, 15, 1080.00, '2025-12-11', 'card', NULL, NULL),
(6, 10, 3678.00, '2025-12-11', 'online', NULL, NULL),
(7, 12, 2310.00, '2025-12-17', 'card', NULL, NULL),
(8, 21, 10174.00, '2025-12-17', 'card', NULL, NULL),
(9, 6, 1950.00, '2025-12-17', 'cash', NULL, NULL),
(10, 19, 345.00, '2025-12-17', 'online', NULL, NULL),
(11, 3, 3610.00, '2026-01-09', 'cash', NULL, NULL),
(12, 16, 7870.00, '2026-01-09', 'card', NULL, NULL),
(13, 9, 665.00, '2026-01-09', 'cash', NULL, NULL),
(14, 25, 1078.00, '2026-01-09', 'online', NULL, NULL);

--
-- Triggers `payment`
--
DELIMITER $$
CREATE TRIGGER `trg_payment_full_pay` AFTER INSERT ON `payment` FOR EACH ROW BEGIN
    DECLARE bill_total DECIMAL(10,2);
    DECLARE paid_so_far DECIMAL(10,2);
    
    -- Get total_due for the bill
    SELECT total_due INTO bill_total
    FROM Bill
    WHERE bill_id = NEW.bill_id;
    
    -- Sum all payments for this bill (including new one)
    SELECT COALESCE(SUM(amount_paid), 0) INTO paid_so_far
    FROM Payment
    WHERE bill_id = NEW.bill_id;
    
    -- If fully paid, update status
    IF paid_so_far >= bill_total THEN
        UPDATE Bill
        SET status = 'paid'
        WHERE bill_id = NEW.bill_id;
    END IF;
END
$$
DELIMITER ;
DELIMITER $$
CREATE TRIGGER `trg_payment_no_overpay` BEFORE INSERT ON `payment` FOR EACH ROW BEGIN
    DECLARE bill_total DECIMAL(10,2);
    DECLARE paid_so_far DECIMAL(10,2);
    DECLARE remaining DECIMAL(10,2);
    
    -- Get bill's total_due
    SELECT total_due INTO bill_total
    FROM Bill
    WHERE bill_id = NEW.bill_id;
    
    -- Sum existing payments (exclude NEW one — this is BEFORE INSERT)
    SELECT COALESCE(SUM(amount_paid), 0) INTO paid_so_far
    FROM Payment
    WHERE bill_id = NEW.bill_id;
    
    SET remaining = bill_total - paid_so_far;
    
    -- Block if new payment > remaining
    IF NEW.amount_paid > remaining THEN
        SIGNAL SQLSTATE '45000'
        SET MESSAGE_TEXT = 'Error: Payment exceeds remaining balance.';
    END IF;
END
$$
DELIMITER ;

-- --------------------------------------------------------

--
-- Table structure for table `reading`
--

CREATE TABLE `reading` (
  `reading_id` int NOT NULL,
  `meter_id` int NOT NULL,
  `reading_date` date NOT NULL,
  `current_reading` decimal(10,2) NOT NULL,
  `prev_reading` decimal(10,2) NOT NULL,
  `consumption` decimal(10,2) GENERATED ALWAYS AS ((`current_reading` - `prev_reading`)) STORED
) ;

--
-- Dumping data for table `reading`
--

INSERT INTO `reading` (`reading_id`, `meter_id`, `reading_date`, `current_reading`, `prev_reading`) VALUES
(1, 1, '2025-09-01', 1000.00, 850.00),
(2, 1, '2025-10-01', 1150.00, 1000.00),
(3, 1, '2025-10-01', 1250.00, 1100.00),
(4, 1, '2025-09-01', 1100.00, 950.00),
(5, 2, '2025-10-01', 85.00, 70.00),
(6, 3, '2025-10-01', 980.00, 850.00),
(7, 4, '2025-10-01', 45.00, 30.00),
(8, 5, '2025-10-01', 2100.00, 1980.00),
(9, 6, '2025-10-01', 1050.00, 920.00),
(10, 7, '2025-10-01', 92.00, 77.00),
(11, 8, '2025-10-01', 1420.00, 1280.00),
(12, 9, '2025-10-01', 110.00, 92.00),
(13, 10, '2025-10-01', 52.00, 35.00),
(14, 11, '2025-10-01', 890.00, 780.00),
(15, 12, '2025-10-01', 5200.00, 4800.00),
(16, 13, '2025-10-01', 210.00, 180.00),
(17, 14, '2025-10-01', 4850.00, 4500.00),
(18, 15, '2025-10-01', 6300.00, 5900.00),
(19, 1, '2025-10-01', 1250.00, 1100.00),
(20, 6, '2025-10-01', 85.00, 70.00),
(21, 11, '2025-11-01', 5200.00, 4800.00),
(22, 5, '2025-12-11', 516.21, 450.52),
(23, 9, '2025-12-09', 856.00, 452.00),
(24, 15, '2025-12-01', 56.10, 52.60),
(25, 16, '2025-12-01', 456.30, 428.20),
(26, 6, '2025-12-11', 86.50, 45.20),
(27, 5, '2026-01-09', 189.22, 165.22),
(28, 5, '2026-01-09', 2800.50, 2650.00);

-- --------------------------------------------------------

--
-- Table structure for table `tariff`
--

CREATE TABLE `tariff` (
  `tariff_id` int NOT NULL,
  `util_id` int NOT NULL,
  `min_unit` int NOT NULL,
  `max_unit` int NOT NULL,
  `rate_per_unit` decimal(6,2) NOT NULL,
  `fixed_charge` decimal(6,2) DEFAULT '0.00',
  `description` varchar(100) COLLATE utf8mb4_general_ci DEFAULT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `tariff`
--

INSERT INTO `tariff` (`tariff_id`, `util_id`, `min_unit`, `max_unit`, `rate_per_unit`, `fixed_charge`, `description`) VALUES
(1, 1, 0, 30, 0.15, 10.00, 'Domestic: 0-30 kWh'),
(2, 1, 31, 9999, 0.25, 10.00, 'Domestic: 31+ kWh'),
(3, 2, 0, 10, 1.00, 5.00, 'Water: 0-10 m³'),
(4, 2, 11, 9999, 2.00, 5.00, 'Water: 11+ m³'),
(5, 3, 0, 20, 0.80, 8.00, 'Gas: 0-20 m³'),
(6, 3, 21, 9999, 1.20, 8.00, 'Gas: 21+ m³'),
(7, 1, 0, 30, 7.85, 60.00, 'Domestic: 0-30 kWh'),
(8, 1, 31, 60, 10.00, 60.00, 'Domestic: 31-60 kWh'),
(9, 1, 61, 90, 27.75, 60.00, 'Domestic: 61-90 kWh'),
(10, 1, 91, 9999, 45.00, 60.00, 'Domestic: 91+ kWh'),
(11, 1, 0, 100, 15.00, 120.00, 'Commercial: 0-100 kWh'),
(12, 1, 101, 9999, 25.00, 120.00, 'Commercial: 101+ kWh'),
(13, 2, 0, 5, 25.00, 40.00, 'Water: 0-5 m³'),
(14, 2, 6, 10, 40.00, 40.00, 'Water: 6-10 m³'),
(15, 2, 11, 9999, 60.00, 40.00, 'Water: 11+ m³'),
(16, 2, 0, 25, 30.00, 80.00, 'Commercial/Govt: 0-25 m³'),
(17, 2, 26, 9999, 50.00, 80.00, 'Commercial/Govt: 26+ m³'),
(18, 3, 0, 15, 120.00, 150.00, 'Domestic: 0-15 m³'),
(19, 3, 16, 9999, 180.00, 150.00, 'Domestic: 16+ m³');

-- --------------------------------------------------------

--
-- Stand-in structure for view `topconsumersmonthly`
-- (See below for the actual view)
--
CREATE TABLE `topconsumersmonthly` (
`year` int
,`month` int
,`utility` varchar(20)
,`customer_name` varchar(100)
,`total_consumption` decimal(32,2)
,`consumption_display` varchar(81)
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `unpaidbillsreport`
-- (See below for the actual view)
--
CREATE TABLE `unpaidbillsreport` (
`bill_id` int
,`customer_name` varchar(100)
,`utility` varchar(20)
,`issue_date` date
,`due_date` date
,`amount_due` decimal(10,2)
,`amount_due_display` varchar(52)
,`days_overdue` int
);

-- --------------------------------------------------------

--
-- Stand-in structure for view `unpaidbillsview`
-- (See below for the actual view)
--
CREATE TABLE `unpaidbillsview` (
`bill_id` int
,`customer_name` varchar(100)
,`address` text
,`utility` varchar(20)
,`consumption` decimal(10,2)
,`amount` decimal(10,2)
,`total_due` decimal(10,2)
,`issue_date` date
,`due_date` date
,`days_overdue` int
);

-- --------------------------------------------------------

--
-- Table structure for table `utilitytype`
--

CREATE TABLE `utilitytype` (
  `util_id` int NOT NULL,
  `name` varchar(20) COLLATE utf8mb4_general_ci NOT NULL,
  `unit` varchar(10) COLLATE utf8mb4_general_ci NOT NULL
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci;

--
-- Dumping data for table `utilitytype`
--

INSERT INTO `utilitytype` (`util_id`, `name`, `unit`) VALUES
(1, 'Water', 'm³'),
(2, 'Electricity', 'kWh'),
(3, 'Gas', 'm³'),
(4, 'Electricity', 'kWh'),
(5, 'Water', 'm³'),
(6, 'Gas', 'm³');

-- --------------------------------------------------------

--
-- Stand-in structure for view `yearlyrevenuereport`
-- (See below for the actual view)
--
CREATE TABLE `yearlyrevenuereport` (
`year` int
,`utility` varchar(20)
,`total_transactions` bigint
,`annual_revenue` decimal(54,2)
,`annual_revenue_display` varchar(110)
);

-- --------------------------------------------------------

--
-- Structure for view `dailyrevenuereport`
--
DROP TABLE IF EXISTS `dailyrevenuereport`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `dailyrevenuereport`  AS SELECT `payment`.`payment_date` AS `payment_date`, `payment`.`method` AS `method`, count(0) AS `num_transactions`, sum(`payment`.`amount_paid`) AS `total_collected` FROM `payment` GROUP BY `payment`.`payment_date`, `payment`.`method` ;

-- --------------------------------------------------------

--
-- Structure for view `monthlyrevenuereport`
--
DROP TABLE IF EXISTS `monthlyrevenuereport`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `monthlyrevenuereport`  AS SELECT year(`p`.`payment_date`) AS `year`, month(`p`.`payment_date`) AS `month`, `u`.`name` AS `utility`, `p`.`method` AS `method`, count(0) AS `transactions`, sum(`p`.`amount_paid`) AS `revenue` FROM ((((`payment` `p` join `bill` `b` on((`p`.`bill_id` = `b`.`bill_id`))) join `reading` `r` on((`b`.`reading_id` = `r`.`reading_id`))) join `meter` `m` on((`r`.`meter_id` = `m`.`meter_id`))) join `utilitytype` `u` on((`m`.`util_id` = `u`.`util_id`))) GROUP BY `year`, `month`, `utility`, `p`.`method` ;

-- --------------------------------------------------------

--
-- Structure for view `topconsumersmonthly`
--
DROP TABLE IF EXISTS `topconsumersmonthly`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `topconsumersmonthly`  AS SELECT year(`r`.`reading_date`) AS `year`, month(`r`.`reading_date`) AS `month`, `u`.`name` AS `utility`, `c`.`name` AS `customer_name`, sum(`r`.`consumption`) AS `total_consumption`, concat(format(sum(`r`.`consumption`),2),(case `u`.`unit` when 'kWh' then ' kWh' when 'm³' then ' m³' else '' end)) AS `consumption_display` FROM (((`reading` `r` join `meter` `m` on((`r`.`meter_id` = `m`.`meter_id`))) join `customer` `c` on((`m`.`cust_id` = `c`.`cust_id`))) join `utilitytype` `u` on((`m`.`util_id` = `u`.`util_id`))) GROUP BY `year`, `month`, `utility`, `c`.`name` ;

-- --------------------------------------------------------

--
-- Structure for view `unpaidbillsreport`
--
DROP TABLE IF EXISTS `unpaidbillsreport`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `unpaidbillsreport`  AS SELECT `b`.`bill_id` AS `bill_id`, `c`.`name` AS `customer_name`, `u`.`name` AS `utility`, `b`.`issue_date` AS `issue_date`, `b`.`due_date` AS `due_date`, `b`.`total_due` AS `amount_due`, concat('LKR ',format(`b`.`total_due`,2)) AS `amount_due_display`, (to_days(curdate()) - to_days(`b`.`due_date`)) AS `days_overdue` FROM ((((`bill` `b` join `reading` `r` on((`b`.`reading_id` = `r`.`reading_id`))) join `meter` `m` on((`r`.`meter_id` = `m`.`meter_id`))) join `customer` `c` on((`m`.`cust_id` = `c`.`cust_id`))) join `utilitytype` `u` on((`m`.`util_id` = `u`.`util_id`))) WHERE (`b`.`status` = 'unpaid') ;

-- --------------------------------------------------------

--
-- Structure for view `unpaidbillsview`
--
DROP TABLE IF EXISTS `unpaidbillsview`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `unpaidbillsview`  AS SELECT `b`.`bill_id` AS `bill_id`, `c`.`name` AS `customer_name`, `c`.`address` AS `address`, `u`.`name` AS `utility`, `r`.`consumption` AS `consumption`, `b`.`amount` AS `amount`, `b`.`total_due` AS `total_due`, `b`.`issue_date` AS `issue_date`, `b`.`due_date` AS `due_date`, (to_days(curdate()) - to_days(`b`.`due_date`)) AS `days_overdue` FROM ((((`bill` `b` join `reading` `r` on((`b`.`reading_id` = `r`.`reading_id`))) join `meter` `m` on((`r`.`meter_id` = `m`.`meter_id`))) join `customer` `c` on((`m`.`cust_id` = `c`.`cust_id`))) join `utilitytype` `u` on((`m`.`util_id` = `u`.`util_id`))) WHERE ((`b`.`status` = 'unpaid') AND (`b`.`due_date` < curdate())) ;

-- --------------------------------------------------------

--
-- Structure for view `yearlyrevenuereport`
--
DROP TABLE IF EXISTS `yearlyrevenuereport`;

CREATE ALGORITHM=UNDEFINED DEFINER=`root`@`localhost` SQL SECURITY DEFINER VIEW `yearlyrevenuereport`  AS SELECT `monthlyrevenuereport`.`year` AS `year`, `monthlyrevenuereport`.`utility` AS `utility`, count(0) AS `total_transactions`, sum(`monthlyrevenuereport`.`revenue`) AS `annual_revenue`, concat('LKR ',format(sum(`monthlyrevenuereport`.`revenue`),2)) AS `annual_revenue_display` FROM `monthlyrevenuereport` GROUP BY `monthlyrevenuereport`.`year`, `monthlyrevenuereport`.`utility` ;

--
-- Indexes for dumped tables
--

--
-- Indexes for table `bill`
--
ALTER TABLE `bill`
  ADD PRIMARY KEY (`bill_id`),
  ADD KEY `fk_bill_reading` (`reading_id`);

--
-- Indexes for table `customer`
--
ALTER TABLE `customer`
  ADD PRIMARY KEY (`cust_id`);

--
-- Indexes for table `meter`
--
ALTER TABLE `meter`
  ADD PRIMARY KEY (`meter_id`),
  ADD KEY `fk_meter_customer` (`cust_id`),
  ADD KEY `fk_meter_utility` (`util_id`);

--
-- Indexes for table `payment`
--
ALTER TABLE `payment`
  ADD PRIMARY KEY (`payment_id`),
  ADD KEY `fk_payment_bill` (`bill_id`);

--
-- Indexes for table `reading`
--
ALTER TABLE `reading`
  ADD PRIMARY KEY (`reading_id`),
  ADD KEY `fk_reading_meter` (`meter_id`);

--
-- Indexes for table `tariff`
--
ALTER TABLE `tariff`
  ADD PRIMARY KEY (`tariff_id`),
  ADD KEY `fk_tariff_utility` (`util_id`);

--
-- Indexes for table `utilitytype`
--
ALTER TABLE `utilitytype`
  ADD PRIMARY KEY (`util_id`);

--
-- AUTO_INCREMENT for dumped tables
--

--
-- AUTO_INCREMENT for table `bill`
--
ALTER TABLE `bill`
  MODIFY `bill_id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `customer`
--
ALTER TABLE `customer`
  MODIFY `cust_id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=20;

--
-- AUTO_INCREMENT for table `meter`
--
ALTER TABLE `meter`
  MODIFY `meter_id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=20;

--
-- AUTO_INCREMENT for table `payment`
--
ALTER TABLE `payment`
  MODIFY `payment_id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `reading`
--
ALTER TABLE `reading`
  MODIFY `reading_id` int NOT NULL AUTO_INCREMENT;

--
-- AUTO_INCREMENT for table `tariff`
--
ALTER TABLE `tariff`
  MODIFY `tariff_id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=20;

--
-- AUTO_INCREMENT for table `utilitytype`
--
ALTER TABLE `utilitytype`
  MODIFY `util_id` int NOT NULL AUTO_INCREMENT, AUTO_INCREMENT=7;

--
-- Constraints for dumped tables
--

--
-- Constraints for table `bill`
--
ALTER TABLE `bill`
  ADD CONSTRAINT `fk_bill_reading` FOREIGN KEY (`reading_id`) REFERENCES `reading` (`reading_id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `meter`
--
ALTER TABLE `meter`
  ADD CONSTRAINT `fk_meter_customer` FOREIGN KEY (`cust_id`) REFERENCES `customer` (`cust_id`) ON DELETE CASCADE ON UPDATE CASCADE,
  ADD CONSTRAINT `fk_meter_utility` FOREIGN KEY (`util_id`) REFERENCES `utilitytype` (`util_id`) ON DELETE RESTRICT ON UPDATE CASCADE;

--
-- Constraints for table `payment`
--
ALTER TABLE `payment`
  ADD CONSTRAINT `fk_payment_bill` FOREIGN KEY (`bill_id`) REFERENCES `bill` (`bill_id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `reading`
--
ALTER TABLE `reading`
  ADD CONSTRAINT `fk_reading_meter` FOREIGN KEY (`meter_id`) REFERENCES `meter` (`meter_id`) ON DELETE CASCADE ON UPDATE CASCADE;

--
-- Constraints for table `tariff`
--
ALTER TABLE `tariff`
  ADD CONSTRAINT `fk_tariff_utility` FOREIGN KEY (`util_id`) REFERENCES `utilitytype` (`util_id`) ON DELETE CASCADE ON UPDATE CASCADE;
COMMIT;

/*!40101 SET CHARACTER_SET_CLIENT=@OLD_CHARACTER_SET_CLIENT */;
/*!40101 SET CHARACTER_SET_RESULTS=@OLD_CHARACTER_SET_RESULTS */;
/*!40101 SET COLLATION_CONNECTION=@OLD_COLLATION_CONNECTION */;
