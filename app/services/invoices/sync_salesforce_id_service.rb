# frozen_string_literal: true

module Invoices
  class SyncSalesforceIdService < BaseService
    def initialize(invoice:, params:)
      @invoice = invoice
      @params = params
      super
    end

    def call
      return result.not_found_failure!(resource: 'invoice') if invoice.nil?
      return result.not_found_failure!(resource: 'integration') unless integration

      result.invoice = invoice
      result
    end

    private

    attr_reader :invoice, :params

    def integration
      type = Integrations::BaseIntegration.integration_type("salesforce")
      return @integration if defined?(@integration) && @integration&.type == type
      code = params[:integration_code]
      @integration = Integrations::BaseIntegration.find_by(type:, code:, organization: invoice.organization)
    end
  end
end
