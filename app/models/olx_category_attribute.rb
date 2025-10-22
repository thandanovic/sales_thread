class OlxCategoryAttribute < ApplicationRecord
  # Associations
  belongs_to :olx_category

  # Validations
  validates :name, presence: true
  validates :attribute_type, presence: true

  # Scopes
  scope :required_attributes, -> { where(required: true) }
  scope :optional_attributes, -> { where(required: false) }

  ##
  # Get attribute values/options if available
  #
  # @return [Array, nil] Array of possible values or nil
  #
  def possible_values
    options&.dig('values')
  end

  ##
  # Check if attribute has predefined values
  #
  # @return [Boolean]
  #
  def has_predefined_values?
    possible_values.present?
  end

  ##
  # Get display label
  #
  # @return [String]
  #
  def display_label
    options&.dig('label') || name.titleize
  end
end
