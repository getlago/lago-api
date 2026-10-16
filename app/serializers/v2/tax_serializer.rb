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
        applied_to_organization: model.applied_to_organization,
        **counts,
        created_at: model.created_at.iso8601,
        **deleted_at_payload
      }
    end

    private

    def counts = include?(:counts) ? ZERO_COUNTS : {}
  end
end
