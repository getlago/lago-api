# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Analytics
  class GrossRevenuesService < BaseService
    def call
      @records = ::Analytics::GrossRevenue.find_all_by(organization.id, **filters)

      result.records = records
      result
    end
  end
end
