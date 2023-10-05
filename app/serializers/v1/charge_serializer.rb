# frozen_string_literal: true

module V1
  class ChargeSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        lago_billable_metric_id: model.billable_metric_id,
        invoice_display_name: model.invoice_display_name,
        billable_metric_code: model.billable_metric.code,
        created_at: model.created_at.iso8601,
        charge_model: model.charge_model,
        invoiceable: model.invoiceable,
        pay_in_advance: model.pay_in_advance,
        prorated: model.prorated,
        min_amount_cents: model.min_amount_cents,
        properties: model.properties,
      }

      payload.merge!(group_properties)

      payload.merge!(taxes) if include?(:taxes)

      payload
    end

    private

    def group_properties
      ::CollectionSerializer.new(
        model.group_properties,
        ::V1::GroupPropertiesSerializer,
        collection_name: 'group_properties',
      ).serialize
    end

    def taxes
      ::CollectionSerializer.new(
        model.taxes,
        ::V1::TaxSerializer,
        collection_name: 'taxes',
      ).serialize
    end
  end
end
