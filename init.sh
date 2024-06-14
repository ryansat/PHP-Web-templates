# Create project directories
mkdir -p project/backend/config project/backend/controllers project/backend/models project/backend/middleware project/backend/routes project/frontend project/data

# Create .env file
cat <<EOL > project/.env
DATABASE_TYPE=mysql # or postgres
DATABASE_HOST=localhost
DATABASE_PORT=3306 # or 5432 for PostgreSQL
DATABASE_NAME=myapp
DATABASE_USER=root
DATABASE_PASSWORD=password
SECRET_KEY=your_secret_key
EOL

# Create config/database.php
cat <<EOL > project/backend/config/database.php
<?php
require __DIR__ . '/../vendor/autoload.php';
use Dotenv\Dotenv;

\$dotenv = Dotenv::createImmutable(__DIR__ . '/../');
\$dotenv->load();

\$dbType = \$_ENV['DATABASE_TYPE'];
\$host = \$_ENV['DATABASE_HOST'];
\$port = \$_ENV['DATABASE_PORT'];
\$dbName = \$_ENV['DATABASE_NAME'];
\$user = \$_ENV['DATABASE_USER'];
\$password = \$_ENV['DATABASE_PASSWORD'];

try {
    \$dsn = "\$dbType:host=\$host;port=\$port;dbname=\$dbName";
    \$pdo = new PDO(\$dsn, \$user, \$password);
    \$pdo->setAttribute(PDO::ATTR_ERRMODE, PDO::ERRMODE_EXCEPTION);
} catch (PDOException \$e) {
    die('Database connection failed: ' . \$e->getMessage());
}

return \$pdo;
EOL

# Create models/User.php
cat <<EOL > project/backend/models/User.php
<?php
require_once __DIR__ . '/../config/database.php';

class User {
    private \$pdo;
    
    public function __construct() {
        \$this->pdo = require __DIR__ . '/../config/database.php';
    }
    
    public function findByUsername(\$username) {
        \$stmt = \$this->pdo->prepare('SELECT * FROM users WHERE username = :username');
        \$stmt->execute(['username' => \$username]);
        return \$stmt->fetch(PDO::FETCH_ASSOC);
    }

    public function create(\$username, \$password) {
        \$stmt = \$this->pdo->prepare('INSERT INTO users (username, password) VALUES (:username, :password)');
        \$stmt->execute(['username' => \$username, 'password' => password_hash(\$password, PASSWORD_DEFAULT)]);
    }
}
EOL

# Create controllers/AuthController.php
cat <<EOL > project/backend/controllers/AuthController.php
<?php
require_once __DIR__ . '/../models/User.php';
require __DIR__ . '/../vendor/autoload.php';
use Firebase\JWT\JWT;

class AuthController {
    private \$user;

    public function __construct() {
        \$this->user = new User();
    }

    public function login(\$username, \$password) {
        \$user = \$this->user->findByUsername(\$username);
        if (!\$user || !password_verify(\$password, \$user['password'])) {
            http_response_code(401);
            echo json_encode(['error' => 'Invalid credentials']);
            return;
        }
        \$token = JWT::encode(['userId' => \$user['id']], \$_ENV['SECRET_KEY']);
        echo json_encode(['token' => \$token]);
    }

    public function register(\$username, \$password) {
        \$this->user->create(\$username, \$password);
        http_response_code(201);
        echo json_encode(['message' => 'User registered']);
    }
}
EOL

# Create middleware/authMiddleware.php
cat <<EOL > project/backend/middleware/authMiddleware.php
<?php
require __DIR__ . '/../vendor/autoload.php';
use Firebase\JWT\JWT;

function authMiddleware() {
    \$headers = getallheaders();
    if (!isset(\$headers['Authorization'])) {
        http_response_code(401);
        echo json_encode(['error' => 'Access denied']);
        exit();
    }
    \$token = \$headers['Authorization'];
    try {
        \$decoded = JWT::decode(\$token, \$_ENV['SECRET_KEY'], ['HS256']);
        return \$decoded;
    } catch (Exception \$e) {
        http_response_code(400);
        echo json_encode(['error' => 'Invalid token']);
        exit();
    }
}
EOL

# Create controllers/CrudController.php
cat <<EOL > project/backend/controllers/CrudController.php
<?php
require_once __DIR__ . '/../middleware/authMiddleware.php';

class CrudController {
    private \$items = [];

    public function __construct() {
        \$this->items = json_decode(file_get_contents(__DIR__ . '/../data/items.json'), true) ?: [];
    }

    public function getAll() {
        echo json_encode(\$this->items);
    }

    public function create(\$item) {
        \$this->items[] = \$item;
        file_put_contents(__DIR__ . '/../data/items.json', json_encode(\$this->items));
        echo json_encode(\$item);
    }

    public function update(\$id, \$newItem) {
        foreach (\$this->items as &\$item) {
            if (\$item['id'] == \$id) {
                \$item = \$newItem;
                break;
            }
        }
        file_put_contents(__DIR__ . '/../data/items.json', json_encode(\$this->items));
        echo json_encode(\$newItem);
    }

    public function delete(\$id) {
        \$this->items = array_filter(\$this->items, function(\$item) use (\$id) {
            return \$item['id'] != \$id;
        });
        file_put_contents(__DIR__ . '/../data/items.json', json_encode(\$this->items));
        http_response_code(204);
    }
}
EOL

# Create routes/auth.php
cat <<EOL > project/backend/routes/auth.php
<?php
require_once __DIR__ . '/../controllers/AuthController.php';

\$authController = new AuthController();

if (\$_SERVER['REQUEST_METHOD'] === 'POST') {
    \$data = json_decode(file_get_contents('php://input'), true);
    if (strpos(\$_SERVER['REQUEST_URI'], 'register') !== false) {
        \$authController->register(\$data['username'], \$data['password']);
    } else {
        \$authController->login(\$data['username'], \$data['password']);
    }
}
EOL

# Create routes/crud.php
cat <<EOL > project/backend/routes/crud.php
<?php
require_once __DIR__ . '/../controllers/CrudController.php';
require_once __DIR__ . '/../middleware/authMiddleware.php';

\$crudController = new CrudController();
\$auth = authMiddleware();

if (\$_SERVER['REQUEST_METHOD'] === 'GET') {
    \$crudController->getAll();
} elseif (\$_SERVER['REQUEST_METHOD'] === 'POST') {
    \$data = json_decode(file_get_contents('php://input'), true);
    \$crudController->create(\$data);
} elseif (\$_SERVER['REQUEST_METHOD'] === 'PUT') {
    \$data = json_decode(file_get_contents('php://input'), true);
    \$id = basename(\$_SERVER['REQUEST_URI']);
    \$crudController->update(\$id, \$data);
} elseif (\$_SERVER['REQUEST_METHOD'] === 'DELETE') {
    \$id = basename(\$_SERVER['REQUEST_URI']);
    \$crudController->delete(\$id);
}
EOL

# Create index.php
cat <<EOL > project/backend/index.php
<?php
header('Content-Type: application/json');
\$requestUri = \$_SERVER['REQUEST_URI'];

if (strpos(\$requestUri, '/auth') === 0) {
    require_once __DIR__ . '/routes/auth.php';
} elseif (strpos(\$requestUri, '/crud') === 0) {
    require_once __DIR__ . '/routes/crud.php';
}
EOL

# Create frontend files
cat <<EOL > project/frontend/index.html
<!DOCTYPE html>
<html>
<head>
  <title>CRUD App</title>
</head>
<body>
  <h1>CRUD App</h1>
  <div id="app">
    <input type="text" id="item-input" placeholder="Enter item" />
    <button onclick="addItem()">Add Item</button>
    <ul id="items-list"></ul>
  </div>
  <script src="main.js"></script>
</body>
</html>
EOL

cat <<EOL > project/frontend/login.html
<!DOCTYPE html>
<html>
<head>
  <title>Login</title>
</head>
<body>
  <h1>Login</h1>
  <div id="login-form">
    <input type="text" id="username" placeholder="Username" />
    <input type="password" id="password" placeholder="Password" />
    <button onclick="login()">Login</button>
  </div>
  <script src="main.js"></script>
</body>
</html>
EOL

cat <<EOL > project/frontend/main.js
const API_URL = 'http://localhost/project/backend/index.php';

async function login() {
  const username = document.getElementById('username').value;
  const password = document.getElementById('password').value;
  
  const response = await fetch(\`\${API_URL}/auth/login\`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify({ username, password })
  });
  
  const data = await response.json();
  if (response.ok) {
    localStorage.setItem('token', data.token);
    window.location.href = 'index.html';
  } else {
    alert('Login failed');
  }
}

async function addItem() {
  const item = document.getElementById('item-input').value;
  const token = localStorage.getItem('token');
  
  const response = await fetch(\`\${API_URL}/crud\`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Authorization': token },
    body: JSON.stringify({ item })
  });
  
  const newItem = await response.json();
  document.getElementById('items-list').innerHTML += \`<li>\${newItem.item}</li>\`;
}

async function fetchItems() {
  const token = localStorage.getItem('token');
  
  const response = await fetch(\`\${API_URL}/crud\`, {
    headers: { 'Authorization': token }
  });
  
  const items = await response.json();
  const itemsList = document.getElementById('items-list');
  itemsList.innerHTML = '';
  items.forEach(item => {
    itemsList.innerHTML += \`<li>\${item.item}</li>\`;
  });
}

if (localStorage.getItem('token')) {
  fetchItems();
}
EOL

# Install Composer dependencies
cd project/backend
composer require vlucas/phpdotenv firebase/php-jwt

echo "Project initialized successfully."
```

### How to Use the Script

1. Save the script above as `init.sh` in your project directory.
2. Make the script executable by running:

```bash
chmod +x init.sh
```

3. Run the script by executing:

```bash
./init.sh
```

This script will create the necessary directory structure, files, and install dependencies using Composer. Once the script completes, you can start your application by navigating to the `project/backend` directory and serving it with your preferred PHP web server (e.g., `php -S localhost:8000`).