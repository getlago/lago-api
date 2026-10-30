# frozen_string_literal: true

require "rails_helper"

RSpec.describe BaseService::ValidationFailure do
  subject(:failure) { described_class.new(result, messages:, meta:) }

  let(:result) { BaseResult.new }
  let(:messages) { {name: ["value_is_mandatory"], position: %w[value_is_out_of_range value_is_invalid]} }
  let(:meta) { {position: {min: 1, max: 3}} }

  describe ".from_errors" do
    subject(:failure) { described_class.from_errors(result, record.errors) }

    let(:record) do
      build(:customer, name: "a" * 256, net_payment_term: -1).tap(&:valid?).tap do |customer|
        customer.errors.add(:legal_name, :too_short, count: 2)
        customer.errors.add(:legal_name, :invalid)
        customer.errors.add(:city, :less_than_or_equal_to, count: 10)
        customer.errors.add(:state, :greater_than, count: 0)
        customer.errors.add(:firstname, :greater_than_or_equal_to, count: BigDecimal("0.5"))
      end
    end

    # An exclusive or decimal bound has no key.
    it "keeps the messages of the record and derives the inclusive Integer bounds of each field" do
      expect(failure.messages).to eq(record.errors.messages)
      expect(failure.meta).to eq(name: {max_length: 255}, net_payment_term: {min: 0}, legal_name: {min_length: 2}, city: {max: 10})
    end

    it "keeps them once the record is validated again" do
      failure
      record.errors.clear

      expect(failure.messages.keys).to eq(%i[name net_payment_term legal_name city state firstname])
      expect(failure.meta.keys).to eq(%i[name net_payment_term legal_name city])
    end

    context "when the length validator counts the elements of a list" do
      let(:record) { build(:usage_attribution_type, attribution_keys: %w[a b c d e]).tap(&:valid?) }

      it "derives no length bound" do
        expect(failure.messages[:attribution_keys]).to eq(["value_is_too_long"])
        expect(failure.meta).not_to have_key(:attribution_keys)
      end
    end

    context "with errors imported under other attributes" do
      let(:record) do
        build(:rate_card_rate).tap do |rate|
          rate.errors.import(ActiveModel::Error.new(rate, :billing_interval_count, :greater_than_or_equal_to, count: 1), attribute: :"rates.billing_interval_count")
          rate.errors.import(ActiveModel::Error.new(rate, :code, :too_long, count: 255), attribute: :"rates.code")
        end
      end

      # Autosaved associations import the errors of their records so. The record has no such attribute
      # to read, so a length bound is kept.
      it "keeps their bounds under the new attributes" do
        expect(failure.messages).to eq("rates.billing_interval_count": ["value_is_out_of_range"], "rates.code": ["value_is_too_long"])
        expect(failure.meta).to eq("rates.billing_interval_count": {min: 1}, "rates.code": {max_length: 255})
      end
    end
  end

  describe "#remap" do
    subject(:remapped) { failure.remap(other_result) { :"rates.#{it}" } }

    let(:other_result) { BaseResult.new }

    it "renames the fields of the messages and the meta, on the result given" do
      expect(remapped.result).to eq(other_result)
      expect(remapped.messages).to eq("rates.name": ["value_is_mandatory"], "rates.position": %w[value_is_out_of_range value_is_invalid])
      expect(remapped.meta).to eq("rates.position": {min: 1, max: 3})
    end
  end
end
