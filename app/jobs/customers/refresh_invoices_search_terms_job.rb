# frozen_string_literal: true

module Customers
  class RefreshInvoicesSearchTermsJob < ApplicationJob
    queue_as "default"
    unique :until_executing, on_conflict: :log

    def perform(customer_id)
      customer = Customer.with_discarded.find_by(id: customer_id)
      return if customer.nil?

      Customers::RefreshInvoicesSearchTermsService.call!(customer:)
    end
  end
end
