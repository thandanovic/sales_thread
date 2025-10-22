class ProductsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_shop, only: [:index, :show, :new, :create, :edit, :update, :destroy, :bulk_update_margin, :bulk_destroy, :publish_to_olx, :publish_to_olx_live, :update_on_olx, :unpublish_from_olx, :remove_from_olx]
  before_action :set_product, only: [:show, :edit, :update, :destroy, :publish_to_olx, :publish_to_olx_live, :update_on_olx, :unpublish_from_olx, :remove_from_olx]
  before_action :authorize_shop, only: [:new, :create, :edit, :update, :destroy, :bulk_update_margin, :bulk_destroy, :publish_to_olx, :publish_to_olx_live, :update_on_olx, :unpublish_from_olx, :remove_from_olx]

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

  def bulk_destroy
    product_ids = params[:product_ids] || []

    if product_ids.empty?
      redirect_to shop_products_path(@shop), alert: 'No products selected.'
      return
    end

    deleted_count = 0
    @shop.products.where(id: product_ids).find_each do |product|
      # This will cascade delete:
      # - olx_listing (dependent: :destroy)
      # - imported_products (dependent: :destroy)
      # - images (ActiveStorage attachments)
      product.destroy
      deleted_count += 1
    end

    redirect_to shop_products_path(@shop), notice: "Successfully deleted #{deleted_count} product(s) and all associated data."
  end

  ##
  # Publish product to OLX as draft
  #
  def publish_to_olx
    Rails.logger.info "[Products Controller] Publishing product #{@product.id} to OLX as draft"

    begin
      listing = @product.publish_to_olx
      Rails.logger.info "[Products Controller] ✓ Successfully published product #{@product.id} as draft"

      flash[:notice] = "Product published to OLX as draft. Listing ID: #{listing.external_listing_id}"
      redirect_to shop_product_path(@shop, @product)
    rescue ArgumentError => e
      Rails.logger.error "[Products Controller] ✗ Validation error: #{e.message}"

      flash[:alert] = "<strong>Validation Error:</strong><br>#{e.message}<br><br>Please ensure the product has an OLX category template assigned with valid category and location.".html_safe
      redirect_to shop_product_path(@shop, @product)
    rescue OlxApiService::AuthenticationError => e
      Rails.logger.error "[Products Controller] ✗ Authentication error: #{e.message}"

      flash[:alert] = "<strong>Authentication Error:</strong><br>#{e.message}<br><br>Please check your OLX credentials in shop settings.".html_safe
      redirect_to shop_product_path(@shop, @product)
    rescue OlxApiService::ValidationError => e
      Rails.logger.error "[Products Controller] ✗ OLX validation error: #{e.message}"

      flash[:alert] = "<strong>OLX Validation Error:</strong><br>#{e.message}<br><br>Please check the product data and template configuration.".html_safe
      redirect_to shop_product_path(@shop, @product)
    rescue StandardError => e
      Rails.logger.error "[Products Controller] ✗ Unexpected error: #{e.class.name} - #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")

      flash[:alert] = "<strong>Error Publishing to OLX:</strong><br>#{e.message}<br><br><strong>Error Type:</strong> #{e.class.name}<br><br>Check the logs for more details.".html_safe
      redirect_to shop_product_path(@shop, @product)
    end
  end

  ##
  # Publish product to OLX and make it live immediately
  #
  def publish_to_olx_live
    Rails.logger.info "[Products Controller] Publishing product #{@product.id} to OLX live"

    begin
      listing = @product.publish_to_olx!
      Rails.logger.info "[Products Controller] ✓ Successfully published product #{@product.id} live"

      flash[:notice] = "Product published live on OLX! <br><a href='#{listing.olx_url}' target='_blank' class='underline'>View listing on OLX</a>".html_safe
      redirect_to shop_product_path(@shop, @product)
    rescue ArgumentError => e
      Rails.logger.error "[Products Controller] ✗ Validation error: #{e.message}"

      flash[:alert] = "<strong>Validation Error:</strong><br>#{e.message}<br><br>Please ensure the product has an OLX category template assigned with valid category and location.".html_safe
      redirect_to shop_product_path(@shop, @product)
    rescue OlxApiService::AuthenticationError => e
      Rails.logger.error "[Products Controller] ✗ Authentication error: #{e.message}"

      flash[:alert] = "<strong>Authentication Error:</strong><br>#{e.message}<br><br>Please check your OLX credentials in shop settings.".html_safe
      redirect_to shop_product_path(@shop, @product)
    rescue OlxApiService::ValidationError => e
      Rails.logger.error "[Products Controller] ✗ OLX validation error: #{e.message}"

      flash[:alert] = "<strong>OLX Validation Error:</strong><br>#{e.message}<br><br>Please check the product data and template configuration.".html_safe
      redirect_to shop_product_path(@shop, @product)
    rescue StandardError => e
      Rails.logger.error "[Products Controller] ✗ Unexpected error: #{e.class.name} - #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")

      flash[:alert] = "<strong>Error Publishing to OLX:</strong><br>#{e.message}<br><br><strong>Error Type:</strong> #{e.class.name}<br><br>Check the logs for more details.".html_safe
      redirect_to shop_product_path(@shop, @product)
    end
  end

  ##
  # Unpublish product from OLX (set to draft)
  #
  def unpublish_from_olx
    begin
      @product.unpublish_from_olx
      redirect_to shop_product_path(@shop, @product), notice: 'Product unpublished from OLX (set to draft).'
    rescue StandardError => e
      redirect_to shop_product_path(@shop, @product), alert: "Failed to unpublish from OLX: #{e.message}"
    end
  end

  ##
  # Remove product listing from OLX completely
  #
  def remove_from_olx
    begin
      @product.remove_from_olx
      redirect_to shop_product_path(@shop, @product), notice: 'Product removed from OLX completely.'
    rescue StandardError => e
      redirect_to shop_product_path(@shop, @product), alert: "Failed to remove from OLX: #{e.message}"
    end
  end

  ##
  # Update existing OLX listing with latest product data
  #
  def update_on_olx
    Rails.logger.info "[Products Controller] Updating OLX listing for product #{@product.id}"

    begin
      unless @product.olx_listing&.external_listing_id.present?
        flash[:alert] = "Product must be published to OLX before it can be updated."
        redirect_to shop_product_path(@shop, @product)
        return
      end

      service = OlxListingService.new(@product)
      listing = service.update_listing(@product.olx_listing)

      Rails.logger.info "[Products Controller] ✓ Successfully updated OLX listing #{listing.external_listing_id}"

      flash[:notice] = "OLX listing updated successfully! <br><a href='#{listing.olx_url}' target='_blank' class='underline'>View updated listing on OLX</a>".html_safe
      redirect_to shop_product_path(@shop, @product)
    rescue ArgumentError => e
      Rails.logger.error "[Products Controller] ✗ Validation error: #{e.message}"

      flash[:alert] = "<strong>Validation Error:</strong><br>#{e.message}<br><br>Please check the product data and template configuration.".html_safe
      redirect_to shop_product_path(@shop, @product)
    rescue OlxApiService::AuthenticationError => e
      Rails.logger.error "[Products Controller] ✗ Authentication error: #{e.message}"

      flash[:alert] = "<strong>Authentication Error:</strong><br>#{e.message}<br><br>Please check your OLX credentials in shop settings.".html_safe
      redirect_to shop_product_path(@shop, @product)
    rescue OlxApiService::ValidationError => e
      Rails.logger.error "[Products Controller] ✗ OLX validation error: #{e.message}"

      flash[:alert] = "<strong>OLX Validation Error:</strong><br>#{e.message}<br><br>Please check the product data and template configuration.".html_safe
      redirect_to shop_product_path(@shop, @product)
    rescue StandardError => e
      Rails.logger.error "[Products Controller] ✗ Unexpected error: #{e.message}"
      Rails.logger.error "[Products Controller] Backtrace: #{e.backtrace&.first(5)&.join("\n")}"

      flash[:alert] = "<strong>Error:</strong><br>#{e.message}".html_safe
      redirect_to shop_product_path(@shop, @product)
    end
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
      :source_id, :specs, :olx_category_template_id,
      :olx_title, :olx_description,
      images: []
    )
  end
end
