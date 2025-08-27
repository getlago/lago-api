# frozen_string_literal: true

class SlimHelper
  PDF_LOGO_FILENAME = "lago-logo-invoice.png"

  def self.render(path, context, **locals)
    Slim::Template.new do
      File.read(
        Rails.root.join("app/views/#{path}.slim"),
        encoding: "UTF-8"
      )
    end.render(context, **locals)
  end

  def self.format_address(address_line1, address_line2, city, state, zipcode, country_code)
    country = ISO3166::Country.new(country_code)&.common_name

    case country_code&.upcase
    when "DE", "FR", "IT"
      [
        address_line1,
        address_line2,
        [zipcode, city].compact.join(" "),
        country
      ].compact.reject(&:empty?)
    when "US", "CA", "GB", "AU"
      [
        address_line1,
        address_line2,
        [city, [state, zipcode].compact.join(" ")].compact.join(", "),
        country
      ].compact.reject(&:empty?)
    when "BR"
      [
        address_line1,
        address_line2,
        [city, state].compact.join(" - ") + (zipcode.present? ? ", #{zipcode}" : ""),
        country
      ].compact.reject(&:empty?)
    when "ES"
      [
        address_line1,
        address_line2,
        [zipcode, [city, state].compact.join(", ")].compact.join(" "),
        country
      ].compact.reject(&:empty?)
    else
      [
        address_line1,
        address_line2,
        [city, [state, zipcode].compact.join(" ")].compact.join(", "),
        country
      ].compact.reject(&:empty?)
    end
  end
end
