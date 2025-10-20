class ProductsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_shop, only: [:index, :show, :new, :create, :edit, :update, :destroy, :bulk_update_margin]
  before_action :set_product, only: [:show, :edit, :update, :destroy]
  before_action :authorize_shop, only: [:new, :create, :edit, :update, :destroy, :bulk_update_margin]

  def index
    @products = @shop.products.order(created_at: :desc).page(params[:page])
  end

  def show
    # @shop and @product are already set by before_action filters
  end

  def new
    @product = @shop.products.new
  end

  def create
    @product = @shop.products.new(product_params)
    @product.source = 'csv' unless @product.source.present?

    if @product.save
      redirect_to shop_products_path(@shop), notice: 'Product was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
  end

  def update
    if @product.update(product_params)
      redirect_to shop_products_path(@shop), notice: 'Product was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @product.destroy
    redirect_to shop_products_path(@shop), notice: 'Product was successfully deleted.'
  end

  def bulk_update_margin
    product_ids = params[:product_ids] || []
    margin = params[:margin]

    if product_ids.empty?
      redirect_to shop_products_path(@shop), alert: 'No products selected.'
      return
    end

    if margin.blank?
      redirect_to shop_products_path(@shop), alert: 'Please provide a margin value.'
      return
    end

    updated_count = 0
    @shop.products.where(id: product_ids).find_each do |product|
      product.update(margin: margin)
      updated_count += 1
    end

    redirect_to shop_products_path(@shop), notice: "Successfully updated margin for #{updated_count} product(s)."
  end

  private

  def set_shop
    @shop = current_user.shops.find(params[:shop_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to shops_path, alert: 'Shop not found or you do not have access.'
  end

  def set_product
    if params[:shop_id]
      # Nested route - product belongs to shop
      @product = @shop.products.find(params[:id])
    end
  rescue ActiveRecord::RecordNotFound
    redirect_to shop_products_path(@shop), alert: 'Product not found.'
  end

  def authorize_shop
    membership = @shop.memberships.find_by(user: current_user)
    unless membership&.owner? || membership&.admin?
      redirect_to shop_path(@shop), alert: 'You are not authorized to perform this action.'
    end
  end

  def product_params
    params.require(:product).permit(
      :title, :sku, :brand, :category, :description,
      :price, :currency, :margin, :stock, :published, :source,
      :source_id, :specs, images: []
    )
  end
end
