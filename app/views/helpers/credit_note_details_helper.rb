# frozen_string_literal: true

class CreditNoteDetailsHelper
  Row = Data.define(:label, :tax_html, :formatted_amount, :label_width)

  def initialize(credit_note)
    @credit_note = credit_note
  end

  def rows
    return [] if credit_note.invoice.credit?

    contract_items = ContractRows.load(credit_note)
    subscription_items = SubscriptionRows.load(credit_note)
    metered_rows(contract_items) + subscription_rows(subscription_items)
  end

  def self.metered_source_id(fee)
    if fee.charge?
      fee.charge_id
    elsif fee.product?
      fee.contract_rate_card_id
    end
  end

  def self.metered_filter_id(fee)
    if fee.charge?
      fee.charge_filter_id
    elsif fee.product?
      fee.product_filter_id
    end
  end

  def self.credit_note_metered_group_key(fee)
    source_id = if fee.product? && fee.true_up_parent_fee_id.present?
      [:standalone_true_up, fee.item_key]
    else
      metered_source_id(fee) || fee.item_key
    end

    [fee.fee_type, source_id]
  end

  private

  attr_reader :credit_note

  def subscription_rows(items)
    items.group_by { |item| item.fee.subscription_id }.values.flat_map do |bucket|
      if bucket.first.fee.subscription_id.nil?
        add_on_rows(bucket)
      else
        subscription_bucket_rows(bucket)
      end
    end
  end

  def subscription_bucket_rows(items)
    rows = []
    subscription_item = items.find { |item| item.fee.subscription? }
    if subscription_item&.amount&.positive?
      label = "#{I18n.t("credit_note.subscription")} - #{subscription_item.fee.subscription.invoice_name}"
      rows << row(subscription_item, label, "60%")
    end
    items.select { |item| item.fee.fixed_charge? }.each do |item|
      rows << row(item, item.fee.invoice_name + FeeDisplayHelper.grouped_by_display(item.fee), "60%")
    end
    rows.concat(metered_rows(items.select { |item| item.fee.charge? }))
    rows
  end

  def add_on_rows(items)
    items.select { |item| item.fee.add_on? }.map do |item|
      label = if item.fee.true_up_parent_fee_id.present?
        I18n.t("invoice.true_up_metric", metric: item.fee.true_up_parent_fee.invoice_name)
      else
        item.fee.invoice_name
      end
      row(item, label)
    end
  end

  def metered_rows(items)
    rows = []
    shown_true_up_ids = []
    metered_parent_items(items).group_by { |item| CreditNoteDetailsHelper.credit_note_metered_group_key(item.fee) }.each_value do |group|
      filtered = group.all? { |item| CreditNoteDetailsHelper.metered_filter_id(item.fee).present? }
      displayed = []
      # Product fees can represent distinct billed segments; subscription charges retain their legacy aggregate display.
      displayed_items = if group.first.fee.product? || filtered
        group
      else
        group.first(1)
      end

      displayed_items.each do |item|
        displayed << item
        fee = item.fee
        label = fee.invoice_name
        label += FeeDisplayHelper.grouped_by_display(fee)
        filter_name = fee.filter_display_name(separator: " • ") if filtered
        label += " • #{filter_name}" if filter_name.present?
        rows << row(item, label, filtered ? nil : "60%")
      end

      displayed.each do |parent_item|
        items.select { |item| item.fee.true_up_parent_fee_id == parent_item.fee.id }.each do |child_item|
          next if shown_true_up_ids.include?(child_item.fee.id)

          shown_true_up_ids << child_item.fee.id
          label = I18n.t("invoice.true_up_metric", metric: child_item.fee.invoice_name)
          rows << row(child_item, label, "60%")
        end
      end
    end
    rows
  end

  def metered_parent_items(items)
    credited_fee_ids = items.map { |item| item.fee.id }.to_set
    items.select do |item|
      item.fee.true_up_parent_fee_id.nil? ||
        (item.fee.product? && !credited_fee_ids.include?(item.fee.true_up_parent_fee_id))
    end
  end

  def row(item, label, label_width = nil)
    Row.new(label:, tax_html: TaxHelper.applied_taxes(item),
      formatted_amount: MoneyHelper.format(item.amount), label_width:)
  end
end
