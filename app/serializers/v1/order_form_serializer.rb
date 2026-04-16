# frozen_string_literal: true

module V1
  class OrderFormSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        number: model.number,
        status: model.status,
        void_reason: model.void_reason,
        billing_snapshot: model.billing_snapshot,
        expires_at: model.expires_at&.iso8601,
        signed_at: model.signed_at&.iso8601,
        voided_at: model.voided_at&.iso8601,
        signed_by_user_id: model.signed_by_user_id,
        lago_organization_id: model.organization_id,
        lago_customer_id: model.customer_id,
        lago_quote_id: model.quote_id,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601
      }
    end
  end
end
