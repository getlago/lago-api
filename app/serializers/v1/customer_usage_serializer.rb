# frozen_string_literal: true

module V1
  class CustomerUsageSerializer < ModelSerializer
    def serialize
      payload = {
        # TODO: remove || after all cache key expirations
        from_datetime: model.from_date&.beginning_of_day || model.from_datetime,
        to_datetime: model.to_date&.end_of_day || model.to_datetime,
        issuing_date: model.issuing_date,
        amount_cents: model.amount_cents,
        amount_currency: model.amount_currency,
        total_amount_cents: model.total_amount_cents,
        total_amount_currency: model.total_amount_currency,
        vat_amount_cents: model.vat_amount_cents,
        vat_amount_currency: model.vat_amount_currency,
      }.merge(legacy_values)

      payload.merge!(charges_usage) if include?(:charges_usage)
      payload
    end

    private

    def charges_usage
      ::CollectionSerializer.new(
        model.fees,
        ::V1::ChargeUsageSerializer,
        collection_name: 'charges_usage',
      ).serialize
    end

    def legacy_values
      ::V1::Legacy::CustomerUsageSerializer.new(model).serialize
    end
  end
end
