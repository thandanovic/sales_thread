# frozen_string_literal: true

require 'net/http'
require 'json'
require 'uri'

##
# OlxApiService
#
# Ruby service for interacting with the OLX API.
# Handles authentication, token management, and API requests.
#
# Usage:
#   # Authenticate
#   OlxApiService.authenticate(shop)
#
#   # Make API requests
#   categories = OlxApiService.get('/categories', shop)
#   listing = OlxApiService.post('/listings', { title: 'Product' }, shop)
#
class OlxApiService
  class ApiError < StandardError; end
  class AuthenticationError < ApiError; end
  class NotFoundError < ApiError; end
  class ValidationError < ApiError; end

  BASE_URL = 'https://api.olx.ba'
  API_VERSION = 'v1'

  ##
  # Authenticate shop with OLX API and store access token
  #
  # @param shop [Shop] Shop with OLX credentials
  # @return [Hash] Authentication response with token
  #
  def self.authenticate(shop)
    raise AuthenticationError, 'OLX username is required' if shop.olx_username.blank?
    raise AuthenticationError, 'OLX password is required' if shop.olx_password.blank?

    uri = URI.parse("#{BASE_URL}/auth/login")
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.path)
    request['Content-Type'] = 'application/json'
    request.body = {
      username: shop.olx_username,
      password: shop.olx_password,
      device_name: 'rails_app'
    }.to_json

    response = http.request(request)
    data = JSON.parse(response.body)

    if response.code.to_i == 200 && data['token']
      # Store token and expiration
      shop.update!(
        olx_access_token: data['token'],
        olx_token_expires_at: 30.days.from_now # OLX tokens typically expire after 30 days
      )

      Rails.logger.info "[OLX API] Successfully authenticated for shop #{shop.id}"
      { success: true, token: data['token'], user: data['user'] }
    else
      error_message = data['message'] || data['error'] || 'Authentication failed'
      Rails.logger.error "[OLX API] Authentication failed: #{error_message}"
      raise AuthenticationError, error_message
    end
  rescue JSON::ParserError => e
    Rails.logger.error "[OLX API] Failed to parse authentication response: #{e.message}"
    raise AuthenticationError, 'Invalid response from OLX API'
  rescue StandardError => e
    Rails.logger.error "[OLX API] Authentication error: #{e.message}"
    raise AuthenticationError, e.message
  end

  ##
  # Check if shop has valid OLX token
  #
  # @param shop [Shop]
  # @return [Boolean]
  #
  def self.authenticated?(shop)
    shop.olx_access_token.present? &&
      shop.olx_token_expires_at.present? &&
      shop.olx_token_expires_at > Time.current
  end

  ##
  # Ensure shop is authenticated, re-authenticate if needed
  #
  # @param shop [Shop]
  # @return [Boolean]
  #
  def self.ensure_authenticated!(shop)
    return true if authenticated?(shop)

    authenticate(shop)
    true
  end

  ##
  # Make authenticated GET request to OLX API
  #
  # @param endpoint [String] API endpoint (e.g., '/categories')
  # @param shop [Shop] Shop with authentication
  # @param params [Hash] Query parameters
  # @return [Hash] Parsed JSON response
  #
  def self.get(endpoint, shop, params = {})
    ensure_authenticated!(shop)

    uri = build_uri(endpoint, params)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Get.new(uri.request_uri)
    add_auth_headers(request, shop)

    response = http.request(request)
    handle_response(response, endpoint)
  end

  ##
  # Make authenticated POST request to OLX API
  #
  # @param endpoint [String] API endpoint
  # @param body [Hash] Request body
  # @param shop [Shop] Shop with authentication
  # @return [Hash] Parsed JSON response
  #
  def self.post(endpoint, body, shop)
    ensure_authenticated!(shop)

    uri = build_uri(endpoint)
    Rails.logger.info "[OLX API] POST #{uri}"
    Rails.logger.info "[OLX API] Request body: #{body.to_json}"

    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Post.new(uri.path)
    add_auth_headers(request, shop)
    request.body = body.to_json

    response = http.request(request)
    Rails.logger.info "[OLX API] Response status: #{response.code}"
    Rails.logger.info "[OLX API] Response body: #{response.body}"

    handle_response(response, endpoint)
  end

  ##
  # Make authenticated PUT request to OLX API
  #
  # @param endpoint [String] API endpoint
  # @param body [Hash] Request body
  # @param shop [Shop] Shop with authentication
  # @return [Hash] Parsed JSON response
  #
  def self.put(endpoint, body, shop)
    ensure_authenticated!(shop)

    uri = build_uri(endpoint)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Put.new(uri.path)
    add_auth_headers(request, shop)
    request.body = body.to_json

    response = http.request(request)
    handle_response(response, endpoint)
  end

  ##
  # Make authenticated DELETE request to OLX API
  #
  # @param endpoint [String] API endpoint
  # @param shop [Shop] Shop with authentication
  # @return [Hash] Parsed JSON response
  #
  def self.delete(endpoint, shop)
    ensure_authenticated!(shop)

    uri = build_uri(endpoint)
    http = Net::HTTP.new(uri.host, uri.port)
    http.use_ssl = true

    request = Net::HTTP::Delete.new(uri.path)
    add_auth_headers(request, shop)

    response = http.request(request)
    handle_response(response, endpoint)
  end

  ##
  # Upload images to an OLX listing
  #
  # @param listing_id [Integer] OLX listing ID
  # @param image_urls [Array<String>] Array of image URLs to upload
  # @param shop [Shop] Shop with OLX authentication
  # @return [Array<Hash>] Array of uploaded image objects
  #
  def self.upload_images(listing_id, image_urls, shop)
    ensure_authenticated!(shop)

    return [] if image_urls.blank?

    # Filter to only use 300x300 images (higher quality)
    filtered_urls = image_urls.select { |url| url.include?('300x300') }

    if filtered_urls.empty?
      Rails.logger.warn "[OLX API] No 300x300 images found, using all images"
      filtered_urls = image_urls
    end

    Rails.logger.info "[OLX API] Uploading #{filtered_urls.length} images (300x300) to listing #{listing_id}"

    uploaded_images = []

    filtered_urls.each_with_index do |image_url, index|
      begin
        Rails.logger.info "[OLX API] Uploading image #{index + 1}/#{filtered_urls.length}: #{image_url}"

        # Download image from URL
        uri = URI.parse(image_url)
        image_data = Net::HTTP.get(uri)

        # Build multipart form request
        endpoint = "/listings/#{listing_id}/image-upload"
        upload_uri = build_uri(endpoint)
        http = Net::HTTP.new(upload_uri.host, upload_uri.port)
        http.use_ssl = true

        request = Net::HTTP::Post.new(upload_uri.path)
        request['Authorization'] = "Bearer #{shop.olx_access_token}"

        # Create multipart form data
        boundary = "----RubyMultipartBoundary#{SecureRandom.hex(16)}"
        request['Content-Type'] = "multipart/form-data; boundary=#{boundary}"

        # Get file extension from URL
        ext = File.extname(URI.parse(image_url).path)
        ext = '.jpg' if ext.blank?
        filename = "image_#{index}#{ext}"

        # Build multipart body
        post_body = []
        post_body << "--#{boundary}\r\n"
        post_body << "Content-Disposition: form-data; name=\"image\"; filename=\"#{filename}\"\r\n"
        post_body << "Content-Type: image/jpeg\r\n\r\n"
        post_body << image_data
        post_body << "\r\n--#{boundary}--\r\n"

        request.body = post_body.join

        response = http.request(request)

        if response.code.to_i.between?(200, 299)
          result = JSON.parse(response.body)
          uploaded_images << result
          Rails.logger.info "[OLX API] ✓ Image #{index + 1} uploaded successfully"
        else
          Rails.logger.warn "[OLX API] ✗ Failed to upload image #{index + 1}: #{response.body}"
        end
      rescue => e
        Rails.logger.error "[OLX API] ✗ Error uploading image #{index + 1}: #{e.message}"
      end
    end

    Rails.logger.info "[OLX API] Uploaded #{uploaded_images.length}/#{image_urls.length} images"
    uploaded_images
  end

  private

  def self.build_uri(endpoint, params = {})
    path = endpoint.start_with?('/') ? endpoint : "/#{endpoint}"
    url = "#{BASE_URL}#{path}"

    if params.any?
      query_string = URI.encode_www_form(params)
      url += "?#{query_string}"
    end

    URI.parse(url)
  end

  def self.add_auth_headers(request, shop)
    request['Authorization'] = "Bearer #{shop.olx_access_token}"
    request['Content-Type'] = 'application/json'
    request['Accept'] = 'application/json'
  end

  def self.handle_response(response, endpoint)
    case response.code.to_i
    when 200, 201
      Rails.logger.info "[OLX API] ✓ Success (#{response.code})"
      JSON.parse(response.body)
    when 204
      Rails.logger.info "[OLX API] ✓ Success (204 No Content)"
      {} # No content
    when 401, 403
      error_message = parse_error_message(response.body)
      Rails.logger.error "[OLX API] ✗ Authentication error on #{endpoint}: #{error_message}"
      Rails.logger.error "[OLX API] Response body: #{response.body}"
      raise AuthenticationError, error_message
    when 404
      error_message = parse_error_message(response.body)
      Rails.logger.error "[OLX API] ✗ Not found on #{endpoint}: #{error_message}"
      Rails.logger.error "[OLX API] Response body: #{response.body}"
      raise NotFoundError, error_message
    when 422
      error_message = parse_error_message(response.body)
      Rails.logger.error "[OLX API] ✗ Validation error on #{endpoint}: #{error_message}"
      Rails.logger.error "[OLX API] Response body: #{response.body}"
      raise ValidationError, error_message
    else
      error_message = parse_error_message(response.body)
      Rails.logger.error "[OLX API] ✗ Request failed on #{endpoint}: #{response.code} - #{error_message}"
      Rails.logger.error "[OLX API] Response body: #{response.body}"
      raise ApiError, "API request failed (#{response.code}): #{error_message}"
    end
  rescue JSON::ParserError => e
    Rails.logger.error "[OLX API] ✗ Failed to parse response from #{endpoint}: #{e.message}"
    Rails.logger.error "[OLX API] Raw response: #{response.body}"
    raise ApiError, 'Invalid response from OLX API'
  end

  def self.parse_error_message(body)
    data = JSON.parse(body)
    data['message'] || data['error'] || data['errors']&.first || 'Unknown error'
  rescue JSON::ParserError
    body
  end
end
