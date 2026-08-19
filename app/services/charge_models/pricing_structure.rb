# frozen_string_literal: true

module ChargeModels
  PricingStructure = Data.define(
    :charge_model,
    :properties,
    :prorated,
    :accepts_target_wallet,
    :currency
  ) do
    def initialize(charge_model:, properties:, prorated:, accepts_target_wallet:, currency:)
      if currency.nil?
        raise ArgumentError, "currency is mandatory"
      end

      super
    end

    def with(**changes)
      self.class.new(**to_h.merge(changes))
    end

    def self.from_charge(charge)
      unless charge.is_a?(Charge)
        raise NotImplementedError, "Chargeable: #{charge.class.name} is not implemented"
      end

      new(
        charge_model: charge.charge_model,
        properties: charge.properties,
        prorated: charge.prorated?,
        accepts_target_wallet: charge.accepts_target_wallet,
        currency: Money::Currency.new(charge.plan.amount_currency)
      )
    end

    def self.from_billing_cycle(billing_cycle)
      unless billing_cycle.is_a?(BillingCycle)
        raise NotImplementedError, "Chargeable: #{billing_cycle.class.name} is not implemented"
      end

      new(
        charge_model: billing_cycle.rate.rate_model,
        properties: billing_cycle.rate_properties,
        prorated: billing_cycle.subscription_rate_card.proration?,
        accepts_target_wallet: false,
        currency: Money::Currency.new(billing_cycle.currency)
      )
    end

    def self.from_fixed_charge(fixed_charge)
      unless fixed_charge.is_a?(FixedCharge)
        raise NotImplementedError, "Chargeable: #{fixed_charge.class.name} is not implemented"
      end

      new(
        charge_model: fixed_charge.charge_model,
        properties: fixed_charge.properties,
        prorated: fixed_charge.prorated?,
        accepts_target_wallet: false,
        currency: Money::Currency.new(fixed_charge.plan.amount_currency)
      )
    end

    def self.from_billing_cycle(billing_cycle)
      unless billing_cycle.is_a?(BillingCycle)
        raise NotImplementedError, "Chargeable: #{billing_cycle.class.name} is not implemented"
      end

      new(
        charge_model: billing_cycle.rate.rate_model,
        properties: billing_cycle.rate_properties,
        prorated: billing_cycle.subscription_rate_card.proration?,
        accepts_target_wallet: false,
        currency: Money::Currency.new(billing_cycle.currency)
      )
    end
  end
end
