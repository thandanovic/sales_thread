class OlxCategoryTemplatesController < ApplicationController
  before_action :authenticate_user!
  before_action :set_shop
  before_action :set_template, only: [:show, :edit, :update, :destroy]
  before_action :authorize_shop

  def index
    @templates = @shop.olx_category_templates.includes(:olx_category, :olx_location).order(created_at: :desc)
  end

  def load_attributes
    category = OlxCategory.find(params[:category_id])
    attributes = category.olx_category_attributes.map do |attr|
      {
        name: attr.name,
        external_id: attr.external_id,
        label: attr.display_label,
        type: attr.attribute_type,
        required: attr.required,
        values: attr.possible_values
      }
    end

    render json: { attributes: attributes }
  rescue ActiveRecord::RecordNotFound
    render json: { error: 'Category not found' }, status: :not_found
  end

  def load_specs
    # Get a sample product to extract available specs from
    product = if params[:product_url].present?
      # Option 1: Scrape from Intercars URL (requires credentials)
      scrape_product_specs(params[:product_url])
    elsif params[:product_id].present?
      # Option 2: Use existing product as sample
      @shop.products.find(params[:product_id])
    else
      # Option 3: Use any recent product with specs as sample
      @shop.products.where.not(specs: nil).order(created_at: :desc).first
    end

    if product && product.specs.present?
      specs_hash = JSON.parse(product.specs)
      spec_keys = specs_hash.keys

      render json: {
        specs: spec_keys,
        sample_product: {
          title: product.title,
          sku: product.sku
        }
      }
    else
      render json: { specs: [], message: 'No specs found. Import some products first.' }
    end
  rescue => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  def load_placeholders
    # Get a sample product to extract available placeholders from
    product = if params[:product_id].present?
      @shop.products.find(params[:product_id])
    else
      @shop.products.where.not(specs: nil).order(created_at: :desc).first
    end

    placeholders = {
      basic: [
        { name: 'brand', description: 'Product brand field', example: product&.brand || 'BOSCH' },
        { name: 'title', description: 'Full product title', example: product&.title&.truncate(40) || 'Product Title' },
        { name: 'sku', description: 'Product SKU/code', example: product&.sku || 'ABC123' },
        { name: 'category', description: 'Category name', example: product&.category || 'Auto Parts' },
        { name: 'price', description: 'Product price with currency', example: product ? "#{product.final_price} #{product.currency}" : '100.00 BAM' }
      ],
      specs: []
    }

    if product && product.specs.present?
      specs_hash = JSON.parse(product.specs)

      placeholders[:specs] = specs_hash.map do |key, value|
        # Convert spec key to placeholder format (snake_case, no special chars)
        placeholder_name = key.downcase
          .gsub(/[čć]/i, 'c')
          .gsub(/[žš]/i, 's')
          .gsub(/[đ]/i, 'd')
          .gsub(/\s+/, '_')
          .gsub(/[^\w]/, '')

        {
          name: placeholder_name,
          original_key: key,
          description: key,
          example: value.to_s.truncate(50)
        }
      end

      placeholders[:sample_product] = {
        title: product.title,
        sku: product.sku
      }
    end

    render json: placeholders
  rescue => e
    render json: { error: e.message, basic: [], specs: [] }, status: :unprocessable_entity
  end

  def show
    @products_count = @template.products.count

    respond_to do |format|
      format.html
      format.json { render json: @template.as_json(only: [:id, :name, :title_template, :description_filter]) }
    end
  end

  def new
    @template = @shop.olx_category_templates.new
    load_categories_and_locations
  end

  def create
    @template = @shop.olx_category_templates.new(template_params)

    if @template.save
      redirect_to shop_olx_category_templates_path(@shop), notice: 'Template was successfully created.'
    else
      load_categories_and_locations
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    load_categories_and_locations
  end

  def update
    if @template.update(template_params)
      redirect_to shop_olx_category_templates_path(@shop), notice: 'Template was successfully updated.'
    else
      load_categories_and_locations
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @template.destroy
    redirect_to shop_olx_category_templates_path(@shop), notice: 'Template was successfully deleted.'
  end

  private

  def set_shop
    @shop = current_user.shops.find(params[:shop_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to shops_path, alert: 'Shop not found or you do not have access.'
  end

  def set_template
    @template = @shop.olx_category_templates.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to shop_olx_category_templates_path(@shop), alert: 'Template not found.'
  end

  def authorize_shop
    membership = @shop.memberships.find_by(user: current_user)
    unless membership&.owner? || membership&.admin?
      redirect_to @shop, alert: 'You are not authorized to perform this action.'
    end
  end

  def template_params
    params.require(:olx_category_template).permit(
      :name,
      :title_template,
      :olx_category_id,
      :olx_location_id,
      :default_listing_type,
      :default_state,
      attribute_mappings: {},
      description_filter: []
    )
  end

  def load_categories_and_locations
    # Only show leaf categories (categories without children) for listing creation
    @categories = OlxCategory.leaf_categories.order(:name)
    @locations = OlxLocation.order(:name)
  end
end
