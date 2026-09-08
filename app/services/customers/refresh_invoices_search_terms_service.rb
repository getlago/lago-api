# frozen_string_literal: true

module Customers
  class RefreshInvoicesSearchTermsService < BaseService
    Result = BaseResult[:customer]

    BATCH_SIZE = 1_000

    def initialize(customer:)
      @customer = customer

      super
    end

    def call
      return result.not_found_failure!(resource: "customer") if customer.nil?

      customer.invoices.in_batches(of: BATCH_SIZE) do |batch|
        batch.update_all("search_terms = #{Invoice::SearchTerms::SQL}") # rubocop:disable Rails/SkipsModelValidations
      end

      result.customer = customer
      result
    end

    private

    attr_reader :customer
  end
end
