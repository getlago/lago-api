# frozen_string_literal: true

module Invoices
  class VoidService < BaseService
    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      return result.not_found_failure!(resource: 'invoice') if invoice.nil?

      result.invoice = invoice

      begin
        invoice.void!
      rescue AASM::InvalidTransition => _e
        return result.not_allowed_failure!(code: 'not_voidable')
      end

      result
    end

    private

    attr_reader :invoice
  end
end
