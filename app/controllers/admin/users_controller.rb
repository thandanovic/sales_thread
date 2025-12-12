module Admin
  class UsersController < BaseController
    before_action :set_user, only: [:show, :edit, :update, :destroy, :impersonate, :add_membership, :remove_membership, :update_membership]

    def index
      @users = User.order(created_at: :desc).page(params[:page]).per(50)
    end

    def show
      @memberships = @user.memberships.includes(:shop)
      @available_shops = Shop.where.not(id: @user.memberships.select(:shop_id)).order(:name)
    end

    def new
      @user = User.new
      @shops = Shop.order(:name)
    end

    def create
      @user = User.new(user_params)
      @user.password = SecureRandom.hex(8) if @user.password.blank?

      if @user.save
        # Create membership if shop and role were provided
        if params[:shop_id].present? && params[:membership_role].present?
          @user.memberships.create(
            shop_id: params[:shop_id],
            role: params[:membership_role]
          )
        end

        redirect_to admin_users_path, notice: "User was successfully created."
      else
        @shops = Shop.order(:name)
        render :new, status: :unprocessable_entity
      end
    end

    def edit
      @memberships = @user.memberships.includes(:shop)
      @available_shops = Shop.where.not(id: @user.memberships.select(:shop_id)).order(:name)
    end

    def update
      update_params = user_params
      # Don't update password if it's blank
      update_params = update_params.except(:password, :password_confirmation) if update_params[:password].blank?

      if @user.update(update_params)
        redirect_to admin_user_path(@user), notice: "User was successfully updated."
      else
        @memberships = @user.memberships.includes(:shop)
        @available_shops = Shop.where.not(id: @user.memberships.select(:shop_id)).order(:name)
        render :edit, status: :unprocessable_entity
      end
    end

    def destroy
      if @user == true_user
        redirect_to admin_users_path, alert: "You cannot delete yourself."
        return
      end

      @user.destroy
      redirect_to admin_users_path, notice: "User was successfully deleted."
    end

    def impersonate
      authorize @user, :impersonate?

      if @user == true_user
        redirect_to admin_users_path, alert: "You cannot impersonate yourself."
        return
      end

      # Create impersonation log
      ImpersonationLog.create!(
        admin_user: true_user,
        impersonated_user: @user,
        started_at: Time.current,
        reason: params[:reason]
      )

      # Store the admin user ID and set the impersonated user
      session[:admin_user_id] = true_user.id
      session[:impersonated_user_id] = @user.id

      redirect_to root_path, notice: "Now impersonating #{@user.email}. Click 'Stop Impersonating' to return."
    end

    def add_membership
      if params[:shop_id].blank?
        redirect_to admin_user_path(@user), alert: "Please select a shop."
        return
      end

      membership = @user.memberships.build(shop_id: params[:shop_id], role: params[:role] || 'agent')

      if membership.save
        redirect_to admin_user_path(@user), notice: "Membership added successfully."
      else
        redirect_to admin_user_path(@user), alert: membership.errors.full_messages.join(", ")
      end
    end

    def remove_membership
      membership = @user.memberships.find(params[:membership_id])
      membership.destroy
      redirect_to admin_user_path(@user), notice: "Membership removed."
    end

    def update_membership
      membership = @user.memberships.find(params[:membership_id])
      membership.update(role: params[:role])
      redirect_to admin_user_path(@user), notice: "Role updated."
    end

    private

    def set_user
      @user = User.find(params[:id])
    end

    def user_params
      params.require(:user).permit(:email, :password, :password_confirmation, :admin)
    end
  end
end
