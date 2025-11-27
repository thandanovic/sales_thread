class ShopsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_shop, only: [:show, :edit, :update, :destroy, :test_olx_connection, :sync_from_olx, :setup_olx_data]
  before_action :authorize_shop, only: [:edit, :update, :destroy, :test_olx_connection, :sync_from_olx, :setup_olx_data]

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

  def test_olx_connection
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
    Rails.logger.info "[Shops] Starting OLX sync for shop #{@shop.id}"

    begin
      # By default, only sync 'active' listings. To sync all statuses, pass status_filter: nil
      # To sync specific categories, pass category_ids: [18, 31, ...]
      # skip_existing: true means only import new products, don't update existing ones
      sync_options = {
        limit: params[:limit]&.to_i || 200,
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
    Rails.logger.info "[Shops] Starting OLX setup for shop #{@shop.id}"

    begin
      result = OlxSetupService.new(@shop).setup_all

      if result[:success]
        categories = result[:categories]
        attributes = result[:attributes]
        locations = result[:locations]

        if categories[:total] > 0
          message = "Successfully set up OLX data: "
          parts = []
          parts << "#{categories[:created]} categories created" if categories[:created] > 0
          parts << "#{categories[:updated]} categories updated" if categories[:updated] > 0
          parts << "#{attributes[:total]} attributes" if attributes && attributes[:total] > 0
          parts << "#{locations[:created]} cities created" if locations[:created] > 0
          parts << "#{locations[:updated]} cities updated" if locations[:updated] > 0

          if parts.any?
            message += parts.join(", ") + "."
          else
            cat_msg = "#{categories[:total]} categories"
            attr_msg = attributes && attributes[:total] > 0 ? ", #{attributes[:total]} attributes" : ""
            loc_msg = locations[:total] > 0 ? ", #{locations[:total]} cities" : ""
            message = "OLX data already up to date (#{cat_msg}#{attr_msg}#{loc_msg})."
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
    params.require(:shop).permit(:name, :olx_username, :olx_password)
  end
end
