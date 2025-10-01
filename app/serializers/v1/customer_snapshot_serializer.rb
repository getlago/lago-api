# frozen_string_literal: true

module V1
  class CustomerSnapshotSerializer < ModelSerializer
    def serialize
      {
        display_name: model.display_name,
        firstname: model.firstname,
        lastname: model.lastname,
        email: model.email,
        phone: model.phone,
        url: model.url,
        tax_identification_number: model.tax_identification_number,
        applicable_timezone: model.applicable_timezone,
        address_line1: model.address_line1,
        address_line2: model.address_line2,
        city: model.city,
        state: model.state,
        zipcode: model.zipcode,
        country: model.country,
        legal_name: model.legal_name,
        legal_number: model.legal_number,
        shipping_address: model.shipping_address
      }
    end
  end
end
