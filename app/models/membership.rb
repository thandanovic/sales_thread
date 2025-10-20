class Membership < ApplicationRecord
  belongs_to :user
  belongs_to :shop

  # Enum for roles
  enum :role, { owner: 'owner', admin: 'admin', member: 'member' }, default: :member

  # Validations
  validates :role, presence: true
  validates :user_id, uniqueness: { scope: :shop_id, message: "is already a member of this shop" }
end
