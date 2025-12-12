class HomeController < ApplicationController
  def index
    if user_signed_in?
      # Auto-redirect for single-shop users
      if current_user.single_shop_access?
        redirect_to current_user.single_shop
        return
      end

      @shops = current_user.accessible_shops.order(created_at: :desc)
      @recent_imports = ImportLog.joins(:shop)
                                  .where(shop: @shops)
                                  .order(created_at: :desc)
                                  .limit(5)
    end
  end
end
