# frozen_string_literal: true

module V1
  class CustomerSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        customer_id: model.customer_id,
        name: model.name,
        created_at: model.created_at.iso8601,
        country: model.country,
        address_line1: model.address_line1,
        address_line2: model.address_line2,
        state: model.state,
        zipcode: model.zipcode,
        email: model.email,
        city: model.city,
        url: model.url,
        phone: model.phone,
        logo_url: model.logo_url,
        legal_name: model.legal_name,
        legal_number: model.legal_number,
      }
    end
  end
end
