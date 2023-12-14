# frozen_string_literal: true

module Types
  module Invoices
    class StatusTypeEnum < Types::BaseEnum
      graphql_name 'InvoiceStatusTypeEnum'

      Invoice::STATUS.reject { |k| k == :generating }.each do |type|
        value type
      end
    end
  end
end
