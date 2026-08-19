# frozen_string_literal: true

module Orders
  module OneOff
    class ExecuteService < Orders::BaseExecuteService
      private

      def create_records
        {invoice_id: bill_one_off&.id}
      end

      def bill_one_off
        Invoices::CreateOneOffService.call!(
          customer: order.customer,
          currency: order.currency,
          # Nil leaves CreateOneOffService falling back to the customer's own entity, which is what a
          # deal naming none asks for.
          billing_entity_id: order.quote_version.billing_entity_id,
          fees: build_fees,
          timestamp: Time.current.to_i,
          with_discarded_add_ons: true
        ).invoice
      end

      # Both add-on identifiers are sent because the billing services pick the one matching the
      # source that triggered the execution: the code under api, the id otherwise. An execution
      # replays the same snapshot whichever transport started it.
      def build_fees
        add_on_items.map do |item|
          {
            add_on_id: item["id"],
            add_on_code: item.dig("payload", "code"),
            units: effective_value(item, "units"),
            unit_amount_cents: effective_value(item, "unitAmountCents"),
            invoice_display_name: effective_value(item, "invoiceDisplayName"),
            # Description may ride in either section (the payload is free-form); overrides win.
            # When neither carries one, the fee falls back to the add-on description in
            # Fees::OneOffService.
            description: effective_value(item, "description"),
            from_datetime: effective_value(item, "fromDatetime"),
            to_datetime: effective_value(item, "toDatetime")
          }
        end
      end

      def add_on_items
        Array(billing_items["addOns"])
      end
    end
  end
end
