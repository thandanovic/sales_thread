class OlxLocation < ApplicationRecord
  # Associations
  has_many :olx_category_templates, dependent: :destroy

  # Validations
  validates :external_id, presence: true, uniqueness: true
  validates :name, presence: true

  # Scopes
  scope :by_country, ->(country_id) { where(country_id: country_id) }
  scope :by_state, ->(state_id) { where(state_id: state_id) }
  scope :by_canton, ->(canton_id) { where(canton_id: canton_id) }
  scope :with_coordinates, -> { where.not(lat: nil, lon: nil) }

  ##
  # Get full location path (e.g., "Bosnia and Herzegovina > Sarajevo Canton > Sarajevo")
  #
  # @return [String] Location path
  #
  def full_path
    parts = []
    parts << country_name if country_id.present?
    parts << state_name if state_id.present?
    parts << canton_name if canton_id.present?
    parts << name

    parts.compact.join(' > ')
  end

  ##
  # Check if location has geographic coordinates
  #
  # @return [Boolean]
  #
  def has_coordinates?
    lat.present? && lon.present?
  end

  ##
  # Get display name (name with zip code if available)
  #
  # @return [String]
  #
  def display_name
    if zip_code.present?
      "#{name} (#{zip_code})"
    else
      name
    end
  end

  private

  ##
  # Get country name from ID (placeholder - could be enhanced with country lookup)
  #
  def country_name
    # This is a simplified version. In a real app, you might want to
    # store country names or use a gem like Countries
    case country_id
    when 1
      'Bosnia and Herzegovina'
    else
      "Country #{country_id}"
    end
  end

  ##
  # Get state/region name from ID (placeholder)
  #
  def state_name
    # This is a simplified version
    state_id ? "State #{state_id}" : nil
  end

  ##
  # Get canton/municipality name from ID (placeholder)
  #
  def canton_name
    # This is a simplified version
    canton_id ? "Canton #{canton_id}" : nil
  end
end
