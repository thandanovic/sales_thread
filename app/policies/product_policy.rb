class ProductPolicy < ApplicationPolicy
  def index?
    user.present? && user_is_shop_member?
  end

  def show?
    user.present? && user_is_shop_member?
  end

  def create?
    user.present? && (user_is_shop_owner? || user_is_shop_admin?)
  end

  def update?
    user.present? && (user_is_shop_owner? || user_is_shop_admin?)
  end

  def destroy?
    user.present? && (user_is_shop_owner? || user_is_shop_admin?)
  end

  class Scope < ApplicationPolicy::Scope
    def resolve
      if user.present?
        shop_ids = user.shops.pluck(:id)
        scope.where(shop_id: shop_ids)
      else
        scope.none
      end
    end
  end

  private

  def shop
    record.shop
  end

  def user_is_shop_member?
    shop.users.include?(user)
  end

  def user_is_shop_owner?
    membership = shop.memberships.find_by(user: user)
    membership&.owner?
  end

  def user_is_shop_admin?
    membership = shop.memberships.find_by(user: user)
    membership&.admin?
  end
end
