# frozen_string_literal: true

require "rails_helper"

RSpec.describe Charges::Validators::GraduatedPercentageService, type: :service do
  subject(:graduated_percentage_service) { described_class.new(charge:) }

  let(:charge) do
    build(
      :graduated_percentage_charge,
      properties: {graduated_percentage_ranges: ranges}
    )
  end

  let(:ranges) { {} }

  describe ".valid?" do
    context "when billable metric is latest_agg" do
      let(:billable_metric) { create(:latest_billable_metric) }
      let(:charge) { build(:graduated_percentage_charge, properties: graduated_percentage_ranges, billable_metric:) }
      let(:graduated_percentage_ranges) do
        {
          graduated_percentage_ranges: ranges
        }
      end

      it "is invalid" do
        aggregate_failures do
          expect(graduated_percentage_service).not_to be_valid
          expect(graduated_percentage_service.result.error).to be_a(BaseService::ValidationFailure)
          expect(graduated_percentage_service.result.error.messages.keys).to include(:billable_metric)
          expect(graduated_percentage_service.result.error.messages[:billable_metric]).to include("invalid_value")
        end
      end
    end

    context "with ranges validation" do
      it "ensures the presences of ranges" do
        aggregate_failures do
          expect(graduated_percentage_service).not_to be_valid
          expect(graduated_percentage_service.result.error).to be_a(BaseService::ValidationFailure)
          expect(graduated_percentage_service.result.error.messages.keys).to include(:graduated_percentage_ranges)
          expect(graduated_percentage_service.result.error.messages[:graduated_percentage_ranges])
            .to include("missing_graduated_percentage_ranges")
        end
      end

      context "when ranges does not starts at 0" do
        let(:ranges) { [{from_value: -1, to_value: 100}] }

        it "is invalid" do
          aggregate_failures do
            expect(graduated_percentage_service).not_to be_valid
            expect(graduated_percentage_service.result.error).to be_a(BaseService::ValidationFailure)
            expect(graduated_percentage_service.result.error.messages.keys).to include(:graduated_percentage_ranges)
            expect(graduated_percentage_service.result.error.messages[:graduated_percentage_ranges])
              .to include("invalid_graduated_percentage_ranges")
          end
        end
      end

      context "when ranges does not ends at infinity" do
        let(:ranges) { [{from_value: 0, to_value: 100}] }

        it "is invalid" do
          aggregate_failures do
            expect(graduated_percentage_service).not_to be_valid
            expect(graduated_percentage_service.result.error).to be_a(BaseService::ValidationFailure)
            expect(graduated_percentage_service.result.error.messages.keys).to include(:graduated_percentage_ranges)
            expect(graduated_percentage_service.result.error.messages[:graduated_percentage_ranges])
              .to include("invalid_graduated_percentage_ranges")
          end
        end
      end

      context "when ranges have holes" do
        let(:ranges) do
          [
            {from_value: 0, to_value: 100},
            {from_value: 120, to_value: 1000}
          ]
        end

        it "is invalid" do
          aggregate_failures do
            expect(graduated_percentage_service).not_to be_valid
            expect(graduated_percentage_service.result.error).to be_a(BaseService::ValidationFailure)
            expect(graduated_percentage_service.result.error.messages.keys).to include(:graduated_percentage_ranges)
            expect(graduated_percentage_service.result.error.messages[:graduated_percentage_ranges])
              .to include("invalid_graduated_percentage_ranges")
          end
        end
      end

      context "when ranges are overlapping" do
        let(:ranges) do
          [
            {from_value: 0, to_value: 100},
            {from_value: 90, to_value: 1000}
          ]
        end

        it "is invalid" do
          aggregate_failures do
            expect(graduated_percentage_service).not_to be_valid
            expect(graduated_percentage_service.result.error).to be_a(BaseService::ValidationFailure)
            expect(graduated_percentage_service.result.error.messages.keys).to include(:graduated_percentage_ranges)
            expect(graduated_percentage_service.result.error.messages[:graduated_percentage_ranges])
              .to include("invalid_graduated_percentage_ranges")
          end
        end
      end
    end

    context "with rate validation" do
      let(:ranges) { [{from_value: 0, to_value: nil, rate:, flat_amount: "0"}] }

      context "with no range rate" do
        let(:rate) { nil }

        it "is invalid" do
          aggregate_failures do
            expect(graduated_percentage_service).not_to be_valid
            expect(graduated_percentage_service.result.error).to be_a(BaseService::ValidationFailure)
            expect(graduated_percentage_service.result.error.messages.keys).to include(:rate)
            expect(graduated_percentage_service.result.error.messages[:rate]).to include("invalid_rate")
          end
        end
      end

      context "with invalid range rate" do
        let(:rate) { "foo" }

        it "is invalid" do
          aggregate_failures do
            expect(graduated_percentage_service).not_to be_valid
            expect(graduated_percentage_service.result.error).to be_a(BaseService::ValidationFailure)
            expect(graduated_percentage_service.result.error.messages.keys).to include(:rate)
            expect(graduated_percentage_service.result.error.messages[:rate]).to include("invalid_rate")
          end
        end
      end

      context "with negative range rate" do
        let(:rate) { "-2" }

        it "is invalid" do
          aggregate_failures do
            expect(graduated_percentage_service).not_to be_valid
            expect(graduated_percentage_service.result.error).to be_a(BaseService::ValidationFailure)
            expect(graduated_percentage_service.result.error.messages.keys).to include(:rate)
            expect(graduated_percentage_service.result.error.messages[:rate]).to include("invalid_rate")
          end
        end
      end
    end

    context "with flat amount validation" do
      let(:ranges) { [{from_value: 0, to_value: nil, rate: 2, flat_amount:}] }

      context "with no range flat amount" do
        let(:flat_amount) { nil }

        it "is invalid" do
          aggregate_failures do
            expect(graduated_percentage_service).not_to be_valid
            expect(graduated_percentage_service.result.error).to be_a(BaseService::ValidationFailure)
            expect(graduated_percentage_service.result.error.messages.keys).to include(:flat_amount)
            expect(graduated_percentage_service.result.error.messages[:flat_amount]).to include("invalid_amount")
          end
        end
      end

      context "with invalid range flat amount" do
        let(:flat_amount) { "foo" }

        it "is invalid" do
          aggregate_failures do
            expect(graduated_percentage_service).not_to be_valid
            expect(graduated_percentage_service.result.error).to be_a(BaseService::ValidationFailure)
            expect(graduated_percentage_service.result.error.messages.keys).to include(:flat_amount)
            expect(graduated_percentage_service.result.error.messages[:flat_amount]).to include("invalid_amount")
          end
        end
      end

      context "with negative range flat amount" do
        let(:flat_amount) { "-4" }

        it "is invalid" do
          aggregate_failures do
            expect(graduated_percentage_service).not_to be_valid
            expect(graduated_percentage_service.result.error).to be_a(BaseService::ValidationFailure)
            expect(graduated_percentage_service.result.error.messages.keys).to include(:flat_amount)
            expect(graduated_percentage_service.result.error.messages[:flat_amount]).to include("invalid_amount")
          end
        end
      end
    end

    context "with applicable ranges" do
      let(:ranges) do
        [
          {
            from_value: 0,
            to_value: 10,
            rate: "3",
            flat_amount: "0"
          },
          {
            from_value: 11,
            to_value: 20,
            rate: "2",
            flat_amount: "20"
          },
          {
            from_value: 21,
            to_value: nil,
            rate: "1",
            flat_amount: "30"
          }
        ]
      end

      it { expect(graduated_percentage_service).to be_valid }
    end
  end
end
