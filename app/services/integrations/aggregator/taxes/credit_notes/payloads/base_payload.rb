# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      module CreditNotes
        module Payloads
          class BasePayload < Integrations::Aggregator::BasePayload
            private

            # NOTE: A charge split by charge filters or by grouped_by is credited through one item
            #       per fee, so a single charge could take dozens of the 1200 line items both
            #       providers accept.
            def charge_grouped_items
              ChargeGroup.by_charge(credit_note.items.order(created_at: :asc)) do |item|
                item.fee.charge_id if item.fee.charge?
              end
            end

            # NOTE: Fee#item_id is the billable metric for a charge fee, so two charges over the
            #       same metric would share one identifier within a payload.
            def cn_item_id(items)
              fee = items.first.fee

              fee.charge? ? ChargeGroup.key(fee.charge_id) : fee.item_id
            end

            def mapped_item(fee)
              if fee.charge?
                billable_metric_item(fee)
              elsif fee.add_on_id.present?
                add_on_item(fee)
              elsif fee.fixed_charge?
                fixed_charge_item(fee)
              elsif fee.commitment?
                commitment_item
              elsif fee.subscription?
                subscription_item
              end
            end
          end
        end
      end
    end
  end
end
