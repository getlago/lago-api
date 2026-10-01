# frozen_string_literal: true

module V2
  class TaxSerializer < ModelSerializer
    # The zeros V1 has always rendered, for the rate card activity log: its taxes must keep
    # the V1 shape.
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

    # In V1's key order. applied_to_organization stays V1 only: billing entities no longer update
    # it, so it can contradict /api/v1/taxes, which reads the default billing entity instead.
    def v1_fields
      include?(:counts) ? {applied_to_organization: model.applied_to_organization, **ZERO_COUNTS} : {}
    end
  end
end
