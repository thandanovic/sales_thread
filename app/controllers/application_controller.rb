class ApplicationController < ActionController::Base
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Include Pundit for authorization
  include Pundit::Authorization

  # Devise: configure permitted parameters
  before_action :configure_permitted_parameters, if: :devise_controller?

  # Pundit: rescue from unauthorized access
  rescue_from Pundit::NotAuthorizedError, with: :user_not_authorized

  # Make impersonation helpers available to views
  helper_method :true_user, :impersonating?

  protected

  def configure_permitted_parameters
    devise_parameter_sanitizer.permit(:sign_in, keys: [:email])
    devise_parameter_sanitizer.permit(:account_update, keys: [:email])
  end

  private

  def user_not_authorized
    flash[:alert] = "You are not authorized to perform this action."
    redirect_to(request.referrer || root_path)
  end

  # Override current_user to support impersonation
  def current_user
    if session[:impersonated_user_id].present? && session[:admin_user_id].present?
      @current_user ||= User.find_by(id: session[:impersonated_user_id])
    else
      super
    end
  end

  # The actual admin user (even when impersonating)
  def true_user
    if session[:admin_user_id].present?
      @true_user ||= User.find_by(id: session[:admin_user_id])
    else
      current_user
    end
  end

  # Check if currently impersonating another user
  def impersonating?
    session[:impersonated_user_id].present? && session[:admin_user_id].present?
  end

  # Find a shop with system admin access
  # System admins can access any shop, others can only access their shops
  def find_shop_with_admin_access(shop_id)
    if true_user&.system_admin?
      Shop.find(shop_id)
    else
      current_user.shops.find(shop_id)
    end
  end
end
