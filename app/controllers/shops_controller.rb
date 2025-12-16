class ShopsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_shop, only: [:show, :edit, :update, :destroy, :test_olx_connection, :sync_from_olx, :setup_olx_data]

  def index
    # Auto-redirect for single-shop users
    if current_user.single_shop_access?
      redirect_to current_user.single_shop
      return
    end

    @shops = policy_scope(Shop).order(created_at: :desc)
  end

  def show
    authorize @shop
    @products = @shop.products.order(created_at: :desc).limit(10)
    @recent_imports = @shop.import_logs.order(created_at: :desc).limit(5)
  end

  def new
    @shop = Shop.new
    authorize @shop
  end

  def create
    @shop = Shop.new(shop_params)
    authorize @shop

    if @shop.save
      # Create membership with manager role (creator becomes manager)
      @shop.memberships.create!(user: current_user, role: 'manager')

      redirect_to @shop, notice: 'Shop was successfully created.'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit
    authorize @shop
  end

  def update
    authorize @shop
    if @shop.update(shop_params)
      redirect_to @shop, notice: 'Shop was successfully updated.'
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    authorize @shop
    @shop.destroy
    redirect_to shops_url, notice: 'Shop was successfully deleted.'
  end

  def test_olx_connection
    authorize @shop
    begin
      result = OlxApiService.authenticate(@shop)

      if result[:success]
        render json: {
          success: true,
          message: 'Successfully connected to OLX! Token saved.',
          user: result[:user]
        }
      else
        render json: {
          success: false,
          message: 'Connection failed. Please check your credentials.'
        }, status: :unprocessable_entity
      end
    rescue OlxApiService::AuthenticationError => e
      render json: {
        success: false,
        message: "Authentication failed: #{e.message}"
      }, status: :unprocessable_entity
    rescue => e
      render json: {
        success: false,
        message: "Error: #{e.message}"
      }, status: :unprocessable_entity
    end
  end

  def sync_from_olx
    authorize @shop
    Rails.logger.info "[Shops] Starting OLX sync for shop #{@shop.id}"

    begin
      # By default, only sync 'active' listings. To sync all statuses, pass status_filter: nil
      # To sync specific categories, pass category_ids: [18, 31, ...]
      # skip_existing: true means only import new products, don't update existing ones
      sync_options = {
        limit: params[:limit]&.to_i || 500,
        status_filter: params[:status_filter]&.split(',') || ['active'],
        skip_existing: params[:skip_existing] != 'false' # Default to true, unless explicitly set to 'false'
      }

      result = OlxSyncService.new(@shop).sync_products(**sync_options)

      if result[:success]
        total_successful = result[:imported] + result[:updated]
        total_unsuccessful = result[:skipped] + result[:failed]

        if total_successful > 0
          # Some products were successfully synced
          message_parts = ["Successfully synced from OLX:"]
          message_parts << "#{result[:imported]} new" if result[:imported] > 0
          message_parts << "#{result[:updated]} updated" if result[:updated] > 0

          if total_unsuccessful > 0
            unsuccessful_parts = []
            unsuccessful_parts << "#{result[:skipped]} skipped" if result[:skipped] > 0
            unsuccessful_parts << "#{result[:failed]} failed" if result[:failed] > 0
            message_parts << "(#{unsuccessful_parts.join(', ')})"
          end

          flash[:notice] = message_parts.join(", ") + "."
        elsif result[:skipped] > 0 && result[:failed] == 0
          # Everything was skipped (missing categories/locations)
          flash[:alert] = "Could not sync #{result[:skipped]} product(s): Categories or locations missing from database. Please fetch OLX categories and locations first."
        elsif result[:failed] > 0
          # Everything failed with errors
          flash[:alert] = "Sync completed with errors: #{result[:failed]} failed, #{result[:skipped]} skipped. Check logs for details."
        else
          flash[:notice] = "No products to sync."
        end

        Rails.logger.info "[Shops] OLX sync completed: #{result.inspect}"
      else
        flash[:alert] = "Sync failed: #{result[:error]}"
        Rails.logger.error "[Shops] OLX sync failed: #{result[:error]}"
      end
    rescue OlxApiService::AuthenticationError => e
      flash[:alert] = "Authentication error: #{e.message}. Please check your OLX credentials."
      Rails.logger.error "[Shops] OLX sync authentication error: #{e.message}"
    rescue => e
      flash[:alert] = "Sync error: #{e.message}"
      Rails.logger.error "[Shops] OLX sync error: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
    end

    redirect_to @shop
  end

  def setup_olx_data
    authorize @shop
    Rails.logger.info "[Shops] Starting OLX setup for shop #{@shop.id}"

    begin
      result = OlxSetupService.new(@shop).setup_all

      if result[:success]
        categories = result[:categories] || {}
        attributes = result[:attributes] || {}
        locations = result[:locations] || {}
        templates = result[:templates] || {}

        total_categories = categories[:total] || 0
        total_attributes = attributes[:total] || 0
        total_locations = locations[:total] || 0
        total_templates = templates[:total] || 0

        # Extract created/updated counts - handle both old and new result structure
        cat_csv = categories[:csv] || {}
        cat_api = categories[:api] || {}
        cat_created = (cat_csv[:created] || 0) + (cat_api[:created] || 0)
        cat_updated = (cat_csv[:updated] || 0) + (cat_api[:updated] || 0)

        attr_csv = attributes[:csv] || {}
        attr_created = attr_csv[:created] || 0
        attr_updated = attr_csv[:updated] || 0

        loc_created = locations[:created] || 0
        loc_updated = locations[:updated] || 0

        tpl_created = templates[:created] || 0
        tpl_updated = templates[:updated] || 0

        if total_categories > 0
          message = "Successfully set up OLX data: "
          parts = []
          parts << "#{cat_created} categories created" if cat_created > 0
          parts << "#{cat_updated} categories updated" if cat_updated > 0
          parts << "#{total_attributes} attributes" if total_attributes > 0
          parts << "#{loc_created} cities created" if loc_created > 0
          parts << "#{loc_updated} cities updated" if loc_updated > 0
          parts << "#{tpl_created} templates created" if tpl_created > 0
          parts << "#{tpl_updated} templates updated" if tpl_updated > 0

          if parts.any?
            message += parts.join(", ") + "."
          else
            message = "OLX data already up to date (#{total_categories} categories, #{total_attributes} attributes, #{total_templates} templates)."
          end

          flash[:notice] = message
        else
          flash[:alert] = "No categories found. Please check OLX API configuration."
        end

        Rails.logger.info "[Shops] OLX setup completed: #{result.inspect}"
      else
        flash[:alert] = "Setup failed: #{result[:error]}"
        Rails.logger.error "[Shops] OLX setup failed: #{result[:error]}"
      end
    rescue OlxApiService::AuthenticationError => e
      flash[:alert] = "Authentication error: #{e.message}. Please check your OLX credentials."
      Rails.logger.error "[Shops] OLX setup authentication error: #{e.message}"
    rescue => e
      flash[:alert] = "Setup error: #{e.message}"
      Rails.logger.error "[Shops] OLX setup error: #{e.class} - #{e.message}"
      Rails.logger.error e.backtrace.first(5).join("\n")
    end

    redirect_to @shop
  end

  private

  def set_shop
    @shop = find_shop_with_admin_access(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to shops_path, alert: 'Shop not found or you do not have access.'
  end

  def shop_params
    params.require(:shop).permit(:name, :logo, :olx_username, :olx_password)
  end
end
