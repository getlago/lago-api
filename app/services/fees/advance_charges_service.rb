# frozen_string_literal: true

module Fees
  class AdvanceChargesService < BaseService
    Result = BaseResult[:invoiced_metered_items]

    FEE_MATCH_ATTRIBUTE_NAMES = %i[
      contract_id
      contract_rate_card_id
      invoiceable_type
      invoiceable_id
    ].freeze

    def initialize(invoice:, billing_contexts:, billing_at:, metered_items: [])
      @invoice = invoice
      @billing_contexts = billing_contexts
      @billing_at = billing_at
      @metered_items = metered_items

      super
    end

    def call
      result.invoiced_metered_items = []

      if metered_items.empty?
        attach_charge_fees
      else
        attach_product_fees
      end

      result
    end

    private

    attr_reader :invoice, :billing_contexts, :billing_at, :metered_items

    def attach_charge_fees
      return unless regrouping_charge?

      charge_fees.find_each do |fee|
        fee.update_column(:invoice_id, invoice.id) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    def charge_fees
      Fee.where(subscription_id: billing_contexts.map(&:subscription_id))
        .where(invoice: nil, payment_status: :succeeded)
        .where("succeeded_at <= ?", billing_at)
        .then { |relation| filter_charges_to_datetime(relation) }
    end

    def regrouping_charge?
      Charge.where(
        plan_id: billing_contexts.filter_map(&:plan_id).uniq,
        pay_in_advance: true,
        invoiceable: false,
        regroup_paid_fees: :invoice
      ).any?
    end

    def filter_charges_to_datetime(relation)
      return relation unless apply_charges_to_datetime_condition?

      relation.where(
        "(properties ->> 'charges_to_datetime') IS NULL OR (properties ->> 'charges_to_datetime')::timestamp <= ?",
        billing_at
      )
    end

    def apply_charges_to_datetime_condition?
      return true if metered_items.any?

      billing_contexts.all? do |billing_context|
        billing_context.active? && billing_context.next_subscription.nil? && !billing_context.terminated?
      end
    end

    def attach_product_fees
      regrouped_metered_items = metered_items.select(&:regroup_paid_fees_invoice?)
      return if regrouped_metered_items.empty?

      fees = eligible_product_fees(regrouped_metered_items)
      matched_attributes = fees.distinct.pluck(*FEE_MATCH_ATTRIBUTE_NAMES).to_set

      fees.update_all(invoice_id: invoice.id) # rubocop:disable Rails/SkipsModelValidations
      result.invoiced_metered_items = regrouped_metered_items.select do |metered_item|
        matched_attributes.include?(fee_match_attributes(metered_item).values)
      end
    end

    def eligible_product_fees(regrouped_metered_items)
      regrouped_metered_items
        .map { |metered_item| product_fee_relation(metered_item) }
        .reduce { |relation, item_relation| relation.or(item_relation) }
        .where(
          invoice_id: nil,
          payment_status: :succeeded,
          pay_in_advance: true
        )
        .then { |relation| filter_charges_to_datetime(relation) }
    end

    def product_fee_relation(metered_item)
      Fee.where(fee_match_attributes(metered_item))
        .where("succeeded_at <= ?", metered_item.billing_segment.billing_at)
    end

    def fee_match_attributes(metered_item)
      billing_segment = metered_item.billing_segment

      {
        contract_id: billing_segment.contract_id,
        contract_rate_card_id: billing_segment.contract_rate_card_id,
        invoiceable_type: metered_item.invoiceable.class.polymorphic_name,
        invoiceable_id: metered_item.invoiceable.id
      }
    end
  end
end
