# Active Record Encryption Configuration
# This configures the encryption keys for development

Rails.application.configure do
  # Only configure if not already set (avoid overriding production credentials)
  if Rails.env.development? || Rails.env.test?
    config.active_record.encryption.primary_key = "ul38X5wlFcyiRg0zv4QYcTg9QQDfyhgp"
    config.active_record.encryption.deterministic_key = "Z2gRXnekFfKdxGqMsyIMQYEK6QzAoyAY"
    config.active_record.encryption.key_derivation_salt = "tuH1ZIl7hyLZAQkDqIosnjZgOw8ERg5M"
  end
end
