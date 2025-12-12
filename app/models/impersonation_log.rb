class ImpersonationLog < ApplicationRecord
  belongs_to :admin_user, class_name: 'User'
  belongs_to :impersonated_user, class_name: 'User'

  # Validations
  validates :started_at, presence: true

  # Scopes
  scope :active, -> { where(ended_at: nil) }
  scope :recent, -> { order(started_at: :desc).limit(50) }

  # End the impersonation session
  def end_impersonation!
    update!(ended_at: Time.current)
  end

  def active?
    ended_at.nil?
  end

  def duration
    return nil unless ended_at
    ended_at - started_at
  end
end
