# frozen_string_literal: true

##
# OlxCategorySyncService
#
# Service for syncing OLX categories and their attributes from the OLX API
# to the local database.
#
# Usage:
#   # Sync all categories
#   OlxCategorySyncService.sync_all(shop)
#
#   # Sync a specific category
#   OlxCategorySyncService.sync_category(shop, category_id)
#
class OlxCategorySyncService
  class SyncError < StandardError; end

  ##
  # Sync all categories from OLX API
  #
  # @param shop [Shop] Shop with OLX authentication
  # @return [Hash] Summary of sync operation
  #
  def self.sync_all(shop)
    Rails.logger.info "[OLX Category Sync] Starting full category sync for shop #{shop.id}"

    start_time = Time.current
    synced_count = 0
    failed_count = 0
    errors = []

    begin
      # Fetch all categories from OLX API
      response = OlxApiService.get('/categories', shop)
      categories_data = response['data'] || response['categories'] || []

      Rails.logger.info "[OLX Category Sync] Found #{categories_data.size} categories to sync"

      categories_data.each do |category_data|
        begin
          sync_category_data(category_data)
          synced_count += 1
        rescue => e
          failed_count += 1
          error_message = "Category #{category_data['id']}: #{e.message}"
          errors << error_message
          Rails.logger.error "[OLX Category Sync] #{error_message}"
        end
      end

      duration = Time.current - start_time
      Rails.logger.info "[OLX Category Sync] Completed in #{duration.round(2)}s. Synced: #{synced_count}, Failed: #{failed_count}"

      {
        success: true,
        synced_count: synced_count,
        failed_count: failed_count,
        total_count: categories_data.size,
        duration: duration,
        errors: errors
      }
    rescue OlxApiService::AuthenticationError => e
      Rails.logger.error "[OLX Category Sync] Authentication error: #{e.message}"
      raise SyncError, "Authentication failed: #{e.message}"
    rescue => e
      Rails.logger.error "[OLX Category Sync] Sync failed: #{e.message}"
      raise SyncError, "Sync failed: #{e.message}"
    end
  end

  ##
  # Sync a specific category and its attributes
  #
  # @param shop [Shop] Shop with OLX authentication
  # @param category_id [Integer] OLX category ID
  # @return [OlxCategory] Synced category record
  #
  def self.sync_category(shop, category_id)
    Rails.logger.info "[OLX Category Sync] Syncing category #{category_id}"

    begin
      # Fetch category details from OLX API
      response = OlxApiService.get("/categories/#{category_id}", shop)
      category_data = response['data'] || response

      # Sync the category
      category = sync_category_data(category_data)

      # Fetch and sync attributes for this category
      sync_category_attributes(shop, category)

      category
    rescue OlxApiService::NotFoundError
      Rails.logger.error "[OLX Category Sync] Category #{category_id} not found"
      raise SyncError, "Category #{category_id} not found on OLX"
    rescue => e
      Rails.logger.error "[OLX Category Sync] Failed to sync category #{category_id}: #{e.message}"
      raise SyncError, "Failed to sync category: #{e.message}"
    end
  end

  ##
  # Sync category attributes from OLX API
  #
  # @param shop [Shop] Shop with OLX authentication
  # @param category [OlxCategory] Category to sync attributes for
  # @return [Integer] Number of attributes synced
  #
  def self.sync_category_attributes(shop, category)
    Rails.logger.info "[OLX Category Sync] Syncing attributes for category #{category.external_id}"

    begin
      # Fetch category attributes from OLX API
      response = OlxApiService.get("/categories/#{category.external_id}/attributes", shop)
      attributes_data = response['data'] || response['attributes'] || []

      synced_count = 0

      attributes_data.each do |attr_data|
        # Find or create attribute by external_id
        attribute = category.olx_category_attributes.find_or_initialize_by(
          external_id: attr_data['id']
        )

        attribute.assign_attributes(
          name: attr_data['name'] || attr_data['key'],
          attribute_type: attr_data['type'],
          input_type: attr_data['input_type'] || attr_data['widget'],
          required: attr_data['required'] || false,
          options: extract_attribute_options(attr_data)
        )

        if attribute.save
          synced_count += 1
        else
          Rails.logger.warn "[OLX Category Sync] Failed to save attribute #{attr_data['name']}: #{attribute.errors.full_messages.join(', ')}"
        end
      end

      Rails.logger.info "[OLX Category Sync] Synced #{synced_count} attributes for category #{category.external_id}"
      synced_count
    rescue => e
      Rails.logger.error "[OLX Category Sync] Failed to sync attributes: #{e.message}"
      0
    end
  end

  ##
  # Delete categories that no longer exist on OLX
  #
  # @param shop [Shop] Shop with OLX authentication
  # @return [Integer] Number of categories deleted
  #
  def self.cleanup_removed_categories(shop)
    Rails.logger.info "[OLX Category Sync] Cleaning up removed categories"

    begin
      # Fetch current category IDs from OLX
      response = OlxApiService.get('/categories', shop)
      categories_data = response['data'] || response['categories'] || []
      current_external_ids = categories_data.map { |c| c['id'] }.compact

      # Find categories in our DB that no longer exist on OLX
      removed_categories = OlxCategory.where.not(external_id: current_external_ids)
      deleted_count = removed_categories.count

      if deleted_count > 0
        removed_categories.destroy_all
        Rails.logger.info "[OLX Category Sync] Deleted #{deleted_count} removed categories"
      end

      deleted_count
    rescue => e
      Rails.logger.error "[OLX Category Sync] Cleanup failed: #{e.message}"
      0
    end
  end

  private

  ##
  # Sync individual category data to database
  #
  # @param category_data [Hash] Category data from OLX API
  # @return [OlxCategory] Synced category record
  #
  def self.sync_category_data(category_data)
    external_id = category_data['id']

    # Find or create category
    category = OlxCategory.find_or_initialize_by(external_id: external_id)

    category.assign_attributes(
      name: category_data['name'],
      slug: category_data['slug'] || category_data['name']&.parameterize,
      parent_id: category_data['parent_id'],
      has_shipping: category_data['has_shipping'] || false,
      has_brand: category_data['has_brand'] || false,
      metadata: extract_metadata(category_data)
    )

    if category.save
      Rails.logger.debug "[OLX Category Sync] Synced category: #{category.name} (ID: #{external_id})"
    else
      Rails.logger.error "[OLX Category Sync] Failed to save category #{external_id}: #{category.errors.full_messages.join(', ')}"
      raise SyncError, "Failed to save category: #{category.errors.full_messages.join(', ')}"
    end

    category
  end

  ##
  # Extract metadata from category data
  #
  # @param category_data [Hash] Category data from API
  # @return [Hash] Metadata hash
  #
  def self.extract_metadata(category_data)
    {
      icon: category_data['icon'],
      level: category_data['level'],
      order: category_data['order'],
      active: category_data['active'],
      additional_info: category_data['additional_info']
    }.compact
  end

  ##
  # Extract attribute options from attribute data
  #
  # @param attr_data [Hash] Attribute data from API
  # @return [Hash] Options hash
  #
  def self.extract_attribute_options(attr_data)
    options = {}

    # Extract possible values for select/radio inputs
    if attr_data['values'] || attr_data['options']
      options['values'] = attr_data['values'] || attr_data['options']
    end

    # Extract validation rules
    options['min'] = attr_data['min'] if attr_data['min']
    options['max'] = attr_data['max'] if attr_data['max']
    options['min_length'] = attr_data['min_length'] if attr_data['min_length']
    options['max_length'] = attr_data['max_length'] if attr_data['max_length']
    options['pattern'] = attr_data['pattern'] if attr_data['pattern']

    # Extract display info
    options['label'] = attr_data['display_name'] || attr_data['label'] if attr_data['display_name'] || attr_data['label']
    options['placeholder'] = attr_data['placeholder'] if attr_data['placeholder']
    options['help_text'] = attr_data['help_text'] if attr_data['help_text']

    options
  end
end
