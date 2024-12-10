# frozen_string_literal: true

module PaymentProviders
  class CreatePaymentFactory
    def self.new_instance(provider:, invoice:)
      service_class(provider:).new(invoice)
    end

    def self.service_class(provider:)
      # TODO(payment): refactor Invoices::Payments::*Service#call
      #                into PaymentProviders::*::Payments::CreateService#call
      case provider.to_sym
      when :adyen
        Invoices::Payments::AdyenService
      when :gocardless
        Invoices::Payments::GocardlessService
      when :stripe
        Invoices::Payments::StripeService
      end
    end
  end
end
