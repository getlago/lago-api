# frozen_string_literal: true

module V2
  class TaxSerializer < ModelSerializer
    ZERO_COUNTS = {
      add_ons_count: 0,
      customers_count: 0,
      plans_count: 0,
      charges_count: 0,
      commitments_count: 0
    }.freeze

    def serialize
      {
        lago_id: model.id,
        name: model.name,
        code: model.code,
        rate: model.rate,
        description: model.description,
        **v1_fields,
        created_at: model.created_at.iso8601,
        **deleted_at_payload
      }
    end

    private

    # Preserve the v1 shape only for internal callers such as activity logs.
    def v1_fields
      include?(:counts) ? {applied_to_organization: model.applied_to_organization, **ZERO_COUNTS} : {}
    end

    def deleted_at_payload
      include?(:deleted_at) ? {deleted_at: model.deleted_at&.iso8601} : {}
    end
  end
end
