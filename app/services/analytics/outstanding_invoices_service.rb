# frozen_string_literal: true

module Analytics
  class OutstandingInvoicesService < BaseService
    def call
      return result.forbidden_failure! unless License.premium?

      @records = ::Analytics::OutstandingInvoice.find_all_by(organization.id, **filters)

      result.records = records
      result
    end
  end
end
