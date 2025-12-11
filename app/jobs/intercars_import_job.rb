# frozen_string_literal: true

##
# Background job for importing products from Intercars
# Runs the scraper and updates import progress in real-time
#
class IntercarsImportJob < ApplicationJob
  queue_as :default

  def perform(import_log_id, username, password, product_url, max_products)
    import_log = ImportLog.find(import_log_id)
    shop = import_log.shop

    import_log.update!(
      status: 'processing',
      started_at: Time.current,
      total_rows: max_products,
      processed_rows: 0,
      successful_rows: 0,
      failed_rows: 0,
      current_phase: 'starting',
      scraped_count: 0
    )

    begin
      result = ScraperService.scrape_and_import(
        shop,
        username: username,
        password: password,
        product_url: product_url,
        max_products: max_products,
        import_log: import_log
      )

      if result[:success]
        final_status = result[:failed] > 0 ? 'completed_with_errors' : 'completed'
        errors = result[:errors] || []

        import_log.update!(
          status: final_status,
          completed_at: Time.current,
          total_rows: result[:total],
          successful_rows: result[:imported],
          failed_rows: result[:failed],
          error_messages: errors.any? ? errors.to_json : nil,
          current_phase: 'completed'
        )
      else
        import_log.update!(
          status: 'failed',
          completed_at: Time.current,
          error_messages: [result[:error], result[:output]].compact.to_json,
          current_phase: 'failed'
        )
      end
    rescue StandardError => e
      Rails.logger.error "IntercarsImportJob error: #{e.message}\n#{e.backtrace.join("\n")}"

      import_log.update!(
        status: 'failed',
        completed_at: Time.current,
        error_messages: [e.message, e.backtrace.first(5)].flatten.to_json,
        current_phase: 'failed'
      )
    end
  end
end
