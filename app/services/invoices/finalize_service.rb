# frozen_string_literal: true

module Invoices
  class FinalizeService < BaseService
    def initialize(invoice:)
      @invoice = invoice
      super
    end

    def call
      return result.not_found_failure!(resource: "invoice") if invoice.nil?

      if invoice.finalized?
        result.invoice = invoice
        return result
      end

      ActiveRecord::Base.transaction do
        invoice.status = :finalized
        invoice.save!

        CustomerSnapshots::CreateService.call!(invoice: invoice)
      end

      result.invoice = invoice
      result
    rescue ActiveRecord::RecordInvalid => e
      result.record_validation_failure!(record: e.record)
    end

    private

    attr_reader :invoice
  end
end
