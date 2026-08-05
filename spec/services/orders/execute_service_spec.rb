# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orders::ExecuteService do
  subject(:execute_service) { described_class.new(order:) }

  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:, order_type:) }
  let(:quote_version) { create(:quote_version, :approved, quote:, organization:) }
  let(:order_form) { create(:order_form, :signed, organization:, customer:, quote_version:) }
  let(:order) { create(:order, organization:, customer:, order_form:, execution_mode: :order_only) }
  let(:order_type) { :one_off }

  describe "#call" do
    context "without premium license" do
      it "returns a forbidden failure" do
        result = execute_service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("feature_unavailable")
      end
    end

    context "with premium license", :premium do
      context "when the order does not exist" do
        let(:order) { nil }

        it "returns a not found failure" do
          result = execute_service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.resource).to eq("order")
        end
      end

      context "when the order_forms feature flag is disabled" do
        let(:organization) { create(:organization) }

        it "returns a forbidden failure" do
          result = execute_service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ForbiddenFailure)
        end
      end

      context "when the order is a one_off" do
        it "delegates to the one_off execute service" do
          allow(Orders::OneOff::ExecuteService).to receive(:call).and_call_original

          execute_service.call

          expect(Orders::OneOff::ExecuteService).to have_received(:call).with(order:)
        end
      end

      context "when the order type is not supported yet" do
        let(:order_type) { :subscription_creation }

        it "returns a validation failure" do
          result = execute_service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:order_type]).to include("unsupported_order_type")
        end
      end
    end
  end
end
