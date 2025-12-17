# frozen_string_literal: true

namespace :olx do
  desc 'Sync OLX categories and attributes for a shop'
  task :sync_categories, [:shop_id] => :environment do |_t, args|
    if args[:shop_id].blank?
      puts 'Error: Please provide a shop ID'
      puts 'Usage: rake olx:sync_categories[SHOP_ID]'
      exit 1
    end

    shop = Shop.find_by(id: args[:shop_id])

    unless shop
      puts "Error: Shop with ID #{args[:shop_id]} not found"
      exit 1
    end

    unless shop.olx_access_token.present?
      puts "Error: Shop '#{shop.name}' does not have OLX credentials configured"
      puts 'Please configure OLX credentials in the shop settings first'
      exit 1
    end

    puts "Starting category sync for shop: #{shop.name}"
    puts '=' * 60

    begin
      result = OlxCategorySyncService.sync_all(shop)

      puts "\nSync completed successfully!"
      puts "Duration: #{result[:duration].round(2)} seconds"
      puts "Total categories: #{result[:total_count]}"
      puts "Synced: #{result[:synced_count]}"
      puts "Failed: #{result[:failed_count]}"

      if result[:errors].any?
        puts "\nErrors encountered:"
        result[:errors].each { |error| puts "  - #{error}" }
      end

      # Now sync attributes for all synced categories
      puts "\nSyncing attributes for categories..."
      total_attributes = 0

      OlxCategory.find_each do |category|
        count = OlxCategorySyncService.sync_category_attributes(shop, category)
        total_attributes += count
        print '.'
      end

      puts "\n\nTotal attributes synced: #{total_attributes}"
      puts '✓ Category and attribute sync completed!'
    rescue => e
      puts "\n✗ Sync failed: #{e.message}"
      puts e.backtrace.first(5).join("\n") if ENV['DEBUG']
      exit 1
    end
  end

  desc 'Sync OLX locations for a shop'
  task :sync_locations, [:shop_id] => :environment do |_t, args|
    if args[:shop_id].blank?
      puts 'Error: Please provide a shop ID'
      puts 'Usage: rake olx:sync_locations[SHOP_ID]'
      exit 1
    end

    shop = Shop.find_by(id: args[:shop_id])

    unless shop
      puts "Error: Shop with ID #{args[:shop_id]} not found"
      exit 1
    end

    unless shop.olx_access_token.present?
      puts "Error: Shop '#{shop.name}' does not have OLX credentials configured"
      puts 'Please configure OLX credentials in the shop settings first'
      exit 1
    end

    puts "Starting location sync for shop: #{shop.name}"
    puts '=' * 60

    begin
      result = OlxLocationSyncService.sync_all(shop)

      puts "\nSync completed successfully!"
      puts "Duration: #{result[:duration].round(2)} seconds"
      puts "Total locations: #{result[:total_count]}"
      puts "Synced: #{result[:synced_count]}"
      puts "Failed: #{result[:failed_count]}"

      if result[:errors].any?
        puts "\nErrors encountered:"
        result[:errors].each { |error| puts "  - #{error}" }
      end

      puts '✓ Location sync completed!'
    rescue => e
      puts "\n✗ Sync failed: #{e.message}"
      puts e.backtrace.first(5).join("\n") if ENV['DEBUG']
      exit 1
    end
  end

  desc 'Sync both OLX categories and locations for a shop'
  task :sync_all, [:shop_id] => :environment do |_t, args|
    if args[:shop_id].blank?
      puts 'Error: Please provide a shop ID'
      puts 'Usage: rake olx:sync_all[SHOP_ID]'
      exit 1
    end

    shop = Shop.find_by(id: args[:shop_id])

    unless shop
      puts "Error: Shop with ID #{args[:shop_id]} not found"
      exit 1
    end

    unless shop.olx_access_token.present?
      puts "Error: Shop '#{shop.name}' does not have OLX credentials configured"
      puts 'Please configure OLX credentials in the shop settings first'
      exit 1
    end

    puts "Starting full OLX data sync for shop: #{shop.name}"
    puts '=' * 60

    # Sync categories first
    puts "\n[1/2] Syncing categories..."
    Rake::Task['olx:sync_categories'].execute(shop_id: args[:shop_id])

    # Then sync locations
    puts "\n[2/2] Syncing locations..."
    Rake::Task['olx:sync_locations'].execute(shop_id: args[:shop_id])

    puts "\n" + '=' * 60
    puts '✓ Full OLX data sync completed!'
  end

  desc 'Cleanup removed OLX categories and locations for a shop'
  task :cleanup, [:shop_id] => :environment do |_t, args|
    if args[:shop_id].blank?
      puts 'Error: Please provide a shop ID'
      puts 'Usage: rake olx:cleanup[SHOP_ID]'
      exit 1
    end

    shop = Shop.find_by(id: args[:shop_id])

    unless shop
      puts "Error: Shop with ID #{args[:shop_id]} not found"
      exit 1
    end

    unless shop.olx_access_token.present?
      puts "Error: Shop '#{shop.name}' does not have OLX credentials configured"
      exit 1
    end

    puts "Cleaning up removed OLX data for shop: #{shop.name}"
    puts '=' * 60

    begin
      # Cleanup categories
      print 'Removing deleted categories... '
      deleted_categories = OlxCategorySyncService.cleanup_removed_categories(shop)
      puts "✓ (#{deleted_categories} removed)"

      # Cleanup locations
      print 'Removing deleted locations... '
      deleted_locations = OlxLocationSyncService.cleanup_removed_locations(shop)
      puts "✓ (#{deleted_locations} removed)"

      puts "\n✓ Cleanup completed!"
      puts "Categories removed: #{deleted_categories}"
      puts "Locations removed: #{deleted_locations}"
    rescue => e
      puts "\n✗ Cleanup failed: #{e.message}"
      puts e.backtrace.first(5).join("\n") if ENV['DEBUG']
      exit 1
    end
  end

  desc 'Show OLX sync statistics for a shop'
  task :stats, [:shop_id] => :environment do |_t, args|
    if args[:shop_id].blank?
      puts 'Error: Please provide a shop ID'
      puts 'Usage: rake olx:stats[SHOP_ID]'
      exit 1
    end

    shop = Shop.find_by(id: args[:shop_id])

    unless shop
      puts "Error: Shop with ID #{args[:shop_id]} not found"
      exit 1
    end

    puts "OLX Data Statistics for shop: #{shop.name}"
    puts '=' * 60

    # Authentication status
    if shop.olx_access_token.present?
      if shop.olx_token_expires_at && shop.olx_token_expires_at > Time.current
        puts "Authentication: ✓ Connected (expires #{shop.olx_token_expires_at.strftime('%Y-%m-%d')})"
      else
        puts 'Authentication: ✗ Token expired'
      end
    else
      puts 'Authentication: ✗ Not configured'
    end

    # Categories
    categories_count = OlxCategory.count
    root_categories_count = OlxCategory.root_categories.count
    categories_with_attributes = OlxCategory.joins(:olx_category_attributes).distinct.count

    puts "\nCategories:"
    puts "  Total: #{categories_count}"
    puts "  Root categories: #{root_categories_count}"
    puts "  Categories with attributes: #{categories_with_attributes}"

    # Attributes
    attributes_count = OlxCategoryAttribute.count
    required_attributes_count = OlxCategoryAttribute.required_attributes.count

    puts "\nCategory Attributes:"
    puts "  Total: #{attributes_count}"
    puts "  Required: #{required_attributes_count}"
    puts "  Optional: #{attributes_count - required_attributes_count}"

    # Locations
    locations_count = OlxLocation.count
    locations_with_coords = OlxLocation.with_coordinates.count

    puts "\nLocations:"
    puts "  Total: #{locations_count}"
    puts "  With coordinates: #{locations_with_coords}"

    # Templates
    templates_count = shop.olx_category_templates.count

    puts "\nTemplates:"
    puts "  Total: #{templates_count}"

    # Listings
    listings_count = shop.olx_listings.count
    published_listings = shop.olx_listings.where(status: 'published').count

    puts "\nListings:"
    puts "  Total: #{listings_count}"
    puts "  Published: #{published_listings}"

    puts "\n" + '=' * 60
  end

  desc 'List all shops with OLX integration'
  task list_shops: :environment do
    shops = Shop.where.not(olx_access_token: nil)

    if shops.empty?
      puts 'No shops with OLX integration found'
      exit 0
    end

    puts 'Shops with OLX Integration:'
    puts '=' * 60

    shops.each do |shop|
      token_status = if shop.olx_token_expires_at && shop.olx_token_expires_at > Time.current
                       "✓ Valid (expires #{shop.olx_token_expires_at.strftime('%Y-%m-%d')})"
                     else
                       '✗ Expired'
                     end

      puts "\nID: #{shop.id}"
      puts "Name: #{shop.name}"
      puts "Username: #{shop.olx_username}"
      puts "Token: #{token_status}"
      puts "Templates: #{shop.olx_category_templates.count}"
      puts "Listings: #{shop.olx_listings.count}"
    end

    puts "\n" + '=' * 60
    puts "Total shops: #{shops.count}"
  end

  desc 'Setup OLX data from CSV seed files (no API calls)'
  task :setup_from_csv, [:shop_id] => :environment do |_t, args|
    if args[:shop_id].blank?
      puts 'Error: Please provide a shop ID'
      puts 'Usage: rake olx:setup_from_csv[SHOP_ID]'
      exit 1
    end

    shop = Shop.find_by(id: args[:shop_id])

    unless shop
      puts "Error: Shop with ID #{args[:shop_id]} not found"
      exit 1
    end

    puts "Setting up OLX data from CSV for shop: #{shop.name}"
    puts '=' * 60

    service = OlxSetupService.new(shop)
    result = service.import_from_csv_only

    if result[:success]
      puts "\n✓ Setup completed successfully!"
    else
      puts "\n✗ Setup failed"
      exit 1
    end
  end

  desc 'Setup OLX data (from CSV + API for new categories)'
  task :setup, [:shop_id] => :environment do |_t, args|
    if args[:shop_id].blank?
      puts 'Error: Please provide a shop ID'
      puts 'Usage: rake olx:setup[SHOP_ID]'
      exit 1
    end

    shop = Shop.find_by(id: args[:shop_id])

    unless shop
      puts "Error: Shop with ID #{args[:shop_id]} not found"
      exit 1
    end

    unless shop.olx_access_token.present?
      puts "Error: Shop '#{shop.name}' does not have OLX credentials configured"
      puts 'Please configure OLX credentials in the shop settings first'
      puts 'Or use rake olx:setup_from_csv[SHOP_ID] to setup from CSV only'
      exit 1
    end

    puts "Setting up OLX data for shop: #{shop.name}"
    puts '=' * 60

    service = OlxSetupService.new(shop)
    result = service.setup_all

    if result[:success]
      puts "\n✓ Setup completed successfully!"
    else
      puts "\n✗ Setup failed: #{result[:error]}"
      exit 1
    end
  end

  desc 'Export OLX categories and attributes to CSV seed files'
  task export_to_csv: :environment do
    require 'csv'

    puts 'Exporting OLX data to CSV seed files...'
    puts '=' * 60

    seeds_dir = Rails.root.join('db', 'seeds')
    FileUtils.mkdir_p(seeds_dir)

    # Export categories
    categories_path = seeds_dir.join('olx_categories.csv')
    puts "\nExporting categories to #{categories_path}..."

    # Build lookup of external_ids by database id for parent resolution
    id_to_external = OlxCategory.pluck(:id, :external_id).to_h

    CSV.open(categories_path, 'w') do |csv|
      csv << %w[external_id name slug parent_external_id has_shipping has_brand metadata]

      OlxCategory.order(:external_id).find_each do |cat|
        parent_external_id = cat.parent_id ? id_to_external[cat.parent_id] : nil
        csv << [
          cat.external_id,
          cat.name,
          cat.slug,
          parent_external_id,
          cat.has_shipping ? '1' : '0',
          cat.has_brand ? '1' : '0',
          cat.metadata
        ]
      end
    end
    puts "  ✓ Exported #{OlxCategory.count} categories"

    # Export category attributes
    attributes_path = seeds_dir.join('olx_category_attributes.csv')
    puts "\nExporting category attributes to #{attributes_path}..."

    CSV.open(attributes_path, 'w') do |csv|
      csv << %w[external_id category_external_id name attribute_type input_type required options]

      OlxCategoryAttribute.includes(:olx_category).find_each do |attr|
        csv << [
          attr.external_id,
          attr.olx_category.external_id,
          attr.name,
          attr.attribute_type,
          attr.input_type,
          attr.required ? '1' : '0',
          attr.options
        ]
      end
    end
    puts "  ✓ Exported #{OlxCategoryAttribute.count} attributes"

    # Export category templates (shop-specific, use first shop)
    shop = Shop.first
    if shop
      templates_path = seeds_dir.join('olx_category_templates.csv')
      puts "\nExporting category templates to #{templates_path}..."

      CSV.open(templates_path, 'w') do |csv|
        csv << %w[name category_external_id location_external_id default_listing_type default_state attribute_mappings description_filter title_template description_template]

        shop.olx_category_templates.includes(:olx_category, :olx_location).find_each do |template|
          csv << [
            template.name,
            template.olx_category&.external_id,
            template.olx_location&.external_id,
            template.default_listing_type,
            template.default_state,
            template.attribute_mappings&.to_json,
            template.description_filter&.to_json,
            template.title_template,
            template.description_template
          ]
        end
      end
      puts "  ✓ Exported #{shop.olx_category_templates.count} templates"
    end

    puts "\n" + '=' * 60
    puts '✓ Export completed!'
    puts "\nFiles created:"
    puts "  - #{categories_path}"
    puts "  - #{attributes_path}"
    puts "  - #{seeds_dir.join('olx_category_templates.csv')}" if shop
  end

  desc 'Repair OLX category parent relationships (fixes incorrect parent_id references)'
  task :repair_category_parents, [:shop_id] => :environment do |_t, args|
    if args[:shop_id].blank?
      puts 'Error: Please provide a shop ID'
      puts 'Usage: rake olx:repair_category_parents[SHOP_ID]'
      exit 1
    end

    shop = Shop.find_by(id: args[:shop_id])

    unless shop
      puts "Error: Shop with ID #{args[:shop_id]} not found"
      exit 1
    end

    unless shop.olx_access_token.present?
      puts "Error: Shop '#{shop.name}' does not have OLX credentials configured"
      exit 1
    end

    puts "Repairing category parent relationships for shop: #{shop.name}"
    puts '=' * 60

    begin
      # Fetch all categories recursively from OLX API
      response = OlxApiService.get('/categories', shop)
      root_categories = response['data'] || response['categories'] || []

      puts "Fetching all categories recursively (this may take a while)..."
      categories_data = OlxCategorySyncService.fetch_all_categories_recursively(shop, root_categories)

      puts "Found #{categories_data.size} total categories from OLX API"

      fixed_count = 0
      categories_data.each do |category_data|
        external_id = category_data['id'].to_i
        external_parent_id = category_data['parent_id'].present? ? category_data['parent_id'].to_i : nil

        category = OlxCategory.find_by(external_id: external_id)
        next unless category

        # Find the correct parent by external_id
        parent = external_parent_id.present? ? OlxCategory.find_by(external_id: external_parent_id) : nil
        correct_parent_id = parent&.id

        if category.parent_id != correct_parent_id
          old_parent = category.parent
          category.update_column(:parent_id, correct_parent_id)
          puts "Fixed: #{category.name}"
          puts "  Old parent: #{old_parent&.name || 'nil'}"
          puts "  New parent: #{parent&.name || 'nil'}"
          fixed_count += 1
        end
      end

      puts "\n" + '=' * 60
      puts "✓ Repair completed! Fixed #{fixed_count} categories."
    rescue => e
      puts "\n✗ Repair failed: #{e.message}"
      puts e.backtrace.first(5).join("\n") if ENV['DEBUG']
      exit 1
    end
  end
end
