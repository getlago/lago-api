# frozen_string_literal: true

module Invoices
  class RefreshSearchTermsService < BaseService
    Result = BaseResult[:invoice]

    def initialize(invoice:)
      @invoice = invoice

      super
    end

    def call
      return result.not_found_failure!(resource: "invoice") if invoice.nil?

      Invoice.where(id: invoice.id).update_all("search_terms = #{Invoice::SearchTerms::SQL}") # rubocop:disable Rails/SkipsModelValidations

      result.invoice = invoice
      result
    end

    private

    attr_reader :invoice
  end
end
