# frozen_string_literal: true

require "rails_helper"

RSpec.describe BaseService::ValidationFailure do
  subject(:failure) { described_class.new(result, messages:, meta:) }

  let(:result) { BaseResult.new }
  let(:messages) { {position: ["value_is_out_of_range"]} }
  let(:meta) { {position: [{min: 1, max: 3}]} }

  describe "#meta" do
    let(:messages) { {name: ["value_is_mandatory"], position: ["value_is_out_of_range", "value_is_invalid"]} }
    let(:meta) { {name: [{}], position: [{"min" => 1, "max" => 3}]} }

    it "is aligned with the codes and frozen" do
      expect(failure.meta).to eq({position: [{min: 1, max: 3}, {}]})
      expect(failure.meta).to be_frozen
      expect(failure.meta[:position]).to be_frozen
      expect(failure.meta[:position]).to all(be_frozen)
    end

    context "without meta" do
      subject(:failure) { described_class.new(result, messages:) }

      it "is an empty frozen hash" do
        expect(failure.meta).to eq({})
        expect(failure.meta).to be_frozen
      end
    end

    context "when messages has indifferent access" do
      let(:messages) { {position: ["value_is_out_of_range"]}.with_indifferent_access }
      let(:meta) { {position: [{min: 1}]} }

      # Its keys are Strings, under which entries would not find a meta stored under a Symbol.
      it { expect { failure }.to raise_error(ArgumentError, "meta of :position does not match its codes") }
    end
  end

  describe "#message" do
    it { expect(failure.message).to eq('Validation errors: {"position":["value_is_out_of_range"]}') }

    context "without meta" do
      subject(:failure) { described_class.new(result, messages:) }

      it { expect(failure.message).to eq('Validation errors: {"position":["value_is_out_of_range"]}') }
    end
  end

  describe "#entries" do
    let(:messages) { {name: ["value_is_mandatory"], position: ["value_is_out_of_range", "value_is_invalid"]} }

    it "returns one entry per code, in the order of messages" do
      expect(failure.entries).to eq([
        described_class::Entry.new(field: :name, code: "value_is_mandatory", meta: {}),
        described_class::Entry.new(field: :position, code: "value_is_out_of_range", meta: {min: 1, max: 3}),
        described_class::Entry.new(field: :position, code: "value_is_invalid", meta: {})
      ])
      expect(failure.entries.map(&:meta)).to all(be_frozen)
    end

    context "when a field has the same code twice" do
      let(:messages) { {graduated_ranges: ["invalid_graduated_ranges", "invalid_graduated_ranges"]} }
      let(:meta) { {graduated_ranges: [{min: 0}, {min: 101}]} }

      it "keeps each code with its own meta" do
        expect(failure.entries).to eq([
          described_class::Entry.new(field: :graduated_ranges, code: "invalid_graduated_ranges", meta: {min: 0}),
          described_class::Entry.new(field: :graduated_ranges, code: "invalid_graduated_ranges", meta: {min: 101})
        ])
      end
    end

    context "when fields have string and symbol keys" do
      let(:messages) { {"billing_interval_count" => ["value_is_out_of_range"], :name => ["value_is_mandatory"]} }
      let(:meta) { {"billing_interval_count" => [{min: 1}]} }

      it "keeps each field as given" do
        expect(failure.entries).to eq([
          described_class::Entry.new(field: "billing_interval_count", code: "value_is_out_of_range", meta: {min: 1}),
          described_class::Entry.new(field: :name, code: "value_is_mandatory", meta: {})
        ])
      end
    end

    context "when codes are symbols" do
      let(:messages) { {base: [:invalid_date]} }
      let(:meta) { {} }

      it "keeps each code as given" do
        expect(failure.entries).to eq([described_class::Entry.new(field: :base, code: :invalid_date, meta: {})])
      end
    end

    context "when messages is a String" do
      let(:messages) { "invalid_payload" }
      let(:meta) { {} }

      it { expect(failure.entries).to eq([]) }
    end
  end

  describe "#==" do
    let(:other) { described_class.new(result, messages:, meta: other_meta) }
    let(:other_meta) { {position: [{min: 1, max: 3}]} }

    it { expect(failure).to eq(other) }

    context "when only the meta differs" do
      let(:other_meta) { {position: [{min: 0, max: 3}]} }

      it { expect(failure).not_to eq(other) }
    end

    context "when the messages differ" do
      let(:other) { described_class.new(result, messages: {position: ["value_is_invalid"]}, meta: other_meta) }

      it { expect(failure).not_to eq(other) }
    end

    context "when both are raised" do
      # Raised from the same frames, so their backtraces, which Exception#== compares, are equal.
      let(:raised) do
        [failure, other].map do |error|
          raise error
        rescue described_class => e
          e
        end
      end

      it { expect(raised.first).to eq(raised.last) }

      context "when only the meta differs" do
        let(:other_meta) { {position: [{min: 0, max: 3}]} }

        it { expect(raised.first).not_to eq(raised.last) }
      end
    end
  end
end
