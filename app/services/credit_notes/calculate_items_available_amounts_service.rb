# frozen_string_literal: true

module CreditNotes
  class CalculateItemsAvailableAmountsService < BaseService
    def initialize(credit_note:)
      @credit_note = credit_note

      super
    end

    def call
      if credit_note_is_not_applied?
        result.available_amounts = initial_items_amounts
        return result
      end

      clear_items_available_amounts = calculate_items_sum_without_taxes
      result.available_amounts = split_sum_into_items(clear_items_available_amounts)
      result
    end

    private

    attr_reader :credit_note

    def credit_note_is_not_applied?
      credit_note.balance_amount_cents == credit_note.credit_amount_cents
    end

    def initial_items_amounts
      credit_note.items.map { |item| [item.id, item.amount_cents] }.to_h
    end

    # balance_amount_cents includes items_sum + their taxes,
    # but taxes_rate is the percentage, not decimal
    def calculate_items_sum_without_taxes
      (credit_note.balance_amount_cents / (100 + credit_note.taxes_rate)) * 100
    end

    def split_sum_into_items(clear_items_available_amounts)
      item_values = {}
      credit_note.items.each do |item|
        item_weight = item.amount_cents / credit_note_original_amount_without_taxes.to_f
        item_values[item.id] = item_weight * clear_items_available_amounts
      end
      item_values
    end

    def credit_note_original_amount_without_taxes
      @credit_note_original_amount_without_taxes ||= credit_note.credit_amount_cents - credit_note.taxes_amount_cents
    end
  end
end
