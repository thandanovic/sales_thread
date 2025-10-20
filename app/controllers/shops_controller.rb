class ShopsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_shop, only: [:show, :edit, :update, :destroy]
  before_action :authorize_shop, only: [:edit, :update, :destroy]

  def index
    @shops = current_user.shops.order(created_at: :desc)
  end

  def show
    @products = @shop.products.order(created_at: :desc).limit(10)
    @recent_imports = @shop.import_logs.order(created_at: :desc).limit(5)
  end

  def new
    @shop = Shop.new
  end

  def create
    @shop = Shop.new(shop_params)

    if @shop.save
      # Create membership with owner role
      @shop.memberships.create!(user: current_user, role: 'owner')

      redirect_to @shop, notice: 'Shop was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @shop.update(shop_params)
      redirect_to @shop, notice: 'Shop was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @shop.destroy
    redirect_to shops_url, notice: 'Shop was successfully deleted.'
  end

  private

  def set_shop
    @shop = current_user.shops.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to shops_path, alert: 'Shop not found or you do not have access.'
  end

  def authorize_shop
    membership = @shop.memberships.find_by(user: current_user)
    unless membership&.owner? || membership&.admin?
      redirect_to @shop, alert: 'You are not authorized to perform this action.'
    end
  end

  def shop_params
    params.require(:shop).permit(:name)
  end
end
