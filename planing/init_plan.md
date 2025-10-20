# OLX Integration MVP - Technical Implementation Plan

## Executive Summary

This document outlines the complete technical plan for building `olx_integration`, a Rails 8 MVP that enables sellers to import products through:
1. **CSV file uploads** with intelligent column mapping
2. **Web scraping** from https://ba.e-cat.intercars.eu/bs/ using authenticated sessions

**Key Decisions (Updated):**
- **Database**: SQLite for development (standalone, no external DB needed)
- **Authentication**: Devise with passwordless authentication (magic links)
- **Scraping**: Playwright scripts (Node.js) called from Rails via ScraperService
- **Jobs**: Synchronous processing initially (no Sidekiq/Redis required)
- **Architecture**: Standalone Rails 8 app with integrated Playwright scripts

---

## 1. Requirements Analysis

### Core Features (MVP Scope)
1. **Multi-tenant Shop Management**
   - Users can create/manage multiple shops
   - Role-based access (owners, members)
   - Shop-scoped product catalog

2. **CSV Import Flow**
   - Upload CSV files (any encoding, common separators)
   - Automatic column detection and mapping
   - Preview first 10 rows
   - Manual mapping adjustment
   - Background processing with progress tracking
   - Error handling and import logs

3. **Web Scraping Integration**
   - Authenticated login to Intercars catalog
   - Respectful scraping (1s throttle, exponential backoff)
   - Product data extraction (title, SKU, price, images, specs)
   - CAPTCHA/2FA detection (stop and report, no bypass)
   - Structured JSON output

4. **Product Management**
   - Staging table (ImportedProduct) for raw data
   - Normalized Product table with JSONB specs
   - Image management via ActiveStorage
   - Source tracking (CSV vs scraped)

5. **Background Job Processing**
   - Async CSV processing
   - Async scraping
   - Image downloads
   - Retry logic and error logging

---

## 2. Architecture Overview

### System Components (Updated)

```
┌─────────────────────────────────────────────────────────┐
│               Rails 8 Application (Standalone)           │
│                                                          │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐  │
│  │   Web UI     │  │   API v1     │  │  Scraper     │  │
│  │  (Tailwind)  │  │   (JSON)     │  │  Service     │  │
│  └──────────────┘  └──────────────┘  └──────┬───────┘  │
│                                               │          │
│  ┌──────────────────────────────────────────┴────────┐  │
│  │        Models & Services                          │  │
│  │  User │ Shop │ Product │ ImportedProduct          │  │
│  └──────────────────────────────────────────────────┘  │
│                                                          │
│  ┌──────────────────────────────────────────────────┐  │
│  │    ActiveStorage + SQLite (Local File Storage)    │  │
│  └──────────────────────────────────────────────────┘  │
└───────────────────────────┬──────────────────────────────┘
                            │
                            │ Shell Execution
                            ▼
┌─────────────────────────────────────────────────────────┐
│           Playwright Scripts (scraper/ directory)        │
│                                                          │
│  investigate.js │ test-login.js │ scrape.js             │
│                                                          │
│  - Logs into Intercars                                  │
│  - Scrapes product data                                 │
│  - Outputs JSON files                                   │
└─────────────────────────────────────────────────────────┘
                            │
                            ▼
                   Intercars E-catalog Site
```

**No external services required** - everything runs locally!

### Data Flow

**CSV Import Flow (Simplified):**
```
Upload CSV → Parse & Preview → Map Columns → Process Synchronously
    → Create Products
    → Download Images (inline)
    → Update Status
```

**Scraper Import Flow (Playwright):**
```
Enter Credentials → ScraperService.test_login()
    → Execute test-login.js (Playwright)
    → Save Session Cookies

Initiate Scrape → ScraperService.scrape_products()
    → Execute scrape.js (Playwright)
    → Navigate & Extract Products
    → Save to JSON file

Import Data → ScraperService.import_from_json()
    → Parse JSON file
    → Create Products
    → Download Images
    → Update Status
```

---

## 3. Technology Stack

### Rails Application
| Component | Technology | Version | Notes |
|-----------|-----------|---------|-------|
| Framework | Ruby on Rails | 8.x | Latest stable |
| Language | Ruby | >= 3.2 | Required for Rails 8 |
| Database | SQLite | 3.38+ | JSON support, local storage |
| File Storage | ActiveStorage | Built-in | Local disk storage |
| Authentication | Devise | 4.9+ | With devise-passwordless |
| Authorization | Pundit | 2.3+ | Policy-based |
| CSS Framework | Tailwind CSS | 3.x | Via tailwindcss-rails |
| Testing | RSpec | 3.12+ | With FactoryBot, Faker |
| API | Rails API | Built-in | JSON API endpoints |

### Scraper (Playwright Scripts)
| Component | Technology | Version | Notes |
|-----------|-----------|---------|-------|
| Runtime | Node.js | 18 LTS | Playwright compatibility |
| Browser Automation | Playwright | 1.40+ | Chromium browser |
| Integration | Shell execution | - | Called from Rails via ScraperService |
| Output Format | JSON | - | Products data saved to files |

### Development Tools
- RuboCop (Ruby linting)
- ESLint (JavaScript linting, optional)
- GitHub Actions (CI/CD, optional)

**No Docker, Redis, or external services required!**

---

## 4. Data Model Deep Dive

### Core Tables

#### users
```ruby
# Authentication via Devise
- id: bigint (PK)
- email: string (indexed, unique)
- created_at: datetime
- updated_at: datetime
# Devise passwordless fields
- magic_link_token: string (indexed)
- magic_link_sent_at: datetime
```

#### shops
```ruby
# Multi-tenant shop entities
- id: bigint (PK)
- name: string
- settings: text (encrypted) # JSON with integrations credentials
- created_at: datetime
- updated_at: datetime

# Settings JSON structure:
{
  "intercars": {
    "username": "encrypted_value",
    "password": "encrypted_value",
    "last_scrape_at": "2024-01-15T10:30:00Z"
  }
}
```

#### memberships
```ruby
# User ↔ Shop many-to-many with roles
- id: bigint (PK)
- user_id: bigint (FK, indexed)
- shop_id: bigint (FK, indexed)
- role: string (enum: owner, admin, member)
- created_at: datetime
- updated_at: datetime

# Indexes: [user_id, shop_id] unique
```

#### products
```ruby
# Final normalized products
- id: bigint (PK)
- shop_id: bigint (FK, indexed)
- source: string (enum: csv, intercars)
- source_id: string (nullable, indexed)
- title: string
- sku: string (indexed)
- brand: string
- category: string
- price: decimal(10,2)
- currency: string (default: 'BAM')
- stock: integer (default: 0)
- description: text
- specs: text (JSON in SQLite, JSONB in Postgres)
- published: boolean (default: false)
- olx_ad_id: string (nullable, for future)
- created_at: datetime
- updated_at: datetime

# Indexes: [shop_id, source, source_id] unique (prevent duplicates)
```

#### imported_products
```ruby
# Staging table for raw imports
- id: bigint (PK)
- shop_id: bigint (FK, indexed)
- import_log_id: bigint (FK, nullable)
- source: string (enum: csv, intercars)
- raw_data: text (JSON)
- status: string (enum: pending, processing, imported, error)
- error_text: text (nullable)
- product_id: bigint (FK, nullable) # Link to created product
- created_at: datetime
- updated_at: datetime

# Indexes: [shop_id, status], [import_log_id]
```

#### import_logs
```ruby
# Track import jobs
- id: bigint (PK)
- shop_id: bigint (FK, indexed)
- source: string (enum: csv, intercars)
- status: string (enum: pending, processing, completed, failed)
- total_rows: integer (default: 0)
- processed_rows: integer (default: 0)
- successful_rows: integer (default: 0)
- failed_rows: integer (default: 0)
- metadata: text (JSON) # Original filename, mappings, etc.
- started_at: datetime (nullable)
- completed_at: datetime (nullable)
- created_at: datetime
- updated_at: datetime
```

### ActiveStorage Tables
Rails will generate:
- `active_storage_blobs` (file metadata)
- `active_storage_attachments` (polymorphic associations)
- `active_storage_variant_records` (image variants)

Products will have `has_many_attached :images`

---

## 5. API Design

### Base URL
`/api/v1`

### Authentication Endpoints

```
POST /api/v1/auth/magic_link
Body: { "email": "user@example.com" }
Response: { "message": "Magic link sent to your email" }
Status: 200 OK

GET /api/v1/auth/verify?token=ABC123
Response: Sets session cookie, redirects to dashboard
  OR returns JWT: { "token": "jwt_token", "user": {...} }
Status: 302 Found or 200 OK
```

### Shop Management

```
GET /api/v1/shops
Response: { "shops": [{ "id": 1, "name": "My Shop", "role": "owner" }] }
Status: 200 OK

POST /api/v1/shops
Body: { "name": "New Shop" }
Response: { "shop": { "id": 2, "name": "New Shop" } }
Status: 201 Created

GET /api/v1/shops/:id
Response: { "shop": { "id": 1, "name": "...", "stats": {...} } }
Status: 200 OK

PATCH /api/v1/shops/:id
Body: { "name": "Updated Name" }
Response: { "shop": {...} }
Status: 200 OK

POST /api/v1/shops/:shop_id/memberships
Body: { "email": "member@example.com", "role": "member" }
Response: { "membership": {...} }
Status: 201 Created
```

### CSV Import Endpoints

```
POST /api/v1/shops/:shop_id/imports/csv
Content-Type: multipart/form-data
Body: file=<csv_file>
Response: {
  "import_log_id": 123,
  "preview": [
    { "row": 1, "data": { "Title": "...", "Price": "..." } },
    ...first 10 rows
  ],
  "detected_mappings": {
    "Title": "title",
    "Price": "price",
    "confidence": 0.85
  }
}
Status: 201 Created

POST /api/v1/shops/:shop_id/imports/:id/map
Body: {
  "column_mappings": {
    "Title": "title",
    "Part Number": "sku",
    "Price (BAM)": "price",
    "Image URLs": "image_urls"
  }
}
Response: { "import_log": { "id": 123, "status": "mapped" } }
Status: 200 OK

POST /api/v1/shops/:shop_id/imports/:id/start
Response: {
  "import_log": { "id": 123, "status": "processing", "job_id": "abc123" }
}
Status: 202 Accepted

GET /api/v1/shops/:shop_id/imports/:id/status
Response: {
  "import_log": {
    "id": 123,
    "status": "processing",
    "total_rows": 100,
    "processed_rows": 45,
    "successful_rows": 42,
    "failed_rows": 3,
    "errors": [
      { "row": 10, "error": "Invalid price format" }
    ]
  }
}
Status: 200 OK
```

### Scraper Integration Endpoints

```
POST /api/v1/shops/:shop_id/imports/scrape
Body: {
  "username": "user@intercars.com",
  "password": "secret",
  "url": "https://ba.e-cat.intercars.eu/bs/",
  "save_credentials": true
}
Response: {
  "import_log_id": 124,
  "scraper_job_id": "scrape_xyz",
  "status": "initiated"
}
Status: 202 Accepted

GET /api/v1/shops/:shop_id/imports/:id/result
Response: {
  "import_log": {
    "id": 124,
    "status": "completed",
    "total_rows": 250,
    "scraped_products": [
      {
        "source_id": "IC12345",
        "title": "Brake Pad Set",
        "sku": "BP-001",
        "price": 85.00,
        "currency": "BAM",
        ...
      },
      ...
    ]
  }
}
Status: 200 OK
```

### Product Management

```
GET /api/v1/shops/:shop_id/products
Query: ?page=1&per_page=20&source=csv&published=false
Response: {
  "products": [...],
  "meta": { "total": 100, "page": 1, "per_page": 20 }
}
Status: 200 OK

GET /api/v1/shops/:shop_id/products/:id
Response: { "product": {...} }
Status: 200 OK

PATCH /api/v1/shops/:shop_id/products/:id
Body: { "published": true, "price": 99.99 }
Response: { "product": {...} }
Status: 200 OK

DELETE /api/v1/shops/:shop_id/products/:id
Response: { "message": "Product deleted" }
Status: 204 No Content

POST /api/v1/shops/:shop_id/products/:id/publish_to_olx
Body: { "category_id": "auto-parts", "location": "Sarajevo" }
Response: { "olx_ad_id": "OLX123", "url": "https://olx.ba/..." }
Status: 201 Created
# Placeholder for future OLX API integration
```

### Import Logs

```
GET /api/v1/shops/:shop_id/imports
Query: ?status=completed&source=csv
Response: { "imports": [...] }
Status: 200 OK
```

---

## 6. Scraper Microservice Architecture

### Node.js Service Structure

```
scraper/
├── src/
│   ├── server.js              # Express app entry
│   ├── routes/
│   │   ├── auth.js            # Login endpoints
│   │   ├── scrape.js          # Scraping endpoints
│   │   └── jobs.js            # Job status endpoints
│   ├── services/
│   │   ├── browser.service.js # Playwright browser pool
│   │   ├── intercars.service.js # Intercars-specific scraping
│   │   └── job.service.js     # Job queue and status
│   ├── utils/
│   │   ├── logger.js
│   │   ├── throttle.js
│   │   └── selectors.js       # CSS selectors config
│   └── config/
│       └── intercars.config.js
├── tests/
│   ├── intercars.test.js
│   └── mocks/
├── Dockerfile
├── package.json
└── README.md
```

### API Endpoints

```
POST /login
Body: { "site": "intercars", "username": "...", "password": "..." }
Response: {
  "session_token": "SESSION_ABC123",
  "expires_at": "2024-01-15T11:30:00Z"
}
Status: 200 OK
Errors:
  - 401: Invalid credentials
  - 403: CAPTCHA detected (needs_interaction)
  - 500: Browser error

POST /scrape
Body: {
  "session_token": "SESSION_ABC123",
  "site": "intercars",
  "start_url": "https://ba.e-cat.intercars.eu/bs/products",
  "max_products": 100
}
Response: { "job_id": "JOB_XYZ789" }
Status: 202 Accepted

GET /jobs/:job_id
Response: {
  "job_id": "JOB_XYZ789",
  "status": "processing", # pending|processing|completed|failed
  "progress": { "current": 45, "total": 100 },
  "products": [
    {
      "source": "intercars",
      "source_id": "IC12345",
      "title": "Brake Pad Set Front Axle",
      "sku": "BP-F-001",
      "brand": "Bosch",
      "category": "Brake System",
      "price": 85.50,
      "currency": "BAM",
      "stock": 15,
      "description": "High-quality brake pads...",
      "images": [
        "https://ba.e-cat.intercars.eu/images/product_123_main.jpg",
        "https://ba.e-cat.intercars.eu/images/product_123_alt1.jpg"
      ],
      "specs": {
        "part_number": "0986494123",
        "weight": "1.2kg",
        "compatibility": "VW Golf VII, Audi A3 (8V)",
        "fitting_position": "Front Axle"
      }
    },
    ...
  ],
  "error": null
}
Status: 200 OK

DELETE /jobs/:job_id
Response: { "message": "Job cancelled" }
Status: 200 OK
```

### Scraping Strategy

**Intercars Site Structure:**
1. Login page: `https://ba.e-cat.intercars.eu/bs/login`
2. Catalog: `https://ba.e-cat.intercars.eu/bs/` (category navigation)
3. Product list pages (paginated)
4. Product detail pages

**Scraping Flow:**
```javascript
1. Login with credentials
   - Navigate to login page
   - Fill username/password
   - Submit form
   - Wait for dashboard/catalog
   - Detect CAPTCHA/2FA → abort if present
   - Store session cookies

2. Navigate catalog
   - Start from main category page
   - Identify product links
   - Extract basic info from list (title, price, thumbnail)

3. For each product:
   - Navigate to detail page
   - Extract full data:
     - Title (h1.product-title)
     - SKU/Part number (.product-sku)
     - Brand (.product-brand)
     - Price (.product-price)
     - Stock status (.product-stock)
     - Description (.product-description)
     - Images (img.product-image[src])
     - Specs table (.specs-table tr)
   - Wait 1-2 seconds (respectful throttle)
   - Handle errors with exponential backoff

4. Return structured JSON
   - Match Product schema
   - Include source_id for deduplication
```

**Selector Configuration (updatable):**
```javascript
// src/config/intercars.config.js
module.exports = {
  selectors: {
    login: {
      usernameInput: '#username',
      passwordInput: '#password',
      submitButton: 'button[type="submit"]',
      errorMessage: '.login-error',
      captcha: '.g-recaptcha, .h-captcha'
    },
    productList: {
      productLinks: '.product-card a.product-link',
      nextPage: '.pagination .next'
    },
    productDetail: {
      title: 'h1.product-title, .product-name',
      sku: '.product-sku, .part-number',
      brand: '.product-brand, .manufacturer',
      price: '.product-price .amount',
      currency: '.product-price .currency',
      stock: '.product-stock, .availability',
      description: '.product-description, .details',
      images: '.product-gallery img, .product-images img',
      specsTable: '.specifications table, .specs-table'
    }
  },
  throttle: {
    minDelay: 1000, // 1 second between requests
    maxDelay: 5000,
    backoffMultiplier: 2
  }
};
```

**Error Handling:**
- CAPTCHA detection → `{ error: "needs_interaction", type: "captcha" }`
- 2FA detection → `{ error: "needs_interaction", type: "2fa" }`
- Network errors → Retry 3x with exponential backoff
- Timeout → Configurable (default 30s per page)
- Invalid credentials → `{ error: "invalid_credentials" }`

---

## 7. Security Considerations

### 1. Credentials Encryption (Rails 8)

```ruby
# app/models/shop.rb
class Shop < ApplicationRecord
  encrypts :settings

  # Store as JSON with encrypted attributes
  def integration_credentials(site)
    parsed_settings.dig(site.to_s, 'credentials')
  end

  def set_integration_credentials(site, username, password)
    current = parsed_settings
    current[site.to_s] ||= {}
    current[site.to_s]['credentials'] = {
      'username' => username,
      'password' => password,
      'updated_at' => Time.current.iso8601
    }
    self.settings = current.to_json
  end

  private

  def parsed_settings
    settings.present? ? JSON.parse(settings) : {}
  end
end

# config/application.rb
# Rails 8 generates master key automatically
config.active_record.encryption.primary_key = Rails.application.credentials.active_record_encryption_primary_key
config.active_record.encryption.deterministic_key = Rails.application.credentials.active_record_encryption_deterministic_key
config.active_record.encryption.key_derivation_salt = Rails.application.credentials.active_record_encryption_key_derivation_salt
```

### 2. API Authentication

```ruby
# app/controllers/api/v1/base_controller.rb
class Api::V1::BaseController < ActionController::API
  include ActionController::Cookies

  before_action :authenticate_user!
  before_action :set_current_shop

  private

  def authenticate_user!
    # Session-based (from magic link) or JWT
    unless current_user
      render json: { error: 'Unauthorized' }, status: :unauthorized
    end
  end

  def set_current_shop
    if params[:shop_id]
      @current_shop = current_user.shops.find(params[:shop_id])
    end
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Shop not found' }, status: :not_found
  end
end
```

### 3. Authorization (Pundit)

```ruby
# app/policies/shop_policy.rb
class ShopPolicy < ApplicationPolicy
  def update?
    user_membership&.owner? || user_membership&.admin?
  end

  def manage_integrations?
    user_membership&.owner?
  end

  private

  def user_membership
    @user_membership ||= record.memberships.find_by(user: user)
  end
end
```

### 4. Rate Limiting

```ruby
# config/initializers/rack_attack.rb
class Rack::Attack
  throttle('api/ip', limit: 300, period: 5.minutes) do |req|
    req.ip if req.path.start_with?('/api/')
  end

  throttle('scraper/shop', limit: 5, period: 1.hour) do |req|
    if req.path.include?('/imports/scrape') && req.post?
      shop_id = req.params['shop_id']
      "scrape-#{shop_id}"
    end
  end
end
```

### 5. Scraper Security

```javascript
// scraper/src/middleware/auth.js
const validateApiKey = (req, res, next) => {
  const apiKey = req.headers['x-api-key'];
  if (apiKey !== process.env.SCRAPER_API_KEY) {
    return res.status(401).json({ error: 'Invalid API key' });
  }
  next();
};

// Secure session storage
const sessions = new Map(); // Use Redis in production
const SESSION_TTL = 30 * 60 * 1000; // 30 minutes

function storeSession(token, cookies) {
  sessions.set(token, {
    cookies,
    expiresAt: Date.now() + SESSION_TTL
  });
}
```

### 6. Environment Variables

```bash
# .env.example (Rails)
RAILS_ENV=development
DATABASE_URL=sqlite3:db/development.sqlite3
REDIS_URL=redis://localhost:6379/0
MINIO_ENDPOINT=http://localhost:9000
MINIO_ACCESS_KEY=minioadmin
MINIO_SECRET_KEY=minioadmin
SCRAPER_API_URL=http://scraper:3001
SCRAPER_API_KEY=generate_secure_random_key

# .env.example (Scraper)
NODE_ENV=development
PORT=3001
SCRAPER_API_KEY=same_as_rails_key
PLAYWRIGHT_HEADLESS=true
MAX_CONCURRENT_JOBS=3
```

---

## 8. Step-by-Step Implementation Plan

### STEP 1: Repo Skeleton & Docker Infrastructure

**Goal:** Create project structure, Docker Compose setup, CI config

**Tasks:**
1. Initialize Rails 8 app with API mode + Tailwind
2. Create Docker Compose with services:
   - `web` (Rails)
   - `redis` (Sidekiq queue)
   - `sidekiq` (background worker)
   - `minio` (S3-compatible storage)
   - `scraper` (Node.js + Playwright)
3. Add development scripts (`bin/setup`, `bin/dev`)
4. Configure GitHub Actions CI
5. Create comprehensive README

**Deliverables:**
```
olx_integration/
├── .github/
│   └── workflows/
│       └── ci.yml
├── app/
│   ├── controllers/
│   ├── models/
│   ├── jobs/
│   ├── services/
│   ├── policies/
│   └── views/
├── scraper/
│   ├── src/
│   ├── tests/
│   ├── Dockerfile
│   └── package.json
├── config/
│   ├── database.yml (SQLite)
│   └── sidekiq.yml
├── docker-compose.yml
├── Dockerfile (Rails)
├── Gemfile
├── Makefile
├── README.md
└── .env.example
```

**Tests:**
- Rails boots successfully
- Sidekiq connects to Redis
- MinIO accessible
- Scraper service responds to health check

---

### STEP 2: Authentication & Core Models

**Goal:** Implement magic link auth, multi-tenant shop system

**Tasks:**
1. Install and configure Devise with passwordless authentication
2. Create User model with Devise
3. Implement magic link email flow
4. Create Shop, Membership models
5. Set up Pundit for authorization
6. Build basic UI:
   - Magic link login form
   - Shop dashboard (list shops, create shop)
   - Shop selector
7. Add RSpec model and request tests

**Migrations:**
```ruby
# db/migrate/20240115_devise_create_users.rb
create_table :users do |t|
  t.string :email, null: false
  t.string :magic_link_token
  t.datetime :magic_link_sent_at
  t.timestamps
end
add_index :users, :email, unique: true
add_index :users, :magic_link_token

# db/migrate/20240115_create_shops.rb
create_table :shops do |t|
  t.string :name, null: false
  t.text :settings # Encrypted JSON
  t.timestamps
end

# db/migrate/20240115_create_memberships.rb
create_table :memberships do |t|
  t.references :user, null: false, foreign_key: true
  t.references :shop, null: false, foreign_key: true
  t.string :role, null: false, default: 'member'
  t.timestamps
end
add_index :memberships, [:user_id, :shop_id], unique: true
```

**Models:**
```ruby
# app/models/user.rb
class User < ApplicationRecord
  devise :magic_link_authenticatable, :trackable

  has_many :memberships, dependent: :destroy
  has_many :shops, through: :memberships

  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
end

# app/models/shop.rb
class Shop < ApplicationRecord
  encrypts :settings

  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :products, dependent: :destroy
  has_many :imported_products, dependent: :destroy
  has_many :import_logs, dependent: :destroy

  validates :name, presence: true

  def owner
    memberships.find_by(role: 'owner')&.user
  end
end

# app/models/membership.rb
class Membership < ApplicationRecord
  belongs_to :user
  belongs to :shop

  enum role: { owner: 'owner', admin: 'admin', member: 'member' }

  validates :role, presence: true
  validates :user_id, uniqueness: { scope: :shop_id }
end
```

**Controllers:**
```ruby
# app/controllers/api/v1/auth_controller.rb
class Api::V1::AuthController < ActionController::API
  def create_magic_link
    user = User.find_or_create_by(email: params[:email])
    user.send_magic_link
    render json: { message: 'Magic link sent' }, status: :ok
  end

  def verify
    user = User.find_by(magic_link_token: params[:token])
    if user && user.valid_magic_link?
      sign_in(user)
      redirect_to dashboard_path
    else
      render json: { error: 'Invalid or expired token' }, status: :unauthorized
    end
  end
end

# app/controllers/api/v1/shops_controller.rb
class Api::V1::ShopsController < Api::V1::BaseController
  def index
    render json: { shops: current_user.shops }
  end

  def create
    shop = Shop.new(shop_params)
    if shop.save
      shop.memberships.create!(user: current_user, role: 'owner')
      render json: { shop: shop }, status: :created
    else
      render json: { errors: shop.errors }, status: :unprocessable_entity
    end
  end

  private

  def shop_params
    params.require(:shop).permit(:name)
  end
end
```

**Tests:**
```ruby
# spec/requests/api/v1/auth_spec.rb
RSpec.describe 'Auth API', type: :request do
  describe 'POST /api/v1/auth/magic_link' do
    it 'sends magic link email' do
      post '/api/v1/auth/magic_link', params: { email: 'test@example.com' }
      expect(response).to have_http_status(:ok)
      expect(ActionMailer::Base.deliveries.count).to eq(1)
    end
  end
end

# spec/models/shop_spec.rb
RSpec.describe Shop, type: :model do
  it { should have_many(:memberships) }
  it { should have_many(:users).through(:memberships) }
  it { should validate_presence_of(:name) }

  it 'encrypts settings' do
    shop = create(:shop, settings: '{"key": "value"}')
    expect(shop.settings_before_type_cast).not_to eq('{"key": "value"}')
  end
end
```

**Deliverables:**
- Working authentication system
- Shop CRUD operations
- Authorization policies
- UI for login and shop management
- Comprehensive tests

---

### STEP 3: CSV Import API & Background Jobs

**Goal:** Complete CSV import flow from upload to products

**Tasks:**
1. Create Product, ImportedProduct, ImportLog models
2. Implement CSV upload endpoint with preview
3. Build auto-mapping service (heuristic column detection)
4. Create background jobs for processing
5. Implement image download from URLs
6. Build import status UI
7. Add comprehensive tests

**Migrations:**
```ruby
# db/migrate/20240116_create_products.rb
create_table :products do |t|
  t.references :shop, null: false, foreign_key: true
  t.string :source, null: false # csv, intercars
  t.string :source_id
  t.string :title, null: false
  t.string :sku
  t.string :brand
  t.string :category
  t.decimal :price, precision: 10, scale: 2
  t.string :currency, default: 'BAM'
  t.integer :stock, default: 0
  t.text :description
  t.text :specs # JSON
  t.boolean :published, default: false
  t.string :olx_ad_id
  t.timestamps
end
add_index :products, [:shop_id, :source, :source_id], unique: true, where: "source_id IS NOT NULL"
add_index :products, [:shop_id, :sku]

# db/migrate/20240116_create_imported_products.rb
create_table :imported_products do |t|
  t.references :shop, null: false, foreign_key: true
  t.references :import_log, foreign_key: true
  t.string :source, null: false
  t.text :raw_data # JSON
  t.string :status, default: 'pending'
  t.text :error_text
  t.references :product, foreign_key: true
  t.timestamps
end
add_index :imported_products, [:shop_id, :status]

# db/migrate/20240116_create_import_logs.rb
create_table :import_logs do |t|
  t.references :shop, null: false, foreign_key: true
  t.string :source, null: false
  t.string :status, default: 'pending'
  t.integer :total_rows, default: 0
  t.integer :processed_rows, default: 0
  t.integer :successful_rows, default: 0
  t.integer :failed_rows, default: 0
  t.text :metadata # JSON
  t.datetime :started_at
  t.datetime :completed_at
  t.timestamps
end
add_index :import_logs, [:shop_id, :status]
```

**Services:**
```ruby
# app/services/csv_import/parser.rb
module CsvImport
  class Parser
    def initialize(file_path, shop)
      @file_path = file_path
      @shop = shop
    end

    def preview(limit = 10)
      rows = []
      CSV.foreach(@file_path, headers: true, encoding: 'UTF-8').with_index do |row, idx|
        break if idx >= limit
        rows << { row: idx + 1, data: row.to_h }
      end
      rows
    end

    def detect_mappings(headers)
      mappings = {}
      confidence = 0.0

      headers.each do |header|
        normalized = header.downcase.strip

        if normalized.match?(/(title|name|product)/)
          mappings[header] = 'title'
          confidence += 0.15
        elsif normalized.match?/(desc|description)/
          mappings[header] = 'description'
          confidence += 0.10
        elsif normalized.match?/(price|cost|amount)/
          mappings[header] = 'price'
          confidence += 0.15
        elsif normalized.match?/(sku|part|pn|code)/
          mappings[header] = 'sku'
          confidence += 0.15
        elsif normalized.match?/(brand|manufacturer|make)/
          mappings[header] = 'brand'
          confidence += 0.10
        elsif normalized.match?/(stock|quantity|qty)/
          mappings[header] = 'stock'
          confidence += 0.10
        elsif normalized.match?/(image|img|photo|picture)/
          mappings[header] = 'image_urls'
          confidence += 0.10
        elsif normalized.match?/(category|cat)/
          mappings[header] = 'category'
          confidence += 0.10
        end
      end

      { mappings: mappings, confidence: confidence.round(2) }
    end
  end
end

# app/services/csv_import/processor.rb
module CsvImport
  class Processor
    def initialize(import_log, column_mappings)
      @import_log = import_log
      @shop = import_log.shop
      @column_mappings = column_mappings
    end

    def process_file(file_path)
      @import_log.update!(status: 'processing', started_at: Time.current)

      CSV.foreach(file_path, headers: true, encoding: 'UTF-8') do |row|
        raw_data = map_row(row)
        ImportedProduct.create!(
          shop: @shop,
          import_log: @import_log,
          source: 'csv',
          raw_data: raw_data.to_json,
          status: 'pending'
        )
      end

      @import_log.update!(total_rows: @import_log.imported_products.count)
      enqueue_row_processing
    end

    private

    def map_row(csv_row)
      mapped = {}
      @column_mappings.each do |csv_column, product_field|
        mapped[product_field] = csv_row[csv_column]
      end
      mapped
    end

    def enqueue_row_processing
      @import_log.imported_products.pending.find_each do |imported_product|
        ImportedProduct::ProcessRowJob.perform_later(imported_product.id)
      end
    end
  end
end

# app/services/imported_product/normalizer.rb
class ImportedProduct::Normalizer
  def initialize(imported_product)
    @imported_product = imported_product
    @shop = imported_product.shop
    @raw_data = JSON.parse(imported_product.raw_data)
  end

  def process
    @imported_product.update!(status: 'processing')

    product_attrs = normalize_attributes
    download_images(product_attrs)

    product = create_or_update_product(product_attrs)

    @imported_product.update!(
      status: 'imported',
      product: product
    )

    increment_success_count
    product
  rescue => e
    @imported_product.update!(
      status: 'error',
      error_text: e.message
    )
    increment_failed_count
    raise
  end

  private

  def normalize_attributes
    {
      shop: @shop,
      source: @imported_product.source,
      title: @raw_data['title'],
      sku: @raw_data['sku'],
      brand: @raw_data['brand'],
      category: @raw_data['category'],
      price: parse_price(@raw_data['price']),
      currency: @raw_data['currency'] || 'BAM',
      stock: @raw_data['stock']&.to_i || 0,
      description: @raw_data['description'],
      specs: extract_specs.to_json
    }
  end

  def parse_price(price_string)
    return nil if price_string.blank?
    price_string.to_s.gsub(/[^\d.]/, '').to_f
  end

  def extract_specs
    @raw_data.except('title', 'sku', 'brand', 'category', 'price', 'currency', 'stock', 'description', 'image_urls')
  end

  def download_images(product_attrs)
    # Implementation in next part
  end

  def create_or_update_product(attrs)
    product = @shop.products.find_or_initialize_by(
      source: attrs[:source],
      sku: attrs[:sku]
    )
    product.update!(attrs)
    product
  end

  def increment_success_count
    @imported_product.import_log&.increment!(:successful_rows)
    @imported_product.import_log&.increment!(:processed_rows)
  end

  def increment_failed_count
    @imported_product.import_log&.increment!(:failed_rows)
    @imported_product.import_log&.increment!(:processed_rows)
  end
end
```

**Jobs:**
```ruby
# app/jobs/csv_import/process_file_job.rb
module CsvImport
  class ProcessFileJob < ApplicationJob
    queue_as :default

    def perform(import_log_id, file_path, column_mappings)
      import_log = ImportLog.find(import_log_id)
      processor = Processor.new(import_log, column_mappings)
      processor.process_file(file_path)
    end
  end
end

# app/jobs/imported_product/process_row_job.rb
class ImportedProduct::ProcessRowJob < ApplicationJob
  queue_as :default
  retry_on StandardError, wait: :exponentially_longer, attempts: 3

  def perform(imported_product_id)
    imported_product = ImportedProduct.find(imported_product_id)
    normalizer = ImportedProduct::Normalizer.new(imported_product)
    normalizer.process
  end
end
```

**Controllers:**
```ruby
# app/controllers/api/v1/imports_controller.rb
class Api::V1::ImportsController < Api::V1::BaseController
  before_action :set_shop

  def create_csv
    file = params[:file]

    # Save file temporarily
    file_path = Rails.root.join('tmp', "import_#{SecureRandom.hex(8)}.csv")
    File.open(file_path, 'wb') { |f| f.write(file.read) }

    # Create import log
    import_log = @shop.import_logs.create!(
      source: 'csv',
      status: 'pending',
      metadata: { filename: file.original_filename }.to_json
    )

    # Parse and preview
    parser = CsvImport::Parser.new(file_path, @shop)
    preview = parser.preview
    headers = CSV.open(file_path, &:readline)
    detected = parser.detect_mappings(headers)

    # Store file path in metadata
    import_log.update!(metadata: {
      filename: file.original_filename,
      file_path: file_path.to_s,
      headers: headers
    }.to_json)

    render json: {
      import_log_id: import_log.id,
      preview: preview,
      detected_mappings: detected
    }, status: :created
  end

  def update_mapping
    import_log = @shop.import_logs.find(params[:id])
    metadata = JSON.parse(import_log.metadata)
    metadata['column_mappings'] = params[:column_mappings]
    import_log.update!(metadata: metadata.to_json)

    render json: { import_log: import_log }
  end

  def start_import
    import_log = @shop.import_logs.find(params[:id])
    metadata = JSON.parse(import_log.metadata)

    CsvImport::ProcessFileJob.perform_later(
      import_log.id,
      metadata['file_path'],
      metadata['column_mappings']
    )

    render json: { import_log: import_log }, status: :accepted
  end

  def status
    import_log = @shop.import_logs.find(params[:id])
    errors = import_log.imported_products.where(status: 'error')
                       .limit(10)
                       .pluck(:id, :error_text)

    render json: {
      import_log: import_log.as_json,
      errors: errors.map { |id, text| { id: id, error: text } }
    }
  end

  private

  def set_shop
    @shop = current_user.shops.find(params[:shop_id])
  end
end
```

**Tests:**
```ruby
# spec/services/csv_import/parser_spec.rb
RSpec.describe CsvImport::Parser do
  let(:shop) { create(:shop) }
  let(:csv_path) { Rails.root.join('spec/fixtures/sample_products.csv') }
  let(:parser) { described_class.new(csv_path, shop) }

  describe '#preview' do
    it 'returns first 10 rows' do
      preview = parser.preview
      expect(preview.length).to be <= 10
      expect(preview.first[:data]).to have_key('Title')
    end
  end

  describe '#detect_mappings' do
    it 'maps common column names' do
      headers = ['Title', 'Part Number', 'Price (BAM)', 'Brand']
      result = parser.detect_mappings(headers)

      expect(result[:mappings]['Title']).to eq('title')
      expect(result[:mappings]['Part Number']).to eq('sku')
      expect(result[:mappings]['Price (BAM)']).to eq('price')
      expect(result[:confidence]).to be > 0.4
    end
  end
end

# spec/fixtures/sample_products.csv
Title,Part Number,Brand,Price (BAM),Stock,Image URLs,Description
Brake Pad Set Front,BP-F-001,Bosch,85.50,15,https://example.com/img1.jpg,High-quality brake pads
Oil Filter,OF-001,Mann,12.30,50,https://example.com/img2.jpg,Compatible with VW Golf
```

**Deliverables:**
- Full CSV import flow (upload → preview → map → process)
- Background job processing
- Import progress tracking
- Error handling and reporting
- Sample CSV fixture
- Comprehensive tests

---

### STEP 4: Scraper Microservice Skeleton

**Goal:** Build Node.js Playwright scraper with Intercars support

**Tasks:**
1. Initialize Node.js project with Express
2. Set up Playwright with Chromium
3. Implement `/login`, `/scrape`, `/jobs/:id` endpoints
4. Build Intercars-specific scraping logic
5. Add job queue (in-memory for MVP, Redis for production)
6. Create Dockerfile with Playwright dependencies
7. Add tests with mocked browser

**Project Structure:**
```
scraper/
├── src/
│   ├── server.js
│   ├── routes/
│   │   ├── auth.routes.js
│   │   ├── scrape.routes.js
│   │   └── jobs.routes.js
│   ├── services/
│   │   ├── browser.service.js
│   │   ├── intercars.service.js
│   │   ├── job.service.js
│   │   └── session.service.js
│   ├── utils/
│   │   ├── logger.js
│   │   ├── throttle.js
│   │   └── errors.js
│   ├── config/
│   │   ├── intercars.config.js
│   │   └── index.js
│   └── middleware/
│       ├── auth.middleware.js
│       └── errorHandler.js
├── tests/
│   ├── integration/
│   │   └── intercars.test.js
│   └── unit/
│       └── throttle.test.js
├── Dockerfile
├── package.json
├── .env.example
└── README.md
```

**package.json:**
```json
{
  "name": "olx-scraper",
  "version": "1.0.0",
  "main": "src/server.js",
  "scripts": {
    "start": "node src/server.js",
    "dev": "nodemon src/server.js",
    "test": "jest --coverage"
  },
  "dependencies": {
    "express": "^4.18.2",
    "playwright": "^1.40.0",
    "dotenv": "^16.3.1",
    "uuid": "^9.0.1",
    "winston": "^3.11.0"
  },
  "devDependencies": {
    "jest": "^29.7.0",
    "nodemon": "^3.0.2",
    "eslint": "^8.56.0"
  }
}
```

**Key Files:**
```javascript
// src/server.js
const express = require('express');
const authRoutes = require('./routes/auth.routes');
const scrapeRoutes = require('./routes/scrape.routes');
const jobRoutes = require('./routes/jobs.routes');
const { errorHandler } = require('./middleware/errorHandler');
const { validateApiKey } = require('./middleware/auth.middleware');
const logger = require('./utils/logger');

const app = express();
app.use(express.json());

// Health check
app.get('/health', (req, res) => {
  res.json({ status: 'ok', service: 'scraper' });
});

// Routes (protected by API key)
app.use(validateApiKey);
app.use('/login', authRoutes);
app.use('/scrape', scrapeRoutes);
app.use('/jobs', jobRoutes);

app.use(errorHandler);

const PORT = process.env.PORT || 3001;
app.listen(PORT, () => {
  logger.info(`Scraper service running on port ${PORT}`);
});

// src/services/intercars.service.js
const { chromium } = require('playwright');
const config = require('../config/intercars.config');
const logger = require('../utils/logger');
const { throttle } = require('../utils/throttle');

class IntercarsService {
  constructor() {
    this.browser = null;
  }

  async login(username, password) {
    const browser = await chromium.launch({ headless: true });
    const context = await browser.newContext({
      userAgent: 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36'
    });
    const page = await context.newPage();

    try {
      await page.goto(config.urls.login, { waitUntil: 'networkidle' });

      // Check for CAPTCHA
      if (await page.locator(config.selectors.login.captcha).count() > 0) {
        await browser.close();
        return { error: 'needs_interaction', type: 'captcha' };
      }

      // Fill login form
      await page.fill(config.selectors.login.usernameInput, username);
      await page.fill(config.selectors.login.passwordInput, password);
      await page.click(config.selectors.login.submitButton);

      // Wait for navigation
      await page.waitForNavigation({ waitUntil: 'networkidle', timeout: 10000 });

      // Check for errors
      if (await page.locator(config.selectors.login.errorMessage).count() > 0) {
        await browser.close();
        return { error: 'invalid_credentials' };
      }

      // Extract cookies
      const cookies = await context.cookies();
      await browser.close();

      return { success: true, cookies };
    } catch (error) {
      await browser.close();
      logger.error('Login error:', error);
      return { error: 'login_failed', message: error.message };
    }
  }

  async scrapeProducts(cookies, options = {}) {
    const maxProducts = options.maxProducts || 100;
    const startUrl = options.startUrl || config.urls.catalog;

    const browser = await chromium.launch({ headless: true });
    const context = await browser.newContext();
    await context.addCookies(cookies);

    const page = await context.newPage();
    const products = [];

    try {
      await page.goto(startUrl, { waitUntil: 'networkidle' });

      // Get product links from listing
      const productLinks = await page.locator(config.selectors.productList.productLinks)
                                      .all();
      const urls = await Promise.all(
        productLinks.slice(0, maxProducts).map(link => link.getAttribute('href'))
      );

      // Scrape each product
      for (const url of urls) {
        await throttle(config.throttle.minDelay);

        const product = await this.scrapeProductDetail(page, url);
        if (product) {
          products.push(product);
        }

        if (products.length >= maxProducts) break;
      }

      await browser.close();
      return products;
    } catch (error) {
      await browser.close();
      logger.error('Scraping error:', error);
      throw error;
    }
  }

  async scrapeProductDetail(page, url) {
    try {
      await page.goto(url, { waitUntil: 'networkidle', timeout: 30000 });

      const sel = config.selectors.productDetail;

      const product = {
        source: 'intercars',
        source_id: this.extractIdFromUrl(url),
        title: await page.locator(sel.title).first().textContent(),
        sku: await page.locator(sel.sku).first().textContent(),
        brand: await page.locator(sel.brand).first().textContent(),
        price: await this.extractPrice(page, sel.price),
        currency: 'BAM',
        stock: await this.extractStock(page, sel.stock),
        description: await page.locator(sel.description).first().textContent(),
        images: await this.extractImages(page, sel.images),
        specs: await this.extractSpecs(page, sel.specsTable)
      };

      return product;
    } catch (error) {
      logger.warn(`Failed to scrape ${url}:`, error.message);
      return null;
    }
  }

  async extractPrice(page, selector) {
    const text = await page.locator(selector).first().textContent();
    return parseFloat(text.replace(/[^\d.]/g, ''));
  }

  async extractStock(page, selector) {
    const text = await page.locator(selector).first().textContent();
    const match = text.match(/\d+/);
    return match ? parseInt(match[0]) : 0;
  }

  async extractImages(page, selector) {
    const imgs = await page.locator(selector).all();
    return Promise.all(imgs.map(img => img.getAttribute('src')));
  }

  async extractSpecs(page, selector) {
    const specs = {};
    const rows = await page.locator(`${selector} tr`).all();

    for (const row of rows) {
      const cells = await row.locator('td').all();
      if (cells.length >= 2) {
        const key = await cells[0].textContent();
        const value = await cells[1].textContent();
        specs[key.trim()] = value.trim();
      }
    }

    return specs;
  }

  extractIdFromUrl(url) {
    const match = url.match(/\/product\/(\d+)/);
    return match ? match[1] : url;
  }
}

module.exports = new IntercarsService();

// src/services/job.service.js
const { v4: uuidv4 } = require('uuid');

class JobService {
  constructor() {
    this.jobs = new Map(); // Use Redis in production
  }

  createJob(type, data) {
    const jobId = uuidv4();
    this.jobs.set(jobId, {
      id: jobId,
      type,
      status: 'pending',
      progress: { current: 0, total: 0 },
      products: [],
      error: null,
      createdAt: new Date(),
      updatedAt: new Date()
    });
    return jobId;
  }

  updateJob(jobId, updates) {
    const job = this.jobs.get(jobId);
    if (job) {
      Object.assign(job, updates, { updatedAt: new Date() });
      this.jobs.set(jobId, job);
    }
  }

  getJob(jobId) {
    return this.jobs.get(jobId);
  }

  deleteJob(jobId) {
    this.jobs.delete(jobId);
  }
}

module.exports = new JobService();

// src/config/intercars.config.js
module.exports = {
  urls: {
    login: 'https://ba.e-cat.intercars.eu/bs/login',
    catalog: 'https://ba.e-cat.intercars.eu/bs/'
  },
  selectors: {
    login: {
      usernameInput: '#username, input[name="username"]',
      passwordInput: '#password, input[name="password"]',
      submitButton: 'button[type="submit"]',
      errorMessage: '.error, .alert-danger',
      captcha: '.g-recaptcha, .h-captcha, #captcha'
    },
    productList: {
      productLinks: '.product-card a, .product-item a',
      nextPage: '.pagination .next, a[rel="next"]'
    },
    productDetail: {
      title: 'h1, .product-title, .product-name',
      sku: '.sku, .part-number, [data-sku]',
      brand: '.brand, .manufacturer',
      price: '.price, .product-price .amount',
      stock: '.stock, .availability',
      description: '.description, .product-description',
      images: '.product-images img, .gallery img',
      specsTable: '.specs table, .specifications table'
    }
  },
  throttle: {
    minDelay: 1000,
    maxDelay: 5000,
    backoffMultiplier: 2
  }
};
```

**Routes:**
```javascript
// src/routes/auth.routes.js
const express = require('express');
const intercarsService = require('../services/intercars.service');
const sessionService = require('../services/session.service');
const logger = require('../utils/logger');

const router = express.Router();

router.post('/', async (req, res, next) => {
  try {
    const { site, username, password } = req.body;

    if (site !== 'intercars') {
      return res.status(400).json({ error: 'Unsupported site' });
    }

    const result = await intercarsService.login(username, password);

    if (result.error) {
      return res.status(result.error === 'invalid_credentials' ? 401 : 403)
                .json(result);
    }

    const sessionToken = sessionService.createSession(result.cookies);

    res.json({
      session_token: sessionToken,
      expires_at: new Date(Date.now() + 30 * 60 * 1000).toISOString()
    });
  } catch (error) {
    next(error);
  }
});

module.exports = router;

// src/routes/scrape.routes.js
const express = require('express');
const intercarsService = require('../services/intercars.service');
const sessionService = require('../services/session.service');
const jobService = require('../services/job.service');
const logger = require('../utils/logger');

const router = express.Router();

router.post('/', async (req, res, next) => {
  try {
    const { session_token, site, start_url, max_products } = req.body;

    const session = sessionService.getSession(session_token);
    if (!session) {
      return res.status(401).json({ error: 'Invalid or expired session' });
    }

    const jobId = jobService.createJob('scrape', { site, start_url });

    // Run async
    (async () => {
      try {
        jobService.updateJob(jobId, { status: 'processing' });

        const products = await intercarsService.scrapeProducts(session.cookies, {
          startUrl: start_url,
          maxProducts: max_products || 100
        });

        jobService.updateJob(jobId, {
          status: 'completed',
          products,
          progress: { current: products.length, total: products.length }
        });
      } catch (error) {
        logger.error(`Job ${jobId} failed:`, error);
        jobService.updateJob(jobId, {
          status: 'failed',
          error: error.message
        });
      }
    })();

    res.status(202).json({ job_id: jobId });
  } catch (error) {
    next(error);
  }
});

module.exports = router;

// src/routes/jobs.routes.js
const express = require('express');
const jobService = require('../services/job.service');

const router = express.Router();

router.get('/:id', (req, res) => {
  const job = jobService.getJob(req.params.id);

  if (!job) {
    return res.status(404).json({ error: 'Job not found' });
  }

  res.json(job);
});

router.delete('/:id', (req, res) => {
  jobService.deleteJob(req.params.id);
  res.json({ message: 'Job cancelled' });
});

module.exports = router;
```

**Dockerfile:**
```dockerfile
FROM mcr.microsoft.com/playwright:v1.40.0-focal

WORKDIR /app

COPY package*.json ./
RUN npm ci --only=production

COPY . .

EXPOSE 3001

CMD ["node", "src/server.js"]
```

**Tests:**
```javascript
// tests/integration/intercars.test.js
const intercarsService = require('../../src/services/intercars.service');

describe('IntercarsService', () => {
  // These tests require valid credentials or mocked Playwright

  it.skip('should login successfully with valid credentials', async () => {
    const result = await intercarsService.login('test@example.com', 'password');
    expect(result.success).toBe(true);
    expect(result.cookies).toBeDefined();
  });

  it.skip('should detect CAPTCHA', async () => {
    // Mock test with CAPTCHA
  });

  it.skip('should scrape product details', async () => {
    // Mock test
  });
});
```

**Deliverables:**
- Working Node.js scraper service
- Intercars login and scraping logic
- Job queue system
- Dockerfile
- Basic tests
- README with usage instructions

---

### STEP 5: Integrate Scraper with Rails

**Goal:** Connect Rails to scraper service, process scraped products

**Tasks:**
1. Create ScraperClient service in Rails
2. Add scraper endpoints to ImportsController
3. Create background job for scraper integration
4. Update ImportedProduct::Normalizer for image downloads
5. Add UI for scraper import wizard
6. Add integration tests

**Services:**
```ruby
# app/services/scraper/client.rb
module Scraper
  class Client
    include HTTParty
    base_uri ENV.fetch('SCRAPER_API_URL', 'http://localhost:3001')

    def initialize
      @headers = {
        'X-API-Key' => ENV.fetch('SCRAPER_API_KEY'),
        'Content-Type' => 'application/json'
      }
    end

    def login(site, username, password)
      response = self.class.post('/login', {
        headers: @headers,
        body: { site: site, username: username, password: password }.to_json
      })

      handle_response(response)
    end

    def start_scrape(session_token, site, options = {})
      response = self.class.post('/scrape', {
        headers: @headers,
        body: {
          session_token: session_token,
          site: site,
          start_url: options[:start_url],
          max_products: options[:max_products]
        }.to_json
      })

      handle_response(response)
    end

    def get_job_status(job_id)
      response = self.class.get("/jobs/#{job_id}", headers: @headers)
      handle_response(response)
    end

    private

    def handle_response(response)
      case response.code
      when 200..299
        JSON.parse(response.body)
      when 401
        raise Scraper::AuthenticationError, 'Invalid API key or session'
      when 403
        raise Scraper::InteractionNeededError, 'CAPTCHA or 2FA detected'
      else
        raise Scraper::Error, "Request failed: #{response.code}"
      end
    end
  end

  class Error < StandardError; end
  class AuthenticationError < Error; end
  class InteractionNeededError < Error; end
end

# app/services/scraper/intercars_importer.rb
module Scraper
  class IntercarsImporter
    def initialize(shop, import_log)
      @shop = shop
      @import_log = import_log
      @client = Client.new
    end

    def execute(username, password)
      @import_log.update!(status: 'processing', started_at: Time.current)

      # Step 1: Login
      login_result = @client.login('intercars', username, password)

      if login_result['error']
        handle_error(login_result['error'])
        return
      end

      session_token = login_result['session_token']

      # Step 2: Start scraping
      scrape_result = @client.start_scrape(session_token, 'intercars', {
        start_url: 'https://ba.e-cat.intercars.eu/bs/',
        max_products: 100
      })

      job_id = scrape_result['job_id']

      # Step 3: Poll for results
      products = poll_job(job_id)

      # Step 4: Create ImportedProducts
      products.each do |product_data|
        @shop.imported_products.create!(
          import_log: @import_log,
          source: 'intercars',
          raw_data: product_data.to_json,
          status: 'pending'
        )
      end

      @import_log.update!(total_rows: products.count)

      # Step 5: Enqueue processing
      @import_log.imported_products.pending.find_each do |imported_product|
        ImportedProduct::ProcessRowJob.perform_later(imported_product.id)
      end

    rescue Scraper::InteractionNeededError => e
      @import_log.update!(
        status: 'failed',
        metadata: { error: 'interaction_needed', message: 'CAPTCHA or 2FA detected. Please complete manually.' }.to_json
      )
    rescue => e
      @import_log.update!(status: 'failed', metadata: { error: e.message }.to_json)
      raise
    end

    private

    def poll_job(job_id, max_attempts = 60)
      attempts = 0

      loop do
        sleep 5
        status = @client.get_job_status(job_id)

        case status['status']
        when 'completed'
          return status['products']
        when 'failed'
          raise Scraper::Error, status['error']
        when 'processing', 'pending'
          attempts += 1
          raise Scraper::Error, 'Job timeout' if attempts > max_attempts
        end
      end
    end

    def handle_error(error_type)
      @import_log.update!(
        status: 'failed',
        metadata: { error: error_type }.to_json
      )
    end
  end
end
```

**Jobs:**
```ruby
# app/jobs/scraper/import_job.rb
module Scraper
  class ImportJob < ApplicationJob
    queue_as :default

    def perform(import_log_id, username, password, save_credentials: false)
      import_log = ImportLog.find(import_log_id)
      shop = import_log.shop

      # Optionally save encrypted credentials
      if save_credentials
        shop.set_integration_credentials('intercars', username, password)
        shop.save!
      end

      importer = IntercarsImporter.new(shop, import_log)
      importer.execute(username, password)
    end
  end
end
```

**Image Download Service:**
```ruby
# app/services/image_downloader.rb
class ImageDownloader
  def initialize(product)
    @product = product
  end

  def download_from_urls(urls)
    urls = Array(urls)

    urls.each_with_index do |url, index|
      next if url.blank?

      begin
        io = URI.open(url)
        filename = "#{@product.sku || @product.id}_#{index}#{File.extname(url)}"

        @product.images.attach(
          io: io,
          filename: filename,
          content_type: io.content_type
        )
      rescue => e
        Rails.logger.error("Failed to download image #{url}: #{e.message}")
      end
    end
  end
end

# Update ImportedProduct::Normalizer
class ImportedProduct::Normalizer
  # ... previous code ...

  def download_images(product)
    image_urls = @raw_data['image_urls'] || @raw_data['images']
    return if image_urls.blank?

    # Parse if comma-separated string
    urls = image_urls.is_a?(String) ? image_urls.split(',').map(&:strip) : image_urls

    downloader = ImageDownloader.new(product)
    downloader.download_from_urls(urls)
  end

  def create_or_update_product(attrs)
    product = @shop.products.find_or_initialize_by(
      source: attrs[:source],
      sku: attrs[:sku]
    )
    product.assign_attributes(attrs)
    product.save!

    # Download images after product is saved
    download_images(product)

    product
  end
end
```

**Controllers:**
```ruby
# app/controllers/api/v1/imports_controller.rb (additions)
class Api::V1::ImportsController < Api::V1::BaseController
  # ... previous code ...

  def create_scrape
    username = params[:username]
    password = params[:password]
    save_creds = params[:save_credentials] == true

    # Check authorization
    authorize @shop, :manage_integrations?

    import_log = @shop.import_logs.create!(
      source: 'intercars',
      status: 'pending',
      metadata: {
        initiated_at: Time.current.iso8601,
        save_credentials: save_creds
      }.to_json
    )

    Scraper::ImportJob.perform_later(
      import_log.id,
      username,
      password,
      save_credentials: save_creds
    )

    render json: {
      import_log_id: import_log.id,
      status: 'initiated'
    }, status: :accepted
  end

  def scrape_result
    import_log = @shop.import_logs.find(params[:id])

    render json: {
      import_log: import_log.as_json(
        include: {
          imported_products: {
            only: [:id, :status, :error_text],
            methods: [:product_preview]
          }
        }
      )
    }
  end
end

# Update routes
# config/routes.rb
namespace :api do
  namespace :v1 do
    resources :shops do
      resources :imports, only: [:index] do
        collection do
          post 'csv', to: 'imports#create_csv'
          post 'scrape', to: 'imports#create_scrape'
        end

        member do
          post 'map', to: 'imports#update_mapping'
          post 'start', to: 'imports#start_import'
          get 'status'
          get 'result', to: 'imports#scrape_result'
        end
      end

      resources :products
    end
  end
end
```

**Tests:**
```ruby
# spec/services/scraper/client_spec.rb
RSpec.describe Scraper::Client do
  let(:client) { described_class.new }

  before do
    stub_const('ENV', ENV.to_h.merge(
      'SCRAPER_API_URL' => 'http://scraper:3001',
      'SCRAPER_API_KEY' => 'test_key'
    ))
  end

  describe '#login' do
    it 'returns session token on success' do
      stub_request(:post, 'http://scraper:3001/login')
        .with(body: { site: 'intercars', username: 'user', password: 'pass' }.to_json)
        .to_return(status: 200, body: { session_token: 'ABC123' }.to_json)

      result = client.login('intercars', 'user', 'pass')
      expect(result['session_token']).to eq('ABC123')
    end

    it 'raises on CAPTCHA' do
      stub_request(:post, 'http://scraper:3001/login')
        .to_return(status: 403, body: { error: 'needs_interaction' }.to_json)

      expect {
        client.login('intercars', 'user', 'pass')
      }.to raise_error(Scraper::InteractionNeededError)
    end
  end
end

# spec/jobs/scraper/import_job_spec.rb
RSpec.describe Scraper::ImportJob do
  let(:shop) { create(:shop) }
  let(:import_log) { create(:import_log, shop: shop, source: 'intercars') }

  it 'executes scraper import' do
    allow_any_instance_of(Scraper::IntercarsImporter).to receive(:execute)

    described_class.perform_now(import_log.id, 'user', 'pass')

    expect(import_log.reload.status).to eq('processing')
  end
end
```

**Deliverables:**
- Rails ↔ Scraper integration
- Background job for scraping
- Image download functionality
- Error handling (CAPTCHA, 2FA)
- Integration tests
- Updated API documentation

---

### STEP 6: Polishing, Tests, Documentation

**Goal:** Complete test coverage, final documentation, production readiness

**Tasks:**
1. Achieve >80% test coverage
2. Add request specs for all API endpoints
3. Create comprehensive README
4. Add API documentation (Postman collection or OpenAPI)
5. Create deployment guide
6. Add scraper selector documentation
7. Performance optimization
8. Security audit

**Test Coverage:**
```ruby
# spec/requests/api/v1/complete_flow_spec.rb
RSpec.describe 'Complete Import Flow', type: :request do
  let(:user) { create(:user) }
  let(:shop) { create(:shop) }

  before do
    shop.memberships.create!(user: user, role: 'owner')
    sign_in user
  end

  describe 'CSV import flow' do
    it 'completes full workflow' do
      # Upload
      csv_file = fixture_file_upload('spec/fixtures/sample_products.csv', 'text/csv')

      post "/api/v1/shops/#{shop.id}/imports/csv", params: { file: csv_file }
      expect(response).to have_http_status(:created)

      import_log_id = JSON.parse(response.body)['import_log_id']

      # Map
      post "/api/v1/shops/#{shop.id}/imports/#{import_log_id}/map", params: {
        column_mappings: {
          'Title' => 'title',
          'Price (BAM)' => 'price',
          'Part Number' => 'sku'
        }
      }
      expect(response).to have_http_status(:ok)

      # Start
      post "/api/v1/shops/#{shop.id}/imports/#{import_log_id}/start"
      expect(response).to have_http_status(:accepted)

      # Process jobs
      perform_enqueued_jobs

      # Check status
      get "/api/v1/shops/#{shop.id}/imports/#{import_log_id}/status"
      expect(response).to have_http_status(:ok)

      data = JSON.parse(response.body)
      expect(data['import_log']['status']).to eq('completed')
      expect(shop.products.count).to be > 0
    end
  end
end
```

**Documentation:**
```markdown
# README.md

# OLX Integration - Product Import System

Production-ready Rails 8 application for importing products from CSV and web scraping.

## Features

- Multi-tenant shop management
- CSV import with intelligent column mapping
- Web scraping from Intercars catalog
- Background job processing
- Image management
- RESTful JSON API

## Tech Stack

- Rails 8.0, Ruby 3.2+
- SQLite (dev), PostgreSQL (production)
- Sidekiq + Redis
- ActiveStorage + MinIO/S3
- Tailwind CSS
- Node.js + Playwright (scraper)

## Quick Start

### Prerequisites

- Ruby 3.2+
- Node.js 18+
- Docker & Docker Compose
- Redis

### Installation

```bash
# Clone repo
git clone <repo_url>
cd olx_integration

# Setup
bin/setup

# Start services
docker-compose up -d

# Start Rails
bin/dev
```

Visit http://localhost:3000

### Environment Variables

Copy `.env.example` to `.env` and configure:

```bash
RAILS_ENV=development
DATABASE_URL=sqlite3:db/development.sqlite3
REDIS_URL=redis://localhost:6379/0
MINIO_ENDPOINT=http://localhost:9000
MINIO_ACCESS_KEY=minioadmin
MINIO_SECRET_KEY=minioadmin
SCRAPER_API_URL=http://localhost:3001
SCRAPER_API_KEY=<generate_random_key>
```

## Usage

### CSV Import

1. Login with magic link
2. Create or select shop
3. Upload CSV file
4. Review auto-mapped columns
5. Adjust mappings if needed
6. Start import
7. Monitor progress

### Scraper Import

1. Navigate to Imports
2. Select "Import from Intercars"
3. Enter credentials
4. Optionally save credentials (encrypted)
5. Start scrape
6. Wait for completion

## API Documentation

See [API.md](docs/API.md) for complete endpoint documentation.

Quick example:
```bash
# Get magic link
curl -X POST http://localhost:3000/api/v1/auth/magic_link \
  -H "Content-Type: application/json" \
  -d '{"email":"user@example.com"}'

# Upload CSV
curl -X POST http://localhost:3000/api/v1/shops/1/imports/csv \
  -H "Cookie: _session_id=..." \
  -F "file=@products.csv"
```

## Testing

```bash
# Run all tests
bundle exec rspec

# With coverage
COVERAGE=true bundle exec rspec

# Scraper tests
cd scraper && npm test
```

## Deployment

See [DEPLOYMENT.md](docs/DEPLOYMENT.md)

## License

MIT
```

**Scraper Documentation:**
```markdown
# docs/scraper-notes.md

# Scraper Implementation Notes

## Intercars Site Structure

### Authentication
- Login URL: https://ba.e-cat.intercars.eu/bs/login
- Form fields: username (email), password
- Session: Cookie-based
- CAPTCHA: May appear on repeated failed logins
- 2FA: Not currently implemented by site

### Product Catalog
- Main catalog: https://ba.e-cat.intercars.eu/bs/
- Categories: Navigate via left sidebar
- Product listings: Paginated (20 per page)
- Product details: Click product card

### Selectors (as of Jan 2024)

Current working selectors in `src/config/intercars.config.js`:

```javascript
productDetail: {
  title: 'h1.product-title',
  sku: '.product-sku',
  brand: '.product-brand',
  price: '.product-price .amount',
  // ... see config file
}
```

### Updating Selectors

If scraping breaks:

1. Inspect the site HTML in browser DevTools
2. Identify new selectors
3. Update `scraper/src/config/intercars.config.js`
4. Test with: `npm run test:integration`
5. Commit changes

### Rate Limiting

Current settings:
- Min delay: 1s between requests
- Max delay: 5s (with backoff)
- Max products per scrape: 100

Adjust in config if needed.

### Error Handling

**CAPTCHA Detected:**
- Scraper returns: `{ error: "needs_interaction", type: "captcha" }`
- Rails shows user: "Manual verification required"
- User must login manually in browser

**2FA Detected:**
- Same as CAPTCHA
- Future: Implement interactive flow

**Network Errors:**
- Retry 3x with exponential backoff
- Final failure logged

## Troubleshooting

### "Login failed"
- Check credentials
- Check for CAPTCHA
- Verify site hasn't changed selectors

### "No products found"
- Check start_url
- Verify selectors still work
- Check site structure hasn't changed

### "Timeout"
- Site may be slow
- Increase timeout in config
- Check network

## Maintenance

Recommended:
- Monthly: Verify selectors still work
- After site updates: Re-check all selectors
- Monitor error rates in logs
```

**Docker Compose (Final):**
```yaml
# docker-compose.yml
version: '3.8'

services:
  web:
    build: .
    command: bundle exec rails server -b 0.0.0.0
    volumes:
      - .:/app
      - bundle:/usr/local/bundle
    ports:
      - "3000:3000"
    environment:
      - DATABASE_URL=sqlite3:db/development.sqlite3
      - REDIS_URL=redis://redis:6379/0
      - MINIO_ENDPOINT=http://minio:9000
      - SCRAPER_API_URL=http://scraper:3001
    env_file:
      - .env
    depends_on:
      - redis
      - minio
      - scraper

  sidekiq:
    build: .
    command: bundle exec sidekiq
    volumes:
      - .:/app
      - bundle:/usr/local/bundle
    environment:
      - DATABASE_URL=sqlite3:db/development.sqlite3
      - REDIS_URL=redis://redis:6379/0
    env_file:
      - .env
    depends_on:
      - redis

  redis:
    image: redis:7-alpine
    ports:
      - "6379:6379"
    volumes:
      - redis:/data

  minio:
    image: minio/minio
    command: server /data --console-address ":9001"
    ports:
      - "9000:9000"
      - "9001:9001"
    environment:
      - MINIO_ROOT_USER=minioadmin
      - MINIO_ROOT_PASSWORD=minioadmin
    volumes:
      - minio:/data

  scraper:
    build: ./scraper
    ports:
      - "3001:3001"
    environment:
      - NODE_ENV=development
      - PORT=3001
      - PLAYWRIGHT_HEADLESS=true
    env_file:
      - .env
    volumes:
      - ./scraper:/app

volumes:
  bundle:
  redis:
  minio:
```

**Deliverables:**
- >80% test coverage
- Complete API documentation
- Deployment guide
- Scraper maintenance docs
- Production-ready configuration
- Security checklist

---

## 9. Testing Strategy

### Model Tests (RSpec + FactoryBot)
```ruby
# spec/models/product_spec.rb
- Associations
- Validations
- Scopes
- Methods (e.g., source_id uniqueness)
```

### Service Tests
```ruby
# spec/services/**/*_spec.rb
- CsvImport::Parser (column detection)
- CsvImport::Processor (file processing)
- ImportedProduct::Normalizer (data normalization)
- Scraper::Client (API calls with VCR or WebMock)
- Scraper::IntercarsImporter (full flow with mocked client)
```

### Job Tests
```ruby
# spec/jobs/**/*_spec.rb
- Idempotency
- Error handling
- Retry logic
- Sidekiq testing mode
```

### Request Tests
```ruby
# spec/requests/api/v1/**/*_spec.rb
- All CRUD operations
- Authentication
- Authorization
- Error responses
- Happy path flows
```

### Integration Tests
```ruby
# spec/integration/**/*_spec.rb
- Complete CSV import flow
- Complete scraper flow
- Multi-user/multi-shop scenarios
```

### Scraper Tests (Jest + Playwright)
```javascript
// tests/integration/intercars.test.js
- Login flow (mocked)
- Product scraping (mocked HTML)
- Error handling
- Throttling
```

---

## 10. Potential Challenges & Solutions

### Challenge 1: SQLite Limitations in Production
**Problem:** SQLite doesn't support concurrent writes well
**Solution:**
- Use SQLite for development only
- Provide clear migration guide to PostgreSQL for production
- Document in README: "SQLite is for development. Use PostgreSQL in production."
- Migrations should be compatible with both

### Challenge 2: Intercars Site Changes
**Problem:** Selectors break when site updates
**Solution:**
- Maintain selector config file
- Implement multiple fallback selectors
- Add monitoring/alerting for scrape failures
- Document selector update process

### Challenge 3: CAPTCHA/2FA
**Problem:** Automated scraping blocked
**Solution:**
- Detect CAPTCHA/2FA early
- Return clear error to user
- Don't attempt bypass (ethical + legal)
- Suggest manual login flow for future enhancement

### Challenge 4: Image Download Performance
**Problem:** Downloading many images is slow
**Solution:**
- Download in background jobs
- Parallel downloads (limit concurrency)
- Optional: Let images stay as URLs initially
- Implement retry logic for failed downloads

### Challenge 5: CSV Encoding Issues
**Problem:** Various encodings (UTF-8, Windows-1252, etc.)
**Solution:**
- Use `encoding: 'UTF-8'` with fallback detection
- Add BOM handling
- Show encoding errors in preview
- Allow user to specify encoding

### Challenge 6: Rate Limiting from Intercars
**Problem:** Too many requests → IP ban
**Solution:**
- Implement respectful throttling (1-2s delays)
- Add exponential backoff
- Limit max products per scrape
- Add per-shop scrape rate limits (via Rack::Attack)

### Challenge 7: Large CSV Files
**Problem:** Memory issues with huge files
**Solution:**
- Stream CSV reading (don't load all into memory)
- Process in batches
- Add file size limits
- Show progress updates

### Challenge 8: Background Job Failures
**Problem:** Jobs fail and data is inconsistent
**Solution:**
- Implement idempotency (check before creating)
- Use database transactions
- Sidekiq retry with dead job queue
- Log all errors for debugging

---

## 11. Future Enhancements (Post-MVP)

1. **OLX Publishing**
   - Integrate with OLX API
   - Map products to OLX categories
   - Auto-publish new products
   - Sync inventory/prices

2. **Multiple Sources**
   - Add more scraper targets
   - Plugin architecture for scrapers
   - Generic scraper configuration UI

3. **Advanced Mapping**
   - ML-based column detection
   - Mapping templates
   - Validation rules

4. **Analytics**
   - Import success rates
   - Product performance tracking
   - Error analytics

5. **Webhooks**
   - Notify on import completion
   - Integration with external systems

6. **API Enhancements**
   - GraphQL support
   - Webhooks for events
   - Batch operations

7. **UI Improvements**
   - Real-time progress (ActionCable)
   - Drag-and-drop CSV upload
   - Rich product editor

---

## 12. Production Deployment Considerations

### Database Migration (SQLite → PostgreSQL)

```bash
# 1. Export from SQLite
sqlite3 db/production.sqlite3 .dump > dump.sql

# 2. Convert to PostgreSQL
# Use tools like: https://github.com/caiiiycuk/db-migrate-sqlite-to-postgres

# 3. Import to PostgreSQL
psql -U postgres -d olx_integration_production -f dump_postgres.sql

# 4. Update DATABASE_URL
DATABASE_URL=postgresql://user:pass@host:5432/olx_integration_production
```

### Environment Variables (Production)

```bash
RAILS_ENV=production
SECRET_KEY_BASE=<generate_with_rails_secret>
DATABASE_URL=postgresql://...
REDIS_URL=redis://...
AWS_ACCESS_KEY_ID=...
AWS_SECRET_ACCESS_KEY=...
AWS_BUCKET=olx-integration-prod
SCRAPER_API_URL=https://scraper.yourdomain.com
SCRAPER_API_KEY=<secure_random>
```

### Hosting Options

1. **Heroku** (simplest)
   - Easy deployment
   - Add-ons for PostgreSQL, Redis
   - Separate dyno for Sidekiq
   - Separate app for scraper

2. **AWS**
   - EC2 for Rails + Sidekiq
   - RDS for PostgreSQL
   - ElastiCache for Redis
   - S3 for storage
   - ECS/Fargate for scraper

3. **DigitalOcean**
   - App Platform for Rails
   - Managed PostgreSQL
   - Managed Redis
   - Spaces for storage

### CI/CD Pipeline

```yaml
# .github/workflows/ci.yml
name: CI

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest

    services:
      redis:
        image: redis:7-alpine

    steps:
      - uses: actions/checkout@v3

      - name: Set up Ruby
        uses: ruby/setup-ruby@v1
        with:
          ruby-version: 3.2
          bundler-cache: true

      - name: Run tests
        env:
          RAILS_ENV: test
          DATABASE_URL: sqlite3:db/test.sqlite3
        run: |
          bundle exec rails db:create db:schema:load
          bundle exec rspec

      - name: Run linter
        run: bundle exec rubocop

  scraper_test:
    runs-on: ubuntu-latest

    steps:
      - uses: actions/checkout@v3

      - name: Set up Node.js
        uses: actions/setup-node@v3
        with:
          node-version: 18

      - name: Install dependencies
        working-directory: ./scraper
        run: npm ci

      - name: Run tests
        working-directory: ./scraper
        run: npm test
```

---

## 13. Summary & Next Steps

### What We're Building

A comprehensive, production-ready Rails 8 application that:
- Manages multi-tenant shops with secure authentication
- Imports products from CSV with intelligent mapping
- Scrapes products from Intercars using ethical, respectful automation
- Processes everything in background jobs
- Provides a clean JSON API and basic UI
- Has comprehensive tests and documentation

### Technology Decisions

✅ **Rails 8** - Latest features, ActiveRecord encryption
✅ **SQLite (dev)** - Simple setup, easy migration to Postgres
✅ **Devise + Passwordless** - Battle-tested magic link auth
✅ **Sidekiq** - Reliable background jobs
✅ **Node.js + Playwright** - Powerful scraping with real browser
✅ **Tailwind CSS** - Modern, utility-first styling
✅ **Docker Compose** - Unified development environment

### Implementation Approach

We'll build this in 6 complete steps:
1. **Infrastructure** - Repo, Docker, CI
2. **Core Models** - Auth, shops, authorization
3. **CSV Import** - Full upload-to-products flow
4. **Scraper Service** - Node.js microservice
5. **Integration** - Connect Rails ↔ Scraper
6. **Polish** - Tests, docs, production-ready

Each step will include:
- Complete code files
- Migrations
- Tests
- Documentation
- Working features

### Key Principles

🔒 **Security First** - Encrypted credentials, no secret exposure
🤖 **Ethical Scraping** - Respectful throttling, CAPTCHA detection
✅ **Test Coverage** - >80% with unit + integration tests
📚 **Documentation** - README, API docs, selector maintenance
🚀 **Production Ready** - Real deployment guide, error handling

---

## Ready to Start?

This plan provides a complete blueprint for building the OLX Integration MVP. The implementation will follow these exact steps, producing working, tested code at each stage.

**First deliverable (STEP 1)** will be a fully functioning development environment with Docker Compose running all services, ready to build features on top of.
