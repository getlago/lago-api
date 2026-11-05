# frozen_string_literal: true

module V2
  class EventSerializer < ModelSerializer
    timestamps :timestamp, :created_at, :updated_at, :deleted_at, :enriched_at

    def serialize
      payload = {
        transaction_id: model.transaction_id,
        external_contract_id: external_contract_id,
        code: model.code,
        precise_total_amount_cents: model.precise_total_amount_cents&.to_s,
        properties: model.properties
      }

      # Bulk ingestion assigns IDs without marking the instances as persisted.
      if model.has_attribute?(:id) && model.id.present?
        payload[:lago_id] = model.id
        payload[:lago_customer_id] = model.customer_id
      end

      if model.has_attribute?(:enriched_at)
        payload.merge!(value: model.value, decimal_value: model.decimal_value&.to_s, attribution_labels: model.attribution_labels || {})
      end

      payload
    end

    private

    def timestamps_payload
      super.select { |name, _| model.has_attribute?(name) && (name == :timestamp || model.id.present?) }
    end

    def external_contract_id
      if model.has_attribute?(:external_contract_id)
        model.external_contract_id
      else
        model.external_subscription_id
      end
    end

    def created_at
      stored_attribute(:created_at)
    end

    def enriched_at
      stored_attribute(:enriched_at)
    end

    def updated_at
      stored_attribute(:updated_at)
    end

    def deleted_at
      stored_attribute(:deleted_at)
    end

    def stored_attribute(name)
      model.public_send(name) if model.has_attribute?(name)
    end
  end
end
