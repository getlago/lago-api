# frozen_string_literal: true

class UrlValidator < ActiveModel::EachValidator
  def validate_each(record, attribute, value)
    if !url_valid?(value)
      record.errors.add(attribute, :url_invalid)
    elsif options[:block_private_addresses] && record.attribute_changed?(attribute) && private_address?(value)
      record.errors.add(attribute, :url_invalid)
    end
  end

  private

  def url_valid?(url)
    url = URI.parse(url)
    url.host.present? && (url.is_a?(URI::HTTP) || url.is_a?(URI::HTTPS))
  rescue
    false
  end

  # An unresolvable host is accepted here: the HTTP client checks the address again at request time.
  def private_address?(url)
    return false unless LagoHttpClient::AddressGuard.enabled?

    LagoHttpClient::AddressGuard.resolve!(URI.parse(url).hostname)
    false
  rescue LagoHttpClient::BlockedAddressError
    true
  rescue SocketError
    false
  end
end
