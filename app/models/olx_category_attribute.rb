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
    # Options can be either a Hash (with 'values' key) or an Array
    if options.is_a?(Hash)
      options.dig('values')
    elsif options.is_a?(Array)
      options
    else
      nil
    end
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
    # Options can be either a Hash (with 'label' key) or an Array
    if options.is_a?(Hash)
      options.dig('label') || name.titleize
    else
      name.titleize
    end
  end
end
