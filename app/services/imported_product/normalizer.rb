module ImportedProduct
  class Normalizer
    def initialize(imported_product)
      @imported_product = imported_product
      @shop = imported_product.shop
      @raw_data = JSON.parse(imported_product.raw_data)
    end

    def process
      @imported_product.update!(status: 'processing')

      product_attrs = normalize_attributes

      product = create_or_update_product(product_attrs)

      # Download images if URLs provided
      download_images(product)

      @imported_product.update!(
        status: 'imported',
        product: product
      )

      increment_success_count
      product
    rescue => e
      @imported_product.update!(
        status: 'error',
        error_text: e.message
      )
      increment_failed_count
      raise
    end

    private

    def normalize_attributes
      attrs = {
        shop: @shop,
        source: @imported_product.source,
        import_source: 'csv',
        title: @raw_data['title'],
        sku: @raw_data['sku'],
        brand: @raw_data['brand'],
        category: @raw_data['category'],
        price: parse_price(@raw_data['price']),
        currency: @raw_data['currency'] || 'BAM',
        stock: @raw_data['stock']&.to_i || 0,
        description: @raw_data['description'],
        specs: extract_specs.to_json
      }

      # Assign OLX category template if import log has one
      if @imported_product.import_log&.olx_category_template_id.present?
        attrs[:olx_category_template_id] = @imported_product.import_log.olx_category_template_id
      end

      attrs
    end

    def parse_price(price_string)
      return nil if price_string.blank?
      price_string.to_s.gsub(/[^\d.]/, '').to_f
    end

    def extract_specs
      @raw_data.except('title', 'sku', 'brand', 'category', 'price', 'currency', 'stock', 'description', 'image_urls')
    end

    def download_images(product)
      image_urls = @raw_data['image_urls'] || @raw_data['images']
      return if image_urls.blank?

      # Parse if comma-separated string
      urls = image_urls.is_a?(String) ? image_urls.split(',').map(&:strip) : Array(image_urls)

      urls.each_with_index do |url, index|
        next if url.blank?

        begin
          # Use open-uri to download the image
          require 'open-uri'
          io = URI.open(url)
          filename = "#{product.sku || product.id}_#{index}#{File.extname(url)}"

          product.images.attach(
            io: io,
            filename: filename,
            content_type: io.content_type
          )
        rescue => e
          Rails.logger.error "Failed to download image #{url}: #{e.message}"
          # Continue with other images
        end
      end
    rescue => e
      Rails.logger.error "Failed to process images: #{e.message}"
      # Don't fail the entire import if images fail
    end

    def create_or_update_product(attrs)
      product = @shop.products.find_or_initialize_by(
        source: attrs[:source],
        sku: attrs[:sku]
      )
      product.assign_attributes(attrs)
      product.save!
      product
    end

    def increment_success_count
      @imported_product.import_log&.increment!(:successful_rows)
      @imported_product.import_log&.increment!(:processed_rows)
    end

    def increment_failed_count
      @imported_product.import_log&.increment!(:failed_rows)
      @imported_product.import_log&.increment!(:processed_rows)
    end
  end
end
