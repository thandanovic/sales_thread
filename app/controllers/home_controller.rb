class HomeController < ApplicationController
  def index
    if user_signed_in?
      @shops = current_user.shops.order(created_at: :desc)
      @recent_imports = ImportLog.joins(:shop)
                                  .where(shop: @shops)
                                  .order(created_at: :desc)
                                  .limit(5)
    end
  end
end
