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

    def initialize(invoice:, billing_contexts:, billing_at:, metered_items: [], charge_fees_resolver: nil)
      @invoice = invoice
      @billing_contexts = billing_contexts
      @billing_at = billing_at
      @metered_items = metered_items
      @charge_fees_resolver = charge_fees_resolver

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

    attr_reader :invoice, :billing_contexts, :billing_at, :metered_items, :charge_fees_resolver

    def attach_charge_fees
      return unless RegroupingChargeService.call!(billing_contexts:).regrouping_charge

      charge_fees.find_each do |fee|
        fee.update_column(:invoice_id, invoice.id) # rubocop:disable Rails/SkipsModelValidations
      end
    end

    def charge_fees
      resolver = charge_fees_resolver || AdvanceChargesToDatetimeFilterResolver.new(billing_contexts:, billing_at:)

      resolver.call.where(subscription_id: billing_contexts.map(&:subscription_id))
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
