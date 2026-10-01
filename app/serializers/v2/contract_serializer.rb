# frozen_string_literal: true

module V2
  # The agreement a customer signed: an optional plan (a plan-less contract
  # prices through directly attached rate cards), a validity window and the
  # billing anchor. There are no plan-interval fields — pricing lives on the
  # applied rate cards.
  class ContractSerializer < ModelSerializer
    EXPANDABLE_RELATIONS = {
      # One card per rate card the contract prices.
      applied_rate_cards: nil,
      plan: :catalog_plan,
      customer: {customer: :billing_entity},
      # Few per contract, chosen one by one through invoice_custom_section_codes.
      invoice_custom_sections: nil
    }.freeze

    def self.expandable_relations
      EXPANDABLE_RELATIONS
    end

    def serialize
      {
        lago_id: model.id,
        external_id: model.external_id,
        lago_customer_id: model.customer_id,
        external_customer_id: model.customer.external_id,
        name: model.name,
        plan_code: model.catalog_plan&.code,
        status: model.status,
        billing_time: model.billing_time,
        consolidate_invoice: model.consolidate_invoice,
        purchase_order_number: model.purchase_order_number,
        billing_anchor_date: model.billing_anchor_date&.iso8601,
        effective_billing_anchor_date: model.effective_billing_anchor_date&.iso8601,
        started_at: model.started_at&.iso8601,
        ended_at: model.ended_at&.iso8601,
        terminated_at: model.terminated_at&.iso8601,
        canceled_at: model.canceled_at&.iso8601,
        skip_invoice_custom_sections: model.skip_invoice_custom_sections,
        created_at: model.created_at.iso8601,
        updated_at: model.updated_at.iso8601,
        **expanded_payload
      }
    end

    private

    def expand(name)
      case name
      when :applied_rate_cards
        # In the order of /applied_rate_cards.
        model.applied_rate_cards.preload(:rate_card, :contract).order(::CursorPagination::DEFAULT_SORT).map do |applied_rate_card|
          ::V2::ContractAppliedRateCardSerializer.new(applied_rate_card, includes: nested_includes).serialize
        end
      when :plan
        # The plan and the customer are read with_discarded, so that a discarded one carries its deleted_at.
        model.catalog_plan&.then { ::V2::CatalogPlanSerializer.new(it, includes: nested_includes).serialize }
      when :customer
        ::V2::CustomerSerializer.new(model.customer, includes: nested_includes).serialize
      when :invoice_custom_sections
        # The selected sections, the last selected first. Their default scope leaves out a section
        # deleted while its link remains.
        model.selected_invoice_custom_sections
          .merge(::Contract::AppliedInvoiceCustomSection.order(::CursorPagination::DEFAULT_SORT))
          .map { ::V2::InvoiceCustomSectionSerializer.new(it, includes: nested_includes).serialize }
      else
        super
      end
    end
  end
end
