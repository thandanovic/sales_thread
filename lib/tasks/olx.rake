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
end
