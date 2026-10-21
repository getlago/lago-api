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
    elsif ActiveStorage::Blob.signed_id_verifier.valid_message?(params[:signed_id])
      # The signature is ours but the link is past its expiry.
      render_expired_document_url
    else
      not_found
    end
  end
end
