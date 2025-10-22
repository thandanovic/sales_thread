class OlxCategory < ApplicationRecord
  # Associations
  has_many :olx_category_attributes, dependent: :destroy
  has_many :olx_category_templates, dependent: :destroy

  # Self-referential association for parent/child categories
  belongs_to :parent, class_name: 'OlxCategory', optional: true
  has_many :children, class_name: 'OlxCategory', foreign_key: 'parent_id', dependent: :destroy

  # Validations
  validates :external_id, presence: true, uniqueness: true
  validates :name, presence: true

  # Scopes
  scope :root_categories, -> { where(parent_id: nil) }
  scope :with_shipping, -> { where(has_shipping: true) }
  scope :with_brand, -> { where(has_brand: true) }
  scope :leaf_categories, -> {
    where.not(id: OlxCategory.select(:parent_id).where.not(parent_id: nil))
  }

  ##
  # Get full category path (e.g., "Electronics > Mobile Phones > Smartphones")
  #
  # @return [String] Category path
  #
  def full_path
    path = [name]
    current = self

    while current.parent.present?
      current = current.parent
      path.unshift(current.name)
    end

    path.join(' > ')
  end

  ##
  # Check if category is a leaf (has no children)
  #
  # @return [Boolean]
  #
  def leaf?
    children.empty?
  end

  ##
  # Get all ancestor categories
  #
  # @return [Array<OlxCategory>]
  #
  def ancestors
    ancestors = []
    current = parent

    while current.present?
      ancestors << current
      current = current.parent
    end

    ancestors
  end
end
