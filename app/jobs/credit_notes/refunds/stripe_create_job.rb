# frozen_string_literal: true

module CreditNotes
  module Refunds
    class StripeCreateJob < ApplicationJob
      queue_as 'providers'

      def perform(credit_note)
        result = CreditNotes::Refunds::StripeService.new(credit_note).create
        result.throw_error unless result.success?
      end
    end
  end
end
