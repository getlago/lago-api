# frozen_string_literal: true

module V1
  class FixedChargeSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        lago_add_on_id: model.add_on_id,
        invoice_display_name: model.invoice_display_name,
        add_on_code: model.add_on.code,
        created_at: model.created_at.iso8601,
        charge_model: model.charge_model,
        pay_in_advance: model.pay_in_advance,
        prorated: model.prorated,
        properties: model.properties,
        units: model.units
      }

      payload.merge!(taxes) if include?(:taxes)

      payload
    end

    private

    def taxes
      ::CollectionSerializer.new(
        model.taxes,
        ::V1::TaxSerializer,
        collection_name: "taxes"
      ).serialize
    end
  end
end
