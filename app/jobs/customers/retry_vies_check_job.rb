# frozen_string_literal: true

module Customers
  class RetryViesCheckJob < ApplicationJob
    queue_as :default
    sidekiq_options retry: 11

    sidekiq_retry_in do |count|
      # 11st retry: 17 hours
      # 12nd retry: 1 day
      [1.minute * (2**count), 1.day].min
    end

    def perform(customer_id)
      customer = Customer.find(customer_id)
      return if customer.tax_identification_number.blank?

      # Re-run the EU auto taxes service
      tax_code = Customers::EuAutoTaxesService.call!(
        customer: customer,
        new_record: false,
        tax_attributes_changed: true
      ).tax_code

      # If successful, apply the tax code
      if tax_code.present?
        Customers::ApplyTaxesService.call(
          customer: customer,
          tax_codes: [tax_code]
        )
      end
    end
  end
end
