class Product < ApplicationRecord
  belongs_to :shop

  # ActiveStorage for images
  has_many_attached :images

  # Enums
  enum :source, { csv: 'csv', intercars: 'intercars' }, validate: true

  # Validations
  validates :title, presence: true
  validates :source, presence: true
  validates :currency, inclusion: { in: %w[BAM EUR USD] }, allow_nil: true

  # Scopes
  scope :published, -> { where(published: true) }
  scope :unpublished, -> { where(published: false) }
  scope :by_source, ->(source) { where(source: source) }

  # Callbacks
  before_save :calculate_final_price
  after_initialize :set_defaults, if: :new_record?

  private

  def set_defaults
    self.currency ||= 'BAM'
    self.stock ||= 0
    self.published ||= false
    self.price ||= 0.0
    self.margin ||= 0.0
  end

  def calculate_final_price
    # Calculate final_price = price * (1 + margin/100)
    base_price = price || 0.0
    margin_percentage = margin || 0.0
    self.final_price = base_price * (1 + margin_percentage / 100.0)
  end
end
