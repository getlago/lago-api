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
    country = ISO3166::Country.new(country_code) || ISO3166::Country.new("US")

    address_format = country.address_format.presence || "{{recipient}}<br>{{street}}<br>{{city}} {{region}} {{postalcode}}<br>{{country}}"

    field_values = {}
    field_values["{{recipient}}"] = address_line1 if address_line1.present?
    field_values["{{street}}"] = address_line2 if address_line2.present?
    field_values["{{postalcode}}"] = zipcode if zipcode.present?
    field_values["{{city}}"] = city if city.present?
    field_values["{{region}}"] = state if state.present?
    field_values["{{region_short}}"] = state if state.present?
    field_values["{{country}}"] = country.common_name if country.common_name.present?

    formatted = address_format.dup
    field_values.each do |placeholder, value|
      formatted = formatted.gsub(placeholder, value)
    end

    formatted
      .gsub(/\{\{[^}]+\}\}/, "") # Remove any remaining placeholders
      .gsub(/\s+/, " ") # Replace multiple spaces with single space
      .gsub(/\s*<br>\s*/, "<br>") # Clean up spaces around line breaks
      .gsub(/<br>(\s*<br>)+/, "<br>") # Remove multiple consecutive line breaks
      .gsub(/^<br>|<br>$/, "") # Remove line breaks at start/end
      .strip # Trim whitespace at start/end
      .gsub("\n", "<br>")
  end
end
