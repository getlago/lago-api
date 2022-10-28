# frozen_string_literal: true

module Invoices
  module Payments
    class GocardlessCreateJob < ApplicationJob
      queue_as 'providers'

      def perform(invoice)
        result = Invoices::Payments::GocardlessService.new(invoice).create
        result.throw_error unless result.success?
      end
    end
  end
end
