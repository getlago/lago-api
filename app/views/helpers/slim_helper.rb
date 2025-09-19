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
    country = ISO3166::Country.new(country_code)
    country.address_format.gsub("{{recipient}}", address_line1)
      .gsub("{{street}}", address_line2)
      .gsub("{{postalcode}}", zipcode)
      .gsub("{{city}}", city)
      .gsub("{{region}}", state)
      .gsub("{{region_short}}", state)
      .gsub("{{country}}", country.common_name)
      .gsub("\n", "<br>")
  end
end
