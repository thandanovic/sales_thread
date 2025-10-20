class ImportLog < ApplicationRecord
  belongs_to :shop
  has_many :imported_products, dependent: :nullify

  # Enums
  enum :status, {
    pending: 'pending',
    processing: 'processing',
    completed: 'completed',
    completed_with_errors: 'completed_with_errors',
    failed: 'failed'
  }, default: :pending
  enum :source, { csv: 'csv', intercars: 'intercars' }

  # Validations
  validates :source, presence: true

  # Default values
  after_initialize :set_defaults, if: :new_record?

  # Methods
  def progress_percentage
    return 0 if total_rows.zero?
    ((processed_rows.to_f / total_rows) * 100).round(2)
  end

  def has_errors?
    failed_rows.to_i > 0
  end

  private

  def set_defaults
    self.total_rows ||= 0
    self.processed_rows ||= 0
    self.successful_rows ||= 0
    self.failed_rows ||= 0
  end
end
