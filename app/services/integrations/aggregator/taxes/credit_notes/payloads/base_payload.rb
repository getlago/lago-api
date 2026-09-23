# frozen_string_literal: true

module Integrations
  module Aggregator
    module Taxes
      module CreditNotes
        module Payloads
          class BasePayload < Integrations::Aggregator::Taxes::BasePayload
            private

            # NOTE: A charge split by charge filters or by grouped_by is credited through one item
            #       per fee, so a single charge could take dozens of the 1200 line items both
            #       providers accept.
            def charge_grouped_items
              ChargeGroup.by_charge(credit_note.items.order(created_at: :asc, id: :asc)) do |item|
                item.fee.charge_id if item.fee.charge?
              end
            end

            # NOTE: Fee#item_id is the billable metric for a charge fee, so two charges over the
            #       same metric would share one identifier within a payload.
            #       Singleton credits also use charge_id, including partial credits of a
            #       grouped charge. This intentionally changes their previous metric ID.
            def cn_item_id(items)
              fee = items.first.fee

              fee.charge? ? fee.charge_id : fee.item_id
            end
          end
        end
      end
    end
  end
end
