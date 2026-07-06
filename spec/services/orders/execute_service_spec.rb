# frozen_string_literal: true

require "rails_helper"

RSpec.describe Orders::ExecuteService do
  subject(:service) { described_class.new(order:) }

  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:customer) { create(:customer, organization:) }
  let(:order) { create(:order, organization:, customer:, execution_mode: "order_only") }

  describe "#call" do
    context "without premium license" do
      it "returns a forbidden failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("feature_unavailable")
      end
    end

    context "with premium license", :premium do
      context "when order is nil" do
        let(:order) { nil }

        it "returns a not found failure" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.resource).to eq("order")
        end
      end

      context "when the order_forms feature flag is disabled" do
        let(:organization) { create(:organization) }

        it "returns a forbidden failure" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ForbiddenFailure)
        end
      end

      context "with concurrent mutations" do
        it "wraps the work in a per-quote lock" do
          allow(Quotes::LockService).to receive(:call).and_call_original

          service.call

          expect(Quotes::LockService).to have_received(:call).with(quote: order.quote).at_least(:once)
        end
      end

      context "when the order is already executed" do
        let(:order) { create(:order, :executed_in_lago, organization:, customer:) }

        it "returns a validation failure" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages).to eq({status: ["not_executable"]})
        end
      end

      context "when the order has no execution_mode" do
        let(:order) { create(:order, organization:, customer:) }

        it "returns a validation failure" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages).to eq({execution_mode: ["value_is_mandatory"]})
        end
      end

      context "when the order is executable" do
        it "transitions the order to executed" do
          result = service.call

          expect(result).to be_success
          expect(result.order).to be_executed
          expect(result.order.executed_at).to be_present
          expect(result.order.execution_mode).to eq("order_only")
        end
      end
    end
  end
end
