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
    return "" if [address_line1, city, country_code].all?(&:blank?)

    road = [address_line1, address_line2].compact_blank.join("\n")
    
    address_components = {
      "road" => road.presence,
      "city" => city.presence,
      "state" => state.presence,
      "postcode" => zipcode.presence,
      "country" => ISO3166::Country.new(country_code)&.common_name,
      "country_code" => country_code.presence
    }.compact

    AddressComposer.compose(address_components).gsub("\n", "<br>")
  end
end
