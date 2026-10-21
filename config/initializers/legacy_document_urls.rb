# frozen_string_literal: true

Rails.application.config.to_prepare do
  ActiveStorage::Blobs::RedirectController.include(LegacyDocumentUrls)
  ActiveStorage::Blobs::ProxyController.include(LegacyDocumentUrls)
end
