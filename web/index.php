<!DOCTYPE html>
<html>
<head>
    <title>UMS Dashboard</title>
    <link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
</head>
<body>
<div class="container mt-4">
    <h2>Utility Management System</h2>
    
    <div class="row">
        <div class="col-md-6">
            <h4>⚠️ Overdue Unpaid Bills</h4>
            <table class="table table-striped table-sm">
                <thead><tr><th>Bill #</th><th>Customer</th><th>Utility</th><th>Due</th><th>Days</th></tr></thead>
                <tbody>
                <?php
                require 'config.php';
                $sql = "SELECT bill_id, customer_name, utility, due_date, days_overdue 
                        FROM UnpaidBillsView ORDER BY days_overdue DESC LIMIT 5";
                foreach ($pdo->query($sql) as $row) {
                    echo "<tr><td>{$row['bill_id']}</td><td>{$row['customer_name']}</td>
                          <td>{$row['utility']}</td><td>{$row['due_date']}</td>
                          <td class='text-danger'>{$row['days_overdue']}</td></tr>";
                }
                ?>
                </tbody>
            </table>
        </div>
        
        <div class="col-md-6">
            <h4>💰 Today’s Revenue</h4>
            <table class="table table-success table-sm">
                <thead><tr><th>Method</th><th>Transactions</th><th>Total</th></tr></thead>
                <tbody>
                <?php
                $sql = "SELECT method, num_transactions, total_collected 
                        FROM DailyRevenueReport WHERE payment_date = CURDATE()";
                foreach ($pdo->query($sql) as $row) {
                    echo "<tr><td>{$row['method']}</td><td>{$row['num_transactions']}</td>
                          <td>₹" . number_format($row['total_collected'], 2) . "</td></tr>";
                }
                ?>
                </tbody>
            </table>
        </div>
    </div>

    <div class="btn-group mt-3">
        <a href="add_customer.php" class="btn btn-primary">+ Customer</a>
        <a href="add_reading.php" class="btn btn-secondary">+ Reading</a>
        <a href="generate_bill.php" class="btn btn-success">Generate Bill</a>
        <a href="record_payment.php" class="btn btn-warning">Record Payment</a>
    </div>
</div>
</body>
</html>
