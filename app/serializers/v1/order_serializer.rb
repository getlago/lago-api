# frozen_string_literal: true

module V1
  class OrderSerializer < ModelSerializer
    def serialize
      payload = {
        lago_id: model.id,
        number: model.number,
        status: model.status,
        order_type: model.order_type,
        execution_mode: model.execution_mode,
        currency: model.currency,
        executed_at: model.executed_at&.iso8601,
        execution_record:,
        lago_organization_id: model.organization_id,
        lago_customer_id: model.customer_id,
        lago_order_form_id: model.order_form_id,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601
      }

      # billing_snapshot is a heavy blob mirroring the quote version billing items:
      # render it for API responses, never in webhook payloads.
      payload[:billing_snapshot] = model.billing_snapshot if include?(:billing_snapshot)
      payload
    end

    private

    # A record written before a key existed carries no such key at all, so the shape is completed
    # here. Types::Orders::ExecutionRecord does the same for GraphQL.
    def execution_record
      Order::EXECUTION_RECORD_DEFAULTS.merge(model.execution_record || {})
    end
  end
end
