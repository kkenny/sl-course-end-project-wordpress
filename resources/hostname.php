<?php
header('Content-Type: text/html; charset=utf-8');
$hostname = gethostname();
$stack_name = '';
$stack_file = '/var/www/html/stack.txt';
if (file_exists($stack_file)) {
    $stack_name = trim(file_get_contents($stack_file));
}
?>
<!DOCTYPE html>
<html>
<head>
    <title>Server Hostname</title>
    <style>
        body {
            font-family: Arial, sans-serif;
            display: flex;
            justify-content: center;
            align-items: center;
            height: 100vh;
            margin: 0;
            background-color: #f5f5f5;
        }
        .container {
            text-align: center;
            background-color: white;
            padding: 40px;
            border-radius: 8px;
            box-shadow: 0 2px 10px rgba(0,0,0,0.1);
        }
        h1 {
            color: #333;
            margin-bottom: 20px;
        }
        .stack-name {
            font-size: 20px;
            color: #666;
            font-weight: bold;
            padding: 15px;
            background-color: #e8f4f8;
            border-radius: 4px;
            display: inline-block;
            margin-bottom: 20px;
        }
        .hostname {
            font-size: 24px;
            color: #0073aa;
            font-weight: bold;
            padding: 20px;
            background-color: #f0f0f0;
            border-radius: 4px;
            display: inline-block;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>Server Hostname</h1>
        <?php if (!empty($stack_name)): ?>
        <div class="stack-name">Stack: <?php echo htmlspecialchars($stack_name); ?></div>
        <?php endif; ?>
        <div class="hostname"><?php echo htmlspecialchars($hostname); ?></div>
    </div>
</body>
</html>

