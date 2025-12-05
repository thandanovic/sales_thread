class Shop < ApplicationRecord
  # Encryption for sensitive settings
  encrypts :settings

  # Active Storage
  has_one_attached :logo

  # Associations
  has_many :memberships, dependent: :destroy
  has_many :users, through: :memberships
  has_many :products, dependent: :destroy
  has_many :imported_products, dependent: :destroy
  has_many :import_logs, dependent: :destroy
  has_many :olx_category_templates, dependent: :destroy
  has_many :olx_listings, dependent: :destroy

  # Validations
  validates :name, presence: true

  # Methods
  def owner
    memberships.find_by(role: 'owner')&.user
  end

  def formatted_olx_token_expiration
    return 'Unknown' if olx_token_expires_at.blank?

    date = olx_token_expires_at.is_a?(String) ? Time.parse(olx_token_expires_at) : olx_token_expires_at
    date.strftime('%B %d, %Y')
  rescue
    'Unknown'
  end

  def integration_credentials(site)
    return {} unless settings.present?
    parsed_settings.dig(site.to_s, 'credentials') || {}
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
  rescue JSON::ParserError
    {}
  end
end
