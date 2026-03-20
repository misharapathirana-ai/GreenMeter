<?php
require 'config.php';
if ($_POST) {
    $stmt = $pdo->prepare("INSERT INTO Reading (meter_id, reading_date, current_reading, prev_reading) 
                           VALUES (?,?,?,?)");
    $stmt->execute([
        $_POST['meter_id'], 
        $_POST['reading_date'], 
        $_POST['current'], 
        $_POST['previous']
    ]);
    header("Location: generate_bill.php?reading_id=" . $pdo->lastInsertId());
    exit;
}

// Get active meters for dropdown
$meters = $pdo->query("SELECT m.meter_id, c.name, u.name AS util 
                       FROM Meter m 
                       JOIN Customer c ON m.cust_id = c.cust_id 
                       JOIN UtilityType u ON m.util_id = u.util_id 
                       WHERE m.status = 'active'")->fetchAll();
?>
<!DOCTYPE html>
<html><head><title>Add Reading</title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
</head><body>
<div class="container mt-4">
    <h3>Enter Meter Reading</h3>
    <form method="post">
        <div class="mb-3">
            <label>Meter</label>
            <select name="meter_id" class="form-control" required>
                <?php foreach ($meters as $m): ?>
                <option value="<?= $m['meter_id'] ?>">
                    #<?= $m['meter_id'] ?> - <?= $m['name'] ?> (<?= $m['util'] ?>)
                </option>
                <?php endforeach; ?>
            </select>
        </div>
        <div class="row">
            <div class="col"><label>Previous Reading</label>
            <input type="number" step="0.01" name="previous" class="form-control" required></div>
            <div class="col"><label>Current Reading</label>
            <input type="number" step="0.01" name="current" class="form-control" required></div>
        </div>
        <div class="mb-3 mt-2">
            <label>Reading Date</label>
            <input type="date" name="reading_date" class="form-control" value="<?= date('Y-m-d') ?>" required>
        </div>
        <button type="submit" class="btn btn-success">Save Reading → Generate Bill</button>
    </form>
</div>
</body></html>
