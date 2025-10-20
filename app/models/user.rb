class User < ApplicationRecord
  # Include default devise modules
  devise :database_authenticatable, :registerable,
         :rememberable, :trackable, :validatable

  # Associations
  has_many :memberships, dependent: :destroy
  has_many :shops, through: :memberships

  # Validations
  validates :email, presence: true, uniqueness: true, format: { with: URI::MailTo::EMAIL_REGEXP }
end
