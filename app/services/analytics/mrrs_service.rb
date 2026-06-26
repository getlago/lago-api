# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Analytics
  class MrrsService < BaseService
    def call
      return result.forbidden_failure! unless License.premium?

      @records = ::Analytics::Mrr.find_all_by(organization.id, **filters)

      result.records = records
      result
    end
  end
end
