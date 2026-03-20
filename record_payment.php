<?php
require 'config.php';
$bills = $pdo->query("SELECT b.bill_id, c.name, u.name AS util, b.total_due, b.status
                      FROM Bill b
                      JOIN Reading r ON b.reading_id = r.reading_id
                      JOIN Meter m ON r.meter_id = m.meter_id
                      JOIN Customer c ON m.cust_id = c.cust_id
                      JOIN UtilityType u ON m.util_id = u.util_id
                      WHERE b.status = 'unpaid'")->fetchAll();

if ($_POST) {
    $stmt = $pdo->prepare("INSERT INTO Payment (bill_id, amount_paid, method) VALUES (?,?,?)");
    try {
        $stmt->execute([$_POST['bill_id'], $_POST['amount'], $_POST['method']]);
        header("Location: index.php?msg=Payment+recorded");
    } catch (PDOException $e) {
        $error = $e->getMessage();
    }
}
?>
<!DOCTYPE html>
<html><head><title>Record Payment</title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
</head><body>
<div class="container mt-4">
    <h3>Record Customer Payment</h3>
    
    <?php if (!empty($error)): ?>
    <div class="alert alert-danger"><?= htmlspecialchars($error) ?></div>
    <?php endif; ?>

    <form method="post">
        <div class="mb-3">
            <label>Bill</label>
            <select name="bill_id" class="form-control" required>
                <?php foreach ($bills as $b): ?>
                <option value="<?= $b['bill_id'] ?>">
                    Bill #<?= $b['bill_id'] ?> - <?= $b['name'] ?> (<?= $b['util'] ?>) — ₹<?= $b['total_due'] ?> (<?= $b['status'] ?>)
                </option>
                <?php endforeach; ?>
            </select>
        </div>
        <div class="row">
            <div class="col"><label>Amount</label>
            <input type="number" step="0.01" name="amount" class="form-control" required></div>
            <div class="col"><label>Method</label>
            <select name="method" class="form-control">
                <option value="cash">Cash</option>
                <option value="card">Card</option>
                <option value="online">Online</option>
            </select></div>
        </div>
        <button type="submit" class="btn btn-warning mt-3">💰 Record Payment</button>
    </form>
</div>
</body></html>