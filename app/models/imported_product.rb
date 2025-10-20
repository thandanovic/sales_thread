class ImportedProduct < ApplicationRecord
  belongs_to :shop
  belongs_to :import_log, optional: true
  belongs_to :product, optional: true

  # Enums
  enum :status, { pending: 'pending', processing: 'processing', imported: 'imported', error: 'error' }, default: :pending
  enum :source, { csv: 'csv', intercars: 'intercars' }

  # Validations
  validates :source, presence: true
  validates :raw_data, presence: true

  # Scopes
  scope :by_status, ->(status) { where(status: status) }
  scope :failed, -> { where(status: 'error') }
end
