# frozen_string_literal: true

# Serves the expiring document links built by ExpiringDocumentUrl.
class DocumentsController < ApplicationController
  include ActiveStorage::SetCurrent
  include ExpiredDocumentUrl

  def show
    blob = ActiveStorage::Blob.find_signed(params[:signed_id], purpose: ExpiringDocumentUrl::PURPOSE)

    if blob
      expires_in ActiveStorage.service_urls_expire_in
      redirect_to blob.url(disposition: params[:disposition]), allow_other_host: true
    elsif expired_document_url?(params[:signed_id])
      render_expired_document_url
    else
      not_found
    end
  end

  private

  # A fresh link only helps when the signature is ours, the link is a document link, its
  # expiry has passed and the file still exists. Anything else is a 404, so integrations
  # don't keep fetching new links to a missing file.
  def expired_document_url?(signed_id)
    return false unless ActiveStorage::Blob.signed_id_verifier.valid_message?(signed_id)

    data = signed_id.rpartition("--").first
    message = JSON.parse(Base64.decode64(data.tr("-_", "+/")))
    message = message["_rails"] if message.is_a?(Hash)
    return false unless message.is_a?(Hash)
    return false unless message["pur"] == ExpiringDocumentUrl::PURPOSE.to_s
    return false if message["exp"].blank? || Time.iso8601(message["exp"]).future?

    ActiveStorage::Blob.exists?(id: message["data"])
  rescue ArgumentError, JSON::ParserError
    false
  end
end
