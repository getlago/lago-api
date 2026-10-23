# frozen_string_literal: true

# Parsed once at boot: a malformed value must stop the app, not fail every blob request.
legacy_expire_at_value = ENV["LAGO_LEGACY_DOCUMENT_URLS_EXPIRE_AT"]

# NOTE: Set explicitly, an unset config.x key returns an empty OrderedOptions, not nil
Rails.application.config.x.legacy_document_urls_expire_at = nil

if legacy_expire_at_value.present?
  legacy_expire_at = begin
    Time.find_zone!("UTC").parse(legacy_expire_at_value)
  rescue ArgumentError
    nil
  end

  raise ArgumentError, "LAGO_LEGACY_DOCUMENT_URLS_EXPIRE_AT is not a valid date: #{legacy_expire_at_value}" if legacy_expire_at.nil?

  Rails.application.config.x.legacy_document_urls_expire_at = legacy_expire_at
end

Rails.application.config.to_prepare do
  ActiveStorage::Blobs::RedirectController.include(LegacyDocumentUrls)
  ActiveStorage::Blobs::ProxyController.include(LegacyDocumentUrls)
end
