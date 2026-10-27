# frozen_string_literal: true

require "rails_helper"

RSpec.describe BaseService::ValidationFailure do
  subject(:failure) { described_class.new(result, messages:) }

  let(:result) { BaseResult.new }
  let(:messages) { {name: ["value_is_mandatory"], position: %w[value_is_out_of_range value_is_invalid]} }

  def entry(field, code, meta = {})
    described_class::Entry.new(field:, code:, meta:)
  end

  describe ".from_errors" do
    subject(:failure) { described_class.from_errors(result, record.errors) }

    let(:record) do
      build(:rate_card_rate).tap do |rate|
        rate.errors.add(:billing_interval_count, :greater_than_or_equal_to, count: 1, value: 0)
        rate.errors.add(:code, :blank)
        rate.errors.add(:billing_interval_count, :not_allowed_for_billing_timing, meta: {min: 1, max: 3})
        rate.errors.add(:rate_model, :not_allowed_for_product, meta: {allowed_values: %w[standard package]})
      end
    end

    it "keeps the messages of the record and the meta option of each error, grouped as messages are" do
      expect(failure.messages).to eq(
        billing_interval_count: %w[value_is_out_of_range not_allowed_for_billing_timing],
        code: %w[value_is_mandatory],
        rate_model: %w[not_allowed_for_product]
      )
      # count and value are options of the validator, not meta: value echoes the request.
      expect(failure.entries).to eq([
        entry(:billing_interval_count, "value_is_out_of_range"),
        entry(:billing_interval_count, "not_allowed_for_billing_timing", {min: 1, max: 3}),
        entry(:code, "value_is_mandatory"),
        entry(:rate_model, "not_allowed_for_product", {allowed_values: %w[standard package]})
      ])
      expect(failure.entries.group_by(&:field).transform_values { it.map(&:code) }).to eq(failure.messages)
    end

    it "keeps them once the record is validated again" do
      failure
      record.errors.clear

      expect(failure.messages.keys).to eq(%i[billing_interval_count code rate_model])
      expect(failure.entries.size).to eq(4)
    end

    context "with an error imported under another attribute" do
      let(:record) do
        build(:rate_card_rate).tap do |rate|
          error = ActiveModel::Error.new(rate, :billing_interval_count, :not_allowed_for_billing_timing, meta: {min: 1})
          rate.errors.import(error, attribute: :"rates.billing_interval_count")
        end
      end

      # Autosaved associations import their errors so, and re-keying a failure can do the same.
      it "keeps its meta under the new attribute" do
        expect(failure.messages).to eq("rates.billing_interval_count": ["not_allowed_for_billing_timing"])
        expect(failure.entries).to eq([entry(:"rates.billing_interval_count", "not_allowed_for_billing_timing", {min: 1})])
      end
    end
  end

  describe "#message" do
    it { expect(failure.message).to eq('Validation errors: {"name":["value_is_mandatory"],"position":["value_is_out_of_range","value_is_invalid"]}') }
  end

  describe "#entries" do
    it "returns one entry per code, in the order of messages, without meta" do
      expect(failure.entries).to eq([
        entry(:name, "value_is_mandatory"),
        entry(:position, "value_is_out_of_range"),
        entry(:position, "value_is_invalid")
      ])
      expect(failure.entries).to be_frozen
    end

    context "when fields have string and symbol keys" do
      let(:messages) { {"billing_interval_count" => ["value_is_out_of_range"], :name => ["value_is_mandatory"]} }

      it "keeps each field as given" do
        expect(failure.entries).to eq([entry("billing_interval_count", "value_is_out_of_range"), entry(:name, "value_is_mandatory")])
      end
    end

    context "when codes are symbols" do
      let(:messages) { {base: [:invalid_date]} }

      it { expect(failure.entries).to eq([entry(:base, :invalid_date)]) }
    end

    context "when messages is a String" do
      let(:messages) { "invalid_payload" }

      it { expect(failure.entries).to eq([]) }
    end

    context "with entries given" do
      subject(:failure) { described_class.new(result, messages: {position: ["value_is_out_of_range"]}, entries:) }

      let(:entries) { [entry(:position, "value_is_out_of_range", {min: 1, max: 3})] }

      it { expect(failure.entries).to eq(entries) }
    end
  end
end
