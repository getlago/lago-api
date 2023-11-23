# frozen_string_literal: true

module Analytics
  class FinalizedInvoicesService < BaseService
    def call
      return result.forbidden_failure! unless License.premium?

      @records = ::Analytics::FinalizedInvoice.find_all_by(organization.id, **filters)

      result.records = records
      result
    end
  end
end
