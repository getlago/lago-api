# frozen_string_literal: true

module Commitments
  class DatesService < BaseService
    def self.new_instance(commitment:, invoice_subscription:)
      klass = if invoice_subscription.subscription.plan.pay_in_advance?
        Commitments::Minimum::InAdvance::DatesService
      else
        Commitments::Minimum::InArrears::DatesService
      end

      klass.new(commitment:, invoice_subscription:)
    end

    def initialize(commitment:, invoice_subscription:)
      @commitment = commitment
      @invoice_subscription = invoice_subscription

      super
    end

    def call
      raise NotImplementedError
    end

    private

    attr_reader :commitment, :invoice_subscription
  end
end
