# frozen_string_literal: true

module V2
  # V1's fields plus deleted_at, without its zero counters, nor applied_to_organization: billing
  # entities no longer update that column, so it can contradict /api/v1/taxes, which reads the
  # default billing entity instead.
  class TaxSerializer < ModelSerializer
    def serialize
      {
        lago_id: model.id,
        name: model.name,
        code: model.code,
        rate: model.rate,
        description: model.description,
        created_at: model.created_at.iso8601,
        deleted_at: model.deleted_at&.iso8601
      }
    end
  end
end
