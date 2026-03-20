<?php
require 'config.php';
if ($_POST) {
    $stmt = $pdo->prepare("INSERT INTO Customer (name, address, type) VALUES (?,?,?)");
    $stmt->execute([$_POST['name'], $_POST['address'], $_POST['type']]);
    header("Location: index.php?msg=Customer+added");
    exit;
}
?>
<!DOCTYPE html>
<html><head><title>Add Customer</title>
<link href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.0/dist/css/bootstrap.min.css" rel="stylesheet">
</head><body>
<div class="container mt-4">
    <h3>Add New Customer</h3>
    <form method="post">
        <div class="mb-3">
            <label>Name</label>
            <input type="text" name="name" class="form-control" required>
        </div>
        <div class="mb-3">
            <label>Address</label>
            <textarea name="address" class="form-control" required></textarea>
        </div>
        <div class="mb-3">
            <label>Type</label>
            <select name="type" class="form-control" required>
                <option value="household">Household</option>
                <option value="business">Business</option>
                <option value="government">Government</option>
            </select>
        </div>
        <button type="submit" class="btn btn-primary">Save Customer</button>
        <a href="index.php" class="btn btn-secondary">Cancel</a>
    </form>
</div>
</body></html>
