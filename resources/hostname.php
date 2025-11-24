<?php
header('Content-Type: text/html; charset=utf-8');
$hostname = gethostname();
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
        <div class="hostname"><?php echo htmlspecialchars($hostname); ?></div>
    </div>
</body>
</html>

