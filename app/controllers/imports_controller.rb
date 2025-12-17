class ImportsController < ApplicationController
  before_action :authenticate_user!
  before_action :set_shop
  before_action :set_import, only: [:show, :start_processing, :retry_import, :preview, :progress]

  def index
    authorize @shop, :show?  # All members can view imports
    @imports = @shop.import_logs.order(created_at: :desc).page(params[:page])
  end

  def new
    authorize @shop, :update?  # Only managers can create imports
    @import = @shop.import_logs.new

    # Load saved Intercars credentials if they exist
    @intercars_credentials = @shop.integration_credentials('intercars')
  end

  def create
    authorize @shop, :update?  # Only managers can create imports
    @import = @shop.import_logs.new
    @import.source = params[:import_log]&.[](:source) || params[:source]
    @import.status = 'pending'
    @import.olx_category_template_id = params[:olx_category_template_id] if params[:olx_category_template_id].present?

    # Require OLX category template for all imports
    if params[:olx_category_template_id].blank?
      @import.errors.add(:base, 'OLX Category Template is required')
      @intercars_credentials = @shop.integration_credentials('intercars')
      render :new, status: :unprocessable_entity
      return
    end

    if @import.source == 'csv' && params[:csv_file].present?
      # Handle CSV upload
      handle_csv_upload(params[:csv_file])
    elsif @import.source == 'intercars'
      username = params[:username]
      password = params[:password]

      # If password is blank, try to use saved credentials
      if password.blank?
        saved_credentials = @shop.integration_credentials('intercars')
        if saved_credentials.present? && saved_credentials['username'] == username
          password = saved_credentials['password']
        else
          @import.errors.add(:base, 'Password is required (no saved credentials found for this username)')
          @intercars_credentials = @shop.integration_credentials('intercars')
          render :new, status: :unprocessable_entity
          return
        end
      end

      # Save scraper metadata
      metadata = {
        username: username,
        product_url: params[:product_url],
        max_products: params[:max_products]&.to_i || 50,
        save_credentials: params[:save_credentials] == '1'
      }

      @import.metadata = metadata.to_json

      if @import.save
        # Save/update credentials if requested
        if metadata[:save_credentials] && params[:password].present?
          @shop.set_integration_credentials('intercars', username, password)
          @shop.save!
        end

        # Start scraping based on run_mode
        run_mode = params[:run_mode] || 'background'
        process_scraper_import_with_params(username, password, metadata[:product_url], metadata[:max_products], run_mode: run_mode)
      else
        render :new, status: :unprocessable_entity
      end
    else
      @import.errors.add(:base, 'Please select a source and provide required data.')
      render :new, status: :unprocessable_entity
    end
  end

  def show
    authorize @shop, :show?  # All members can view imports
    @imported_products = @import.imported_products.order(created_at: :desc).page(params[:page])
  end

  def preview
    authorize @shop, :show?  # All members can view imports
    # Show preview of imported products before final processing
    @imported_products = @import.imported_products.where(status: 'pending').limit(50)
  end

  def start_processing
    authorize @shop, :update?  # Only managers can process imports
    if @import.status == 'pending'
      case @import.source
      when 'csv'
        process_csv_import
      when 'intercars'
        process_scraper_import
      end
    else
      redirect_to shop_import_path(@shop, @import), alert: 'Import is already being processed or completed.'
    end
  end

  def retry_import
    authorize @shop, :update?  # Only managers can retry imports
    # Only allow retry for completed or failed imports
    unless %w[completed completed_with_errors failed].include?(@import.status)
      redirect_to shop_import_path(@shop, @import), alert: 'Cannot retry an import that is still processing.'
      return
    end

    # Only support Intercars imports for now
    unless @import.source == 'intercars'
      redirect_to shop_import_path(@shop, @import), alert: 'Retry is only supported for Intercars imports.'
      return
    end

    metadata = JSON.parse(@import.metadata || '{}')
    username = metadata['username']
    product_url = metadata['product_url']
    max_products = metadata['max_products'] || 50

    # Get saved credentials
    credentials = @shop.integration_credentials('intercars')
    if credentials.nil? || credentials['username'] != username
      redirect_to shop_import_path(@shop, @import),
                  alert: 'Credentials not found. Please create a new import with your credentials.'
      return
    end

    password = credentials['password']

    # Reset import stats
    @import.update(
      status: 'pending',
      started_at: nil,
      completed_at: nil,
      total_rows: 0,
      successful_rows: 0,
      failed_rows: 0,
      processed_rows: 0,
      error_messages: nil
    )

    # Clear previous imported products
    @import.imported_products.destroy_all

    # Process the import again in background
    IntercarsImportJob.perform_later(
      @import.id,
      username,
      password,
      product_url,
      max_products
    )

    redirect_to shop_import_path(@shop, @import), notice: 'Re-import started. This page will auto-refresh to show progress.'
  end

  def progress
    authorize @shop, :show?  # All members can view progress
    render json: {
      status: @import.status,
      current_phase: @import.current_phase || 'unknown',
      scraped_count: @import.scraped_count || 0,
      total_rows: @import.total_rows || 0,
      processed_rows: @import.processed_rows || 0,
      successful_rows: @import.successful_rows || 0,
      failed_rows: @import.failed_rows || 0,
      started_at: @import.started_at&.iso8601,
      completed_at: @import.completed_at&.iso8601
    }
  end

  private

  def set_shop
    @shop = find_shop_with_admin_access(params[:shop_id])
  rescue ActiveRecord::RecordNotFound
    redirect_to shops_path, alert: 'Shop not found or you do not have access.'
  end

  def set_import
    @import = @shop.import_logs.find(params[:id])
  rescue ActiveRecord::RecordNotFound
    redirect_to shop_imports_path(@shop), alert: 'Import not found.'
  end

  def import_params
    params.require(:import_log).permit(:source, :metadata)
  end

  def handle_csv_upload(file)
    # Save file temporarily
    file_path = Rails.root.join('tmp', "import_#{SecureRandom.hex(8)}.csv")
    File.open(file_path, 'wb') { |f| f.write(file.read) }

    # Parse and preview
    parser = CsvImport::Parser.new(file_path, @shop)

    begin
      preview = parser.preview
      headers = parser.get_headers
      detected = parser.detect_mappings(headers)

      if @import.save
        # Store metadata
        @import.update!(metadata: {
          filename: file.original_filename,
          file_path: file_path.to_s,
          headers: headers,
          detected_mappings: detected[:mappings],
          confidence: detected[:confidence]
        }.to_json)

        redirect_to preview_shop_import_path(@shop, @import),
                    notice: "CSV uploaded successfully. #{detected[:mappings].size} columns auto-mapped. Review before processing."
      else
        render :new, status: :unprocessable_entity
      end
    rescue => e
      @import.errors.add(:base, "CSV parsing error: #{e.message}")
      render :new, status: :unprocessable_entity
    end
  end

  def process_csv_import
    begin
      metadata = JSON.parse(@import.metadata)
      file_path = metadata['file_path']
      column_mappings = metadata['detected_mappings']

      unless File.exist?(file_path)
        @import.update(
          status: 'failed',
          completed_at: Time.current,
          error_messages: ['CSV file not found. Please re-upload.'].to_json
        )
        redirect_to shop_import_path(@shop, @import), alert: 'CSV file not found. Please re-upload.'
        return
      end

      # Process the CSV file
      processor = CsvImport::Processor.new(@import, column_mappings, file_path)
      processor.process_file

      # Clean up temp file
      File.delete(file_path) if File.exist?(file_path)

      # Check for errors after processing
      @import.reload
      if @import.failed_rows > 0
        error_products = @import.imported_products.where(status: 'error')
        errors = error_products.map { |p| "#{p.raw_data}: #{p.error_text}" }

        @import.update(error_messages: errors.to_json) if errors.any?

        redirect_to shop_import_path(@shop, @import),
                    notice: "CSV import completed with #{@import.failed_rows} errors. Imported #{@import.successful_rows}/#{@import.total_rows} products."
      else
        redirect_to shop_import_path(@shop, @import),
                    notice: "CSV import completed successfully! Imported #{@import.successful_rows} products."
      end
    rescue => e
      Rails.logger.error "CSV import error: #{e.message}\n#{e.backtrace.join("\n")}"

      @import.update(
        status: 'failed',
        completed_at: Time.current,
        error_messages: [e.message, e.backtrace.first(5)].flatten.to_json
      )

      redirect_to shop_import_path(@shop, @import), alert: "Import failed: #{e.message}"
    end
  end

  def process_scraper_import
    metadata = JSON.parse(@import.metadata || '{}')
    username = metadata['username']
    password = nil # Get from saved credentials
    product_url = metadata['product_url']
    max_products = metadata['max_products'] || 50

    # Try to get saved credentials
    credentials = @shop.integration_credentials('intercars')
    if credentials && credentials['username'] == username
      password = credentials['password']
    end

    if password.blank?
      @import.update(status: 'failed', completed_at: Time.current)
      redirect_to shop_import_path(@shop, @import),
                  alert: 'Credentials not found. Please provide them again.'
      return
    end

    process_scraper_import_with_params(username, password, product_url, max_products)
  end

  def process_scraper_import_with_params(username, password, product_url, max_products, run_mode: 'background')
    # Set initial state
    @import.update!(
      status: 'processing',
      started_at: Time.current,
      total_rows: max_products,
      processed_rows: 0,
      successful_rows: 0,
      failed_rows: 0,
      current_phase: 'starting',
      scraped_count: 0
    )

    if run_mode == 'direct'
      # Run synchronously - the page will wait
      process_scraper_import_direct(username, password, product_url, max_products)
    else
      # Enqueue background job
      IntercarsImportJob.perform_later(
        @import.id,
        username,
        password,
        product_url,
        max_products
      )

      redirect_to shop_import_path(@shop, @import), notice: 'Import started in background. This page will auto-refresh to show progress.'
    end
  end

  def process_scraper_import_direct(username, password, product_url, max_products)
    begin
      # Call the scraper service directly (synchronous)
      result = ScraperService.scrape_and_import(
        @shop,
        username: username,
        password: password,
        product_url: product_url,
        max_products: max_products,
        import_log: @import
      )

      if result[:success]
        # Determine final status based on failures
        final_status = result[:failed] > 0 ? 'completed_with_errors' : 'completed'

        # Save errors if any
        errors = result[:errors] || []
        error_messages = errors.any? ? errors.to_json : nil

        @import.update!(
          status: final_status,
          completed_at: Time.current,
          total_rows: result[:total],
          successful_rows: result[:imported],
          failed_rows: result[:failed],
          error_messages: error_messages,
          current_phase: 'completed'
        )

        if errors.any?
          redirect_to shop_import_path(@shop, @import),
                      alert: "Scraping completed with #{result[:failed]} errors. Imported #{result[:imported]}/#{result[:total]} products."
        else
          redirect_to shop_import_path(@shop, @import),
                      notice: "Scraping completed successfully! Imported #{result[:imported]} products."
        end
      else
        error_msg = result[:error] || 'Unknown error occurred'

        @import.update!(
          status: 'failed',
          completed_at: Time.current,
          error_messages: [error_msg].to_json,
          current_phase: 'failed'
        )

        redirect_to shop_import_path(@shop, @import), alert: "Scraping failed: #{error_msg}"
      end
    rescue => e
      Rails.logger.error "Scraper import error: #{e.message}\n#{e.backtrace.join("\n")}"

      @import.update!(
        status: 'failed',
        completed_at: Time.current,
        error_messages: [e.message].to_json,
        current_phase: 'failed'
      )

      redirect_to shop_import_path(@shop, @import), alert: "Import failed: #{e.message}"
    end
  end

  # Keep old synchronous method for reference but not used
  def process_scraper_import_sync(username, password, product_url, max_products)
    @import.update(status: 'processing', started_at: Time.current)

    begin
      # Call the scraper service with the provided URL
      result = ScraperService.scrape_and_import(
        @shop,
        username: username,
        password: password,
        product_url: product_url,
        max_products: max_products,
        import_log: @import
      )

      if result[:success]
        # Determine final status based on failures
        final_status = result[:failed] > 0 ? 'completed_with_errors' : 'completed'

        # Save errors if any
        errors = result[:errors] || []
        error_messages = errors.any? ? errors.to_json : nil

        @import.update(
          status: final_status,
          completed_at: Time.current,
          total_rows: result[:total],
          successful_rows: result[:imported],
          failed_rows: result[:failed],
          error_messages: error_messages
        )

        if errors.any?
          # Build detailed error summary
          error_summary = "Scraping completed with #{result[:failed]} errors. Successfully imported #{result[:imported]} out of #{result[:total]} products."
          if errors.length <= 5
            error_detail = "<br><br><strong>Error details:</strong><br>#{errors.map { |e| "• #{e}" }.join('<br>')}"
            flash[:alert] = (error_summary + error_detail).html_safe
          else
            error_detail = "<br><br><strong>First 5 errors:</strong><br>#{errors.first(5).map { |e| "• #{e}" }.join('<br>')}<br>... and #{errors.length - 5} more errors. See import details page for full list."
            flash[:alert] = (error_summary + error_detail).html_safe
          end
          redirect_to shop_import_path(@shop, @import)
        else
          redirect_to shop_import_path(@shop, @import),
                      notice: "Scraping completed successfully! Imported #{result[:imported]} products."
        end
      else
        error_msg = result[:error] || 'Unknown error occurred'
        error_output = result[:output] || ''

        # Build detailed error message
        detailed_error = "Scraping failed: #{error_msg}"
        if error_output.present?
          # Extract last 10 lines of output for context
          output_lines = error_output.split("\n").last(10)
          detailed_error += "<br><br><strong>Last output:</strong><br><pre>#{output_lines.join("\n")}</pre>"
        end

        @import.update(
          status: 'failed',
          completed_at: Time.current,
          error_messages: [error_msg, error_output].compact.to_json
        )

        flash[:alert] = detailed_error.html_safe
        redirect_to shop_import_path(@shop, @import)
      end
    rescue => e
      Rails.logger.error "Scraper import error: #{e.message}\n#{e.backtrace.join("\n")}"

      # Build detailed error message with context
      error_details = "Import Error: #{e.message}"
      error_details += "<br><br><strong>Error Type:</strong> #{e.class.name}"

      # Add first 3 stack trace lines for debugging
      if e.backtrace.any?
        error_details += "<br><br><strong>Stack trace:</strong><br><pre>#{e.backtrace.first(3).join("\n")}</pre>"
      end

      @import.update(
        status: 'failed',
        completed_at: Time.current,
        error_messages: [e.message, e.backtrace.first(5)].flatten.to_json
      )

      flash[:alert] = error_details.html_safe
      redirect_to shop_import_path(@shop, @import)
    end
  end
end
