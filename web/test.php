<?php
require 'config.php';
echo "<h2> Connected to UMS database!</h2>";

// Test a query
$stmt = $pdo->query("SELECT COUNT(*) AS cnt FROM Customer");
$row = $stmt->fetch();
echo "<p>• Customers in DB: " . $row['cnt'] . "</p>";
?>
