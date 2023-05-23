# frozen_string_literal: true

module V1
  class ChargeSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        lago_billable_metric_id: model.billable_metric_id,
        billable_metric_code: model.billable_metric.code,
        created_at: model.created_at.iso8601,
        charge_model: model.charge_model,
        invoiceable: model.invoiceable,
        pay_in_advance: model.pay_in_advance,
        min_amount_cents: model.min_amount_cents,
        properties: model.properties,
      }.merge(group_properties)
    end

    private

    def group_properties
      ::CollectionSerializer.new(
        model.group_properties,
        ::V1::GroupPropertiesSerializer,
        collection_name: 'group_properties',
      ).serialize
    end
  end
end
