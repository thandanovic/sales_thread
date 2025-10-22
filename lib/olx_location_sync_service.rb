# frozen_string_literal: true

##
# OlxLocationSyncService
#
# Service for syncing OLX locations from the OLX API to the local database.
#
# Usage:
#   # Sync all locations
#   OlxLocationSyncService.sync_all(shop)
#
#   # Sync a specific location
#   OlxLocationSyncService.sync_location(shop, location_id)
#
class OlxLocationSyncService
  class SyncError < StandardError; end

  ##
  # Sync all locations from OLX API
  #
  # @param shop [Shop] Shop with OLX authentication
  # @return [Hash] Summary of sync operation
  #
  def self.sync_all(shop)
    Rails.logger.info "[OLX Location Sync] Starting full location sync for shop #{shop.id}"

    start_time = Time.current
    synced_count = 0
    failed_count = 0
    errors = []

    begin
      # Fetch all locations from OLX API
      response = OlxApiService.get('/locations', shop)
      locations_data = response['data'] || response['locations'] || []

      Rails.logger.info "[OLX Location Sync] Found #{locations_data.size} locations to sync"

      locations_data.each do |location_data|
        begin
          sync_location_data(location_data)
          synced_count += 1
        rescue => e
          failed_count += 1
          error_message = "Location #{location_data['id']}: #{e.message}"
          errors << error_message
          Rails.logger.error "[OLX Location Sync] #{error_message}"
        end
      end

      duration = Time.current - start_time
      Rails.logger.info "[OLX Location Sync] Completed in #{duration.round(2)}s. Synced: #{synced_count}, Failed: #{failed_count}"

      {
        success: true,
        synced_count: synced_count,
        failed_count: failed_count,
        total_count: locations_data.size,
        duration: duration,
        errors: errors
      }
    rescue OlxApiService::AuthenticationError => e
      Rails.logger.error "[OLX Location Sync] Authentication error: #{e.message}"
      raise SyncError, "Authentication failed: #{e.message}"
    rescue => e
      Rails.logger.error "[OLX Location Sync] Sync failed: #{e.message}"
      raise SyncError, "Sync failed: #{e.message}"
    end
  end

  ##
  # Sync a specific location
  #
  # @param shop [Shop] Shop with OLX authentication
  # @param location_id [Integer] OLX location ID
  # @return [OlxLocation] Synced location record
  #
  def self.sync_location(shop, location_id)
    Rails.logger.info "[OLX Location Sync] Syncing location #{location_id}"

    begin
      # Fetch location details from OLX API
      response = OlxApiService.get("/locations/#{location_id}", shop)
      location_data = response['data'] || response

      # Sync the location
      sync_location_data(location_data)
    rescue OlxApiService::NotFoundError
      Rails.logger.error "[OLX Location Sync] Location #{location_id} not found"
      raise SyncError, "Location #{location_id} not found on OLX"
    rescue => e
      Rails.logger.error "[OLX Location Sync] Failed to sync location #{location_id}: #{e.message}"
      raise SyncError, "Failed to sync location: #{e.message}"
    end
  end

  ##
  # Sync cities from OLX API (these are the actual locations needed for listings)
  #
  # @param shop [Shop] Shop with OLX authentication
  # @return [Hash] Summary of sync operation
  #
  def self.sync_cities(shop)
    Rails.logger.info "[OLX Location Sync] Starting city sync for shop #{shop.id}"

    start_time = Time.current
    synced_count = 0
    failed_count = 0
    errors = []

    begin
      # Fetch all cities from OLX API (returns nested structure)
      response = OlxApiService.get('/cities', shop)
      regions_data = response['data'] || []

      Rails.logger.info "[OLX Location Sync] Processing #{regions_data.size} regions"

      # Extract cities from nested structure
      regions_data.each do |region|
        cantons = region['cantons'] || []
        cantons.each do |canton|
          cities = canton['cities'] || []
          cities.each do |city_data|
            begin
              # Add region and canton info to city data
              city_data['region_name'] = region['name']
              city_data['canton_name'] = canton['name']
              sync_location_data(city_data)
              synced_count += 1
            rescue => e
              failed_count += 1
              error_message = "City #{city_data['id']} (#{city_data['name']}): #{e.message}"
              errors << error_message
              Rails.logger.error "[OLX Location Sync] #{error_message}"
            end
          end
        end
      end

      duration = Time.current - start_time
      Rails.logger.info "[OLX Location Sync] Cities sync completed in #{duration.round(2)}s. Synced: #{synced_count}, Failed: #{failed_count}"

      {
        success: true,
        synced_count: synced_count,
        failed_count: failed_count,
        total_count: synced_count + failed_count,
        duration: duration,
        errors: errors
      }
    rescue OlxApiService::AuthenticationError => e
      Rails.logger.error "[OLX Location Sync] Authentication error: #{e.message}"
      raise SyncError, "Authentication failed: #{e.message}"
    rescue => e
      Rails.logger.error "[OLX Location Sync] City sync failed: #{e.message}"
      raise SyncError, "City sync failed: #{e.message}"
    end
  end

  ##
  # Sync locations for a specific country
  #
  # @param shop [Shop] Shop with OLX authentication
  # @param country_id [Integer] Country ID
  # @return [Hash] Summary of sync operation
  #
  def self.sync_by_country(shop, country_id)
    Rails.logger.info "[OLX Location Sync] Syncing locations for country #{country_id}"

    begin
      response = OlxApiService.get("/locations?country_id=#{country_id}", shop)
      locations_data = response['data'] || response['locations'] || []

      synced_count = 0
      locations_data.each do |location_data|
        sync_location_data(location_data)
        synced_count += 1
      end

      {
        success: true,
        synced_count: synced_count,
        country_id: country_id
      }
    rescue => e
      Rails.logger.error "[OLX Location Sync] Failed to sync locations for country #{country_id}: #{e.message}"
      raise SyncError, "Failed to sync locations: #{e.message}"
    end
  end

  ##
  # Delete locations that no longer exist on OLX
  #
  # @param shop [Shop] Shop with OLX authentication
  # @return [Integer] Number of locations deleted
  #
  def self.cleanup_removed_locations(shop)
    Rails.logger.info "[OLX Location Sync] Cleaning up removed locations"

    begin
      # Fetch current location IDs from OLX
      response = OlxApiService.get('/locations', shop)
      locations_data = response['data'] || response['locations'] || []
      current_external_ids = locations_data.map { |l| l['id'] }.compact

      # Find locations in our DB that no longer exist on OLX
      removed_locations = OlxLocation.where.not(external_id: current_external_ids)
      deleted_count = removed_locations.count

      if deleted_count > 0
        removed_locations.destroy_all
        Rails.logger.info "[OLX Location Sync] Deleted #{deleted_count} removed locations"
      end

      deleted_count
    rescue => e
      Rails.logger.error "[OLX Location Sync] Cleanup failed: #{e.message}"
      0
    end
  end

  private

  ##
  # Sync individual location data to database
  #
  # @param location_data [Hash] Location data from OLX API
  # @return [OlxLocation] Synced location record
  #
  def self.sync_location_data(location_data)
    external_id = location_data['id']

    # Find or create location
    location = OlxLocation.find_or_initialize_by(external_id: external_id)

    # Extract coordinates from location object if present
    coords = location_data['location'] || {}

    location.assign_attributes(
      name: location_data['name'],
      country_id: location_data['country_id'],
      state_id: location_data['state_id'] || location_data['region_id'],
      canton_id: location_data['canton_id'],
      lat: coords['lat'] || location_data['lat'] || location_data['latitude'],
      lon: coords['lon'] || location_data['lon'] || location_data['longitude'],
      zip_code: location_data['zip_code'] || location_data['postal_code']
    )

    if location.save
      Rails.logger.debug "[OLX Location Sync] Synced location: #{location.name} (ID: #{external_id})"
    else
      Rails.logger.error "[OLX Location Sync] Failed to save location #{external_id}: #{location.errors.full_messages.join(', ')}"
      raise SyncError, "Failed to save location: #{location.errors.full_messages.join(', ')}"
    end

    location
  end
end
