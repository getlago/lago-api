# frozen_string_literal: true

module Invoices
  module ProviderTaxes
    class PullTaxesAndApplyJob < ApplicationJob
      queue_as "providers"

      retry_on BaseService::ThrottlingError, wait: :polynomially_longer, attempts: 25
      retry_on LagoHttpClient::HttpError, wait: :polynomially_longer, attempts: 6
      retry_on OpenSSL::SSL::SSLError, wait: :polynomially_longer, attempts: 6
      retry_on Net::ReadTimeout, wait: :polynomially_longer, attempts: 6
      retry_on Net::OpenTimeout, wait: :polynomially_longer, attempts: 6

      def perform(invoice:)
        Invoices::ProviderTaxes::PullTaxesAndApplyService.call!(invoice:)
      end
    end
  end
end
