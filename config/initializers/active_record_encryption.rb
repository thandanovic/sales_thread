# Active Record Encryption Configuration

Rails.application.configure do
  if Rails.env.production?
    # Production: read from environment variables
    config.active_record.encryption.primary_key = ENV["ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY"]
    config.active_record.encryption.deterministic_key = ENV["ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY"]
    config.active_record.encryption.key_derivation_salt = ENV["ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT"]
  else
    # Development/Test: use hardcoded keys
    config.active_record.encryption.primary_key = "ul38X5wlFcyiRg0zv4QYcTg9QQDfyhgp"
    config.active_record.encryption.deterministic_key = "Z2gRXnekFfKdxGqMsyIMQYEK6QzAoyAY"
    config.active_record.encryption.key_derivation_salt = "tuH1ZIl7hyLZAQkDqIosnjZgOw8ERg5M"
  end
end
