# frozen_string_literal: true

# Builds expiring download links for confidential documents (invoices, credit notes,
# payment receipts, order forms). A link expires `organization.document_url_expiration_days`
# after the document's anchor date, and always stays valid for at least MINIMUM_VALIDITY
# after it is built, so a URL fetched today never fails tomorrow.
module ExpiringDocumentUrl
  extend ActiveSupport::Concern

  PURPOSE = :document
  MINIMUM_VALIDITY = 10.days

  def document_url_expires_at
    floor = (Time.current + MINIMUM_VALIDITY).end_of_day
    anchor = document_url_anchor_date
    return floor if anchor.blank?

    [(anchor + organization.document_url_expiration_days.days).end_of_day, floor].max
  end

  private

  # The date the expiry window starts from. Overridden by each document.
  def document_url_anchor_date
    created_at&.to_date
  end

  def expiring_document_url(attachment)
    return if attachment.blank?

    signed_id = attachment.blob.signed_id(purpose: PURPOSE, expires_at: document_url_expires_at)
    path = Rails.application.routes.url_helpers.document_path(signed_id, attachment.filename.to_s)

    File.join(ENV["LAGO_API_URL"], path)
  end
end
