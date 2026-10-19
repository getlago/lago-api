# frozen_string_literal: true

class CreditNoteDetailsHelper
  class ContractRows
    def self.load(credit_note)
      items = credit_note.items
      return items.to_a.select { |item| item.fee.product? } unless items.respond_to?(:joins) && credit_note.persisted?

      items.joins(:fee)
        .where(credit_note_items: {organization_id: credit_note.organization_id}, fees: {fee_type: :product})
        .includes(fee: [:product_filter, :applied_taxes])
        .order(:created_at, :id)
        .to_a.tap do |product_items|
          fees_without_display_name = product_items.map(&:fee).select { |fee| fee.invoice_display_name.blank? }
          ActiveRecord::Associations::Preloader.new(records: fees_without_display_name, associations: :invoiceable).call if fees_without_display_name.any?
        end
    end
  end
end
