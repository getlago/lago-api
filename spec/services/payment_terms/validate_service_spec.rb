# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentTerms::ValidateService do
  subject(:validate_service) { described_class.new(result, payment_term:) }

  let(:result) { BaseResult.new }

  describe "#valid?" do
    context "when payment_term is not provided" do
      let(:payment_term) { nil }

      it "returns true" do
        expect(validate_service).to be_valid
      end
    end

    context "with a valid term of each type" do
      [
        {term_type: "due_on_receipt"},
        {term_type: "net", days: 30},
        {term_type: "net", days: 0},
        {term_type: "end_of_month"},
        {term_type: "net_end_of_month", days: 30},
        {term_type: "days_end_of_month", days: 30},
        {term_type: "day_of_month", day_of_month: 15},
        {term_type: "day_of_month", day_of_month: 31, month_offset: 0},
        {term_type: "day_of_month", day_of_month: 1, month_offset: 12}
      ].each do |term|
        context "with #{term.inspect}" do
          let(:payment_term) { term }

          it "returns true" do
            expect(validate_service).to be_valid
            expect(result).to be_success
          end
        end
      end
    end

    context "when payment_term is not a hash" do
      let(:payment_term) { "net 30" }

      it "fails with invalid_format" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:payment_term]).to eq(["invalid_format"])
      end
    end

    context "when term_type is missing" do
      let(:payment_term) { {} }

      it "fails with invalid_term_type" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:payment_term]).to eq(["invalid_term_type"])
      end
    end

    context "when term_type is unknown" do
      let(:payment_term) { {term_type: "net_15_eom"} }

      it "fails with invalid_term_type" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:payment_term]).to eq(["invalid_term_type"])
      end
    end

    context "when days is missing for a type requiring it" do
      %w[net net_end_of_month days_end_of_month].each do |term_type|
        context "with #{term_type}" do
          let(:payment_term) { {term_type:} }

          it "fails with invalid_days" do
            expect(validate_service).not_to be_valid
            expect(result.error.messages[:payment_term]).to eq(["invalid_days"])
          end
        end
      end
    end

    context "when days is negative" do
      let(:payment_term) { {term_type: "net", days: -1} }

      it "fails with invalid_days" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:payment_term]).to eq(["invalid_days"])
      end
    end

    context "when days exceeds the max bound" do
      let(:payment_term) { {term_type: "net", days: 366} }

      it "fails with invalid_days" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:payment_term]).to eq(["invalid_days"])
      end
    end

    context "when days is not an integer" do
      let(:payment_term) { {term_type: "net", days: "30"} }

      it "fails with invalid_days" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:payment_term]).to eq(["invalid_days"])
      end
    end

    context "when day_of_month is missing" do
      let(:payment_term) { {term_type: "day_of_month"} }

      it "fails with invalid_day_of_month" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:payment_term]).to eq(["invalid_day_of_month"])
      end
    end

    context "when day_of_month is out of the 1..31 range" do
      [0, 32].each do |day|
        context "with #{day}" do
          let(:payment_term) { {term_type: "day_of_month", day_of_month: day} }

          it "fails with invalid_day_of_month" do
            expect(validate_service).not_to be_valid
            expect(result.error.messages[:payment_term]).to eq(["invalid_day_of_month"])
          end
        end
      end
    end

    context "when month_offset is out of the 0..12 range" do
      [-1, 13].each do |offset|
        context "with #{offset}" do
          let(:payment_term) { {term_type: "day_of_month", day_of_month: 15, month_offset: offset} }

          it "fails with invalid_month_offset" do
            expect(validate_service).not_to be_valid
            expect(result.error.messages[:payment_term]).to eq(["invalid_month_offset"])
          end
        end
      end
    end

    context "when month_offset is not an integer" do
      let(:payment_term) { {term_type: "day_of_month", day_of_month: 15, month_offset: "1"} }

      it "fails with invalid_month_offset" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:payment_term]).to eq(["invalid_month_offset"])
      end
    end

    context "when a field not belonging to the term type is sent" do
      [
        {term_type: "due_on_receipt", days: 0},
        {term_type: "net", days: 30, day_of_month: 5},
        {term_type: "end_of_month", month_offset: 1},
        {term_type: "day_of_month", day_of_month: 15, days: 30}
      ].each do |term|
        context "with #{term.inspect}" do
          let(:payment_term) { term }

          it "fails with unexpected_fields" do
            expect(validate_service).not_to be_valid
            expect(result.error.messages[:payment_term]).to include("unexpected_fields")
          end
        end
      end
    end

    context "with string keys" do
      let(:payment_term) { {"term_type" => "net", "days" => 30} }

      it "returns true" do
        expect(validate_service).to be_valid
      end
    end
  end
end
