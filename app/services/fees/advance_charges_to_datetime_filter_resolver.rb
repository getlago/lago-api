# frozen_string_literal: true

module Fees
  class AdvanceChargesToDatetimeFilterResolver
    def initialize(billing_contexts:, billing_at:, customer: nil)
      @billing_contexts = billing_contexts
      @billing_at = billing_at
      @customer = customer
    end

    def call
      relation = Fee.where(invoice: nil, payment_status: :succeeded)
        .where("succeeded_at <= ?", billing_at)

      relation = if customer
        relation.joins(:subscription).where(subscriptions: {
          customer_id: customer.id,
          external_id: billing_contexts.map(&:external_id).uniq,
          status: [:active, :terminated]
        })
      else
        relation.where(subscription_id: billing_contexts.map(&:subscription_id))
      end

      # Upgrades, downgrades and terminations may invoice fees before their period ends.
      if regular_periodic_billing?
        relation.where(
          "(properties ->> 'charges_to_datetime') IS NULL OR (properties ->> 'charges_to_datetime')::timestamp <= ?",
          billing_at
        )
      else
        relation
      end
    end

    private

    attr_reader :billing_contexts, :billing_at, :customer

    def regular_periodic_billing?
      billing_contexts.all? do |context|
        context.active? && !context.terminated? && (!context.subscription? || context.next_subscription.nil?)
      end
    end
  end
end
