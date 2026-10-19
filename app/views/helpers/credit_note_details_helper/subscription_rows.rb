# frozen_string_literal: true

class CreditNoteDetailsHelper
  class SubscriptionRows
    FEE_TYPES = %i[subscription fixed_charge charge add_on].freeze

    def self.load(credit_note)
      items = credit_note.items
      return items.to_a.select { |item| item.fee.fee_type&.to_sym&.in?(FEE_TYPES) } unless items.respond_to?(:joins) && credit_note.persisted?

      base_items = items.joins(:fee)
        .where(credit_note_items: {organization_id: credit_note.organization_id}, fees: {fee_type: FEE_TYPES})
      FEE_TYPES.flat_map do |fee_type|
        type_items = base_items.where(fees: {fee_type:}).includes(fee: associations_for(fee_type)).to_a
        preload_optional_associations(type_items, fee_type)
        type_items
      end.sort_by { |item| [item.created_at, item.id] }
    end

    def self.associations_for(fee_type)
      case fee_type
      when :subscription then {subscription: :plan}
      when :fixed_charge then {fixed_charge: :add_on}
      when :charge then {charge: :billable_metric}
      when :add_on then :add_on
      end
    end

    private_class_method :associations_for

    def self.preload_optional_associations(items, fee_type)
      fees = items.map(&:fee)
      if fee_type == :charge
        filtered_fees = fees.select { |fee| fee.charge_filter_id.present? }
        ActiveRecord::Associations::Preloader.new(records: filtered_fees, associations: {charge_filter: {values: :billable_metric_filter}}).call if filtered_fees.any?
      elsif fee_type == :add_on
        children = fees.select { |fee| fee.true_up_parent_fee_id.present? }
        associations = {true_up_parent_fee: [:add_on, :invoiceable, {subscription: :plan}, {charge: :billable_metric}, {fixed_charge: :add_on}]}
        ActiveRecord::Associations::Preloader.new(records: children, associations:).call if children.any?
      end
    end
    private_class_method :preload_optional_associations
  end
end
