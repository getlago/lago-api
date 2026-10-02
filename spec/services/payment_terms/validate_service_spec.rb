# frozen_string_literal: true

require "rails_helper"

RSpec.describe PaymentTerms::ValidateService do
  subject(:validate_service) { described_class.new(result, payment_term:) }

  let(:result) { BaseResult.new }

  describe "net_payment_term validation" do
    subject(:validate_service) { described_class.new(result, net_payment_term:) }

    context "with an integer >= 0 or null" do
      [30, 0, nil].each do |value|
        context "with #{value.inspect}" do
          let(:net_payment_term) { value }

          it "returns true" do
            expect(validate_service).to be_valid
            expect(result).to be_success
          end
        end
      end
    end

    context "with a negative integer" do
      let(:net_payment_term) { -1 }

      it "fails with value_is_out_of_range" do
        expect(validate_service).not_to be_valid
        expect(result.error.messages[:net_payment_term]).to eq(["value_is_out_of_range"])
      end
    end

    context "with a non-integer value" do
      [30.5, 30.0, "30", "abc", "", true, {}, []].each do |value|
        context "with #{value.inspect}" do
          let(:net_payment_term) { value }

          it "fails with invalid_format" do
            expect(validate_service).not_to be_valid
            expect(result.error.messages[:net_payment_term]).to eq(["invalid_format"])
          end
        end
      end
    end

    context "when the key is absent" do
      subject(:validate_service) { described_class.new(result) }

      it "returns true" do
        expect(validate_service).to be_valid
      end
    end
  end

  describe "payment_term validation" do
    shared_examples "a term type carrying days" do |term_type|
      context "when days is valid" do
        [0, 30, 400].each do |days|
          context "with #{days}" do
            let(:payment_term) { {term_type:, days:} }

            it "returns true" do
              expect(validate_service).to be_valid
              expect(result).to be_success
            end
          end
        end
      end

      context "when days is missing" do
        let(:payment_term) { {term_type:} }

        it "fails with invalid_days" do
          expect(validate_service).not_to be_valid
          expect(result.error.messages[:payment_term]).to eq(["invalid_days"])
        end
      end

      context "when days is negative" do
        let(:payment_term) { {term_type:, days: -1} }

        it "fails with invalid_days" do
          expect(validate_service).not_to be_valid
          expect(result.error.messages[:payment_term]).to eq(["invalid_days"])
        end
      end

      context "when days is not an integer" do
        let(:payment_term) { {term_type:, days: "30"} }

        it "fails with invalid_days" do
          expect(validate_service).not_to be_valid
          expect(result.error.messages[:payment_term]).to eq(["invalid_days"])
        end
      end
    end

    shared_examples "a term type carrying no fields" do |term_type, unexpected_field|
      context "when no other field is sent" do
        let(:payment_term) { {term_type:} }

        it "returns true" do
          expect(validate_service).to be_valid
          expect(result).to be_success
        end
      end

      context "when #{unexpected_field.keys.first} is sent" do
        let(:payment_term) { {term_type:}.merge(unexpected_field) }

        it "fails with unexpected_fields" do
          expect(validate_service).not_to be_valid
          expect(result.error.messages[:payment_term]).to include("unexpected_fields")
        end
      end
    end

    describe "#valid?" do
      context "when payment_term is not provided" do
        let(:payment_term) { nil }

        it "returns true" do
          expect(validate_service).to be_valid
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
        let(:payment_term) { {days: 20} }

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

      context "with due_on_receipt" do
        it_behaves_like "a term type carrying no fields", "due_on_receipt", {days: 0}
      end

      context "with net" do
        it_behaves_like "a term type carrying days", "net"

        context "when day_of_month is sent" do
          let(:payment_term) { {term_type: "net", days: 30, day_of_month: 5} }

          it "fails with unexpected_fields" do
            expect(validate_service).not_to be_valid
            expect(result.error.messages[:payment_term]).to include("unexpected_fields")
          end
        end
      end

      context "with end_of_month" do
        it_behaves_like "a term type carrying no fields", "end_of_month", {month_offset: 1}
      end

      context "with net_end_of_month" do
        it_behaves_like "a term type carrying days", "net_end_of_month"
      end

      context "with days_end_of_month" do
        it_behaves_like "a term type carrying days", "days_end_of_month"
      end

      context "with day_of_month" do
        context "when day_of_month is valid" do
          [
            {day_of_month: 15},
            {day_of_month: 31, month_offset: 0},
            {day_of_month: 1, month_offset: 12}
          ].each do |fields|
            context "with #{fields.inspect}" do
              let(:payment_term) { {term_type: "day_of_month"}.merge(fields) }

              it "returns true" do
                expect(validate_service).to be_valid
                expect(result).to be_success
              end
            end
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

        context "when days is sent" do
          let(:payment_term) { {term_type: "day_of_month", day_of_month: 15, days: 30} }

          it "fails with unexpected_fields" do
            expect(validate_service).not_to be_valid
            expect(result.error.messages[:payment_term]).to include("unexpected_fields")
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
end
