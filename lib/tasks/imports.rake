namespace :imports do
  desc "Backfill ImportedProduct records for existing imports"
  task backfill_imported_products: :environment do
    puts "Starting backfill of ImportedProduct records..."

    ImportLog.where.not(successful_rows: 0).find_each do |import_log|
      next if import_log.imported_products.any? # Skip if already has records

      puts "\nProcessing Import ##{import_log.id}:"
      puts "  Source: #{import_log.source}"
      puts "  Successful: #{import_log.successful_rows}"
      puts "  Time range: #{import_log.started_at} - #{import_log.completed_at}"

      if import_log.started_at.blank? || import_log.completed_at.blank?
        puts "  ⚠️  Skipping - no time range"
        next
      end

      # Find products created during this import's timeframe
      products = Product.where(
        shop: import_log.shop,
        source: import_log.source
      ).where(
        "created_at >= ? AND created_at <= ?",
        import_log.started_at - 1.minute, # Small buffer
        import_log.completed_at + 1.minute
      )

      created_count = 0
      products.each do |product|
        ImportedProduct.create!(
          shop: import_log.shop,
          import_log: import_log,
          product: product,
          source: import_log.source,
          raw_data: {
            title: product.title,
            sku: product.sku,
            price: product.price,
            backfilled: true
          }.to_json,
          status: 'imported',
          created_at: product.created_at,
          updated_at: product.updated_at
        )
        created_count += 1
      end

      puts "  ✓ Created #{created_count} ImportedProduct records"
    end

    puts "\n✓ Backfill complete!"
  end
end
