<?php
require 'config.php';
$reading_id = $_GET['reading_id'] ?? null;

if ($_POST && $reading_id) {
    // Call stored procedure
    $stmt = $pdo->prepare("CALL GenerateBillForReading(?, @bill_id)");
    $stmt->execute([$reading_id]);
    
    $result = $pdo->query("SELECT @bill_id AS bill_id")->fetch();
    $bill_id = $result['bill_id'];
    
    header("Location: index.php?msg=Bill+$bill_id+generated");
    exit;
}
?>
<!DOCTYPE html>
<html><head><title>Generate Bill</title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
</head><body>
<div class="container mt-4">
    <h3>Generate Bill for Reading #<?= htmlspecialchars($reading_id) ?></h3>
    
    <?php if ($reading_id): ?>
    <div class="alert alert-info">
        <strong>Preview:</strong> Amount will be calculated using tariff slabs.
        <br>Bill due in 15 days.
    </div>
    <form method="post">
        <input type="hidden" name="reading_id" value="<?= $reading_id ?>">
        <button type="submit" class="btn btn-success btn-lg">✅ Generate Bill</button>
        <a href="index.php" class="btn btn-secondary">Cancel</a>
    </form>
    <?php else: ?>
    <div class="alert alert-warning">No reading ID provided.</div>
    <a href="add_reading.php" class="btn btn-primary">Enter New Reading</a>
    <?php endif; ?>
</div>
</body></html>