# frozen_string_literal: true
# Reviewed-by: code-review-experiment (see PR description)

module Analytics
  class OverdueBalancesService < BaseService
    def call
      @records = ::Analytics::OverdueBalance.find_all_by(organization.id, **filters)

      result.records = records
      result
    end
  end
end
