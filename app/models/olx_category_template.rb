class OlxCategoryTemplate < ApplicationRecord
  # Associations
  belongs_to :shop
  belongs_to :olx_category
  belongs_to :olx_location, optional: true
  has_many :products, foreign_key: 'olx_category_template_id', dependent: :nullify

  # Validations
  validates :name, presence: true
  validates :olx_category_id, presence: true

  # Scopes
  scope :by_listing_type, ->(type) { where(default_listing_type: type) }
  scope :by_state, ->(state) { where(default_state: state) }

  ##
  # Get the full template display name with category and location
  #
  # @return [String]
  #
  def display_name
    if olx_location
      "#{name} (#{olx_category.name} - #{olx_location.name})"
    else
      "#{name} (#{olx_category.name})"
    end
  end

  ##
  # Get attribute mapping for a specific attribute
  #
  # @param attribute_name [String] Name of the attribute
  # @return [String, nil] Mapping rule or nil
  #
  def attribute_mapping_for(attribute_name)
    attribute_mappings&.dig(attribute_name)
  end

  ##
  # Set attribute mapping
  #
  # @param attribute_name [String] Name of the attribute
  # @param mapping [String] Mapping rule (e.g., "product.brand" or "fixed:New")
  #
  def set_attribute_mapping(attribute_name, mapping)
    self.attribute_mappings ||= {}
    self.attribute_mappings[attribute_name] = mapping
  end
end
