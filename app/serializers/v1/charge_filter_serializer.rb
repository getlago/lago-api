# frozen_string_literal: true

module V1
  class ChargeFilterSerializer < ModelSerializer
    def serialize
      {
        invoice_display_name: model.invoice_display_name,
        properties: model.properties,
        values: model.to_h,
      }
    end
  end
end
