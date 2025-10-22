class OlxListing < ApplicationRecord
  # Associations
  belongs_to :product
  belongs_to :shop

  # Validations
  validates :external_listing_id, uniqueness: true, allow_nil: true
  validates :status, presence: true

  # Scopes
  scope :published, -> { where(status: 'published') }
  scope :draft, -> { where(status: 'draft') }
  scope :pending, -> { where(status: 'pending') }
  scope :failed, -> { where(status: 'failed') }

  # Status constants
  STATUSES = %w[draft pending published failed removed].freeze

  ##
  # Check if listing is published on OLX
  #
  # @return [Boolean]
  #
  def published?
    status == 'published' && external_listing_id.present?
  end

  ##
  # Check if listing is in draft state
  #
  # @return [Boolean]
  #
  def draft?
    status == 'draft'
  end

  ##
  # Get OLX listing URL
  #
  # @return [String, nil]
  #
  def olx_url
    return nil unless external_listing_id.present?

    "https://olx.ba/artikal/#{external_listing_id}"
  end

  ##
  # Publish this listing on OLX
  #
  # @return [OlxListing] self
  #
  def publish!
    service = OlxListingService.new(product)
    service.publish_listing(self)
  end

  ##
  # Unpublish this listing on OLX
  #
  # @return [OlxListing] self
  #
  def unpublish!
    service = OlxListingService.new(product)
    service.unpublish_listing(self)
  end

  ##
  # Update this listing on OLX
  #
  # @return [OlxListing] self
  #
  def update_on_olx!
    service = OlxListingService.new(product)
    service.update_listing(self)
  end

  ##
  # Delete this listing from OLX
  #
  # @return [Boolean] true if successful
  #
  def delete_from_olx!
    service = OlxListingService.new(product)
    service.delete_listing(self)
  end

  ##
  # Check if listing failed
  #
  # @return [Boolean]
  #
  def failed?
    status == 'failed'
  end

  ##
  # Check if listing is pending
  #
  # @return [Boolean]
  #
  def pending?
    status == 'pending'
  end

  ##
  # Get error message if listing failed
  #
  # @return [String, nil]
  #
  def error_message
    return nil unless failed?

    metadata&.dig('error') || 'Unknown error'
  end
end
