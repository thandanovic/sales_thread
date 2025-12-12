module Admin
  class ImpersonationsController < ApplicationController
    before_action :authenticate_user!

    def destroy
      if session[:admin_user_id].present?
        # End the active impersonation log
        log = ImpersonationLog.find_by(
          admin_user_id: session[:admin_user_id],
          impersonated_user_id: session[:impersonated_user_id],
          ended_at: nil
        )
        log&.end_impersonation!

        # Clear impersonation session
        session.delete(:impersonated_user_id)
        session.delete(:admin_user_id)

        redirect_to admin_users_path, notice: "Stopped impersonating. You are now back as yourself."
      else
        redirect_to root_path, alert: "You are not currently impersonating anyone."
      end
    end
  end
end
