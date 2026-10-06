# frozen_string_literal: true

module Fees
  class AdvanceChargesToDatetimeFilterResolver
    PRODUCT_FEE_MATCH_ATTRIBUTES = %i[
      contract_id
      contract_rate_card_id
      invoiceable_type
      invoiceable_id
    ].freeze

    def initialize(billing_contexts:, billing_at:, metered_items: nil)
      @billing_contexts = billing_contexts
      @billing_at = billing_at
      @metered_items = metered_items
      @customer = billing_contexts.first&.customer
    end

    def call
      return product_fees if metered_items
      return Fee.none unless customer

      relation = Fee.joins(:subscription)
        .where(invoice: nil, payment_status: :succeeded)
        .where("succeeded_at <= ?", billing_at)
        .where(subscriptions: {
          customer_id: customer.id,
          external_id: billing_contexts.map(&:external_id).uniq,
          status: [:active, :terminated]
        })

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

    def metered_items_with_fees(fees)
      matched_attributes = fees.distinct.pluck(*PRODUCT_FEE_MATCH_ATTRIBUTES).to_set

      metered_items.select do |metered_item|
        matched_attributes.include?(product_fee_match_attributes(metered_item).values)
      end
    end

    private

    attr_reader :billing_contexts, :billing_at, :customer, :metered_items

    def product_fees
      return Fee.none if metered_items.empty?

      metered_items
        .map { |metered_item| product_fee_relation(metered_item) }
        .reduce { |relation, item_relation| relation.or(item_relation) }
        .where(invoice_id: nil, payment_status: :succeeded, pay_in_advance: true)
    end

    def product_fee_relation(metered_item)
      ended_at = metered_item.billing_segment.ended_at

      Fee.where(product_fee_match_attributes(metered_item))
        .where("succeeded_at <= ?", ended_at)
        .where("(properties ->> 'charges_to_datetime') IS NULL OR " \
          "(properties ->> 'charges_to_datetime')::timestamp <= ?", ended_at)
    end

    def product_fee_match_attributes(metered_item)
      billing_segment = metered_item.billing_segment

      {
        contract_id: billing_segment.contract_id,
        contract_rate_card_id: billing_segment.contract_rate_card_id,
        invoiceable_type: metered_item.invoiceable.class.polymorphic_name,
        invoiceable_id: metered_item.invoiceable.id
      }
    end

    def regular_periodic_billing?
      billing_contexts.all? do |context|
        context.active? && !context.terminated? && (!context.subscription? || context.next_subscription.nil?)
      end
    end
  end
end
