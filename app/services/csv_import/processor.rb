require 'csv'

module CsvImport
  class Processor
    def initialize(import_log, column_mappings, file_path)
      @import_log = import_log
      @shop = import_log.shop
      @column_mappings = column_mappings
      @file_path = file_path
    end

    def process_file
      @import_log.update!(status: 'processing', started_at: Time.current)

      total_rows = 0
      CSV.foreach(@file_path, headers: true, encoding: 'UTF-8') do |row|
        raw_data = map_row(row)
        @shop.imported_products.create!(
          import_log: @import_log,
          source: 'csv',
          raw_data: raw_data.to_json,
          status: 'pending'
        )
        total_rows += 1
      end

      @import_log.update!(total_rows: total_rows)

      # Process each imported product
      process_imported_products
    rescue CSV::MalformedCSVError => e
      @import_log.update!(
        status: 'failed',
        completed_at: Time.current
      )
      raise "CSV parsing error: #{e.message}"
    rescue => e
      @import_log.update!(
        status: 'failed',
        completed_at: Time.current
      )
      raise e
    end

    private

    def map_row(csv_row)
      mapped = {}
      @column_mappings.each do |csv_column, product_field|
        mapped[product_field] = csv_row[csv_column]
      end
      mapped
    end

    def process_imported_products
      @import_log.imported_products.where(status: 'pending').find_each do |imported_product|
        normalizer = ImportedProduct::Normalizer.new(imported_product)
        begin
          normalizer.process
        rescue => e
          Rails.logger.error "Error processing imported product #{imported_product.id}: #{e.message}"
          # Continue processing other products
        end
      end

      # Update import log status
      @import_log.reload
      if @import_log.failed_rows > 0 && @import_log.successful_rows == 0
        @import_log.update!(status: 'failed', completed_at: Time.current)
      else
        @import_log.update!(status: 'completed', completed_at: Time.current)
      end
    end
  end
end
