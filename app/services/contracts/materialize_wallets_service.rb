# frozen_string_literal: true

module Contracts
  # Gives the contract its own copy of its plan's wallet templates, with their scope, taxes, metadata and credit
  # allocation rules. A template stays editable once contracted, so the copy is what keeps a later edit away.
  class MaterializeWalletsService < BaseService
    Result = BaseResult[:wallets]

    WALLET_ATTRIBUTES = %w[
      code name invoice_display_name currency tax_application priority top_up_min_amount_cents top_up_max_amount_cents
    ].freeze
    SELECTOR_ATTRIBUTES = %w[
      selector_type fee_type product_category_id product_id product_filter_id with_product_filters
    ].freeze
    CREDIT_ALLOCATION_ATTRIBUTES = %w[
      code trigger product_id product_filter_id billing_cycles threshold_amount_cents credit_amount_cents
      purchase_amount_cents priority invoice_requires_successful_payment
    ].freeze

    def initialize(contract:)
      @contract = contract
      super
    end

    def call
      return result unless contract.catalog_plan

      wallets = []
      ActiveRecord::Base.transaction do
        # A template edit holds its row lock: the copy waits for it, so it never mixes two versions of a template.
        templates = contract.catalog_plan.wallets.lock("FOR SHARE")
        templates.includes(:selectors, :applied_taxes, :credit_allocations, :metadata).find_each do |plan_wallet|
          wallets << copy(plan_wallet)
        end
      end

      result.wallets = wallets
      result
    end

    private

    attr_reader :contract

    delegate :organization, to: :contract

    def copy(plan_wallet)
      wallet = contract.wallets.create!(
        organization:,
        customer: contract.customer,
        **plan_wallet.attributes.slice(*WALLET_ATTRIBUTES)
      )

      plan_wallet.selectors.each do |selector|
        wallet.selectors.create!(organization:, **selector.attributes.slice(*SELECTOR_ATTRIBUTES))
      end
      plan_wallet.applied_taxes.each do |applied_tax|
        wallet.applied_taxes.create!(organization:, tax_id: applied_tax.tax_id)
      end
      plan_wallet.credit_allocations.each do |allocation|
        wallet.credit_allocations.create!(organization:, **allocation.attributes.slice(*CREDIT_ALLOCATION_ATTRIBUTES))
      end
      wallet.create_metadata!(organization:, value: plan_wallet.metadata.value) if plan_wallet.metadata

      wallet
    end
  end
end
