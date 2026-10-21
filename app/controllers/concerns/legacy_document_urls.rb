# frozen_string_literal: true

# Document links issued before expiring URLs existed go through the stock Active Storage
# routes and never expire. Once LAGO_LEGACY_DOCUMENT_URLS_EXPIRE_AT is past, those routes
# refuse blobs attached to documents. Logos and data exports are not affected.
module LegacyDocumentUrls
  extend ActiveSupport::Concern
  include ExpiredDocumentUrl

  DOCUMENT_RECORD_TYPES = %w[Invoice CreditNote PaymentReceipt OrderForm].freeze

  included do
    before_action :reject_legacy_document_url
  end

  private

  def reject_legacy_document_url
    return if @blob.nil?

    expire_at = Time.zone.parse(ENV["LAGO_LEGACY_DOCUMENT_URLS_EXPIRE_AT"].to_s)
    return if expire_at.nil? || Time.current < expire_at
    return unless @blob.attachments.where(record_type: DOCUMENT_RECORD_TYPES).exists?

    render_expired_document_url
  end
end
