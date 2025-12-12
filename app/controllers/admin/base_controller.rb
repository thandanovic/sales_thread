module Admin
  class BaseController < ApplicationController
    before_action :authenticate_user!
    before_action :require_admin!

    private

    def require_admin!
      unless true_user&.system_admin?
        flash[:alert] = "You must be a system administrator to access this area."
        redirect_to root_path
      end
    end
  end
end
