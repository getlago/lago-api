# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrderForms::MarkAsSignedService do
  subject(:service) { described_class.new(order_form:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, customer:, organization:, order_type: :subscription_creation) }
  let(:order_form) { create(:order_form, customer:, organization:, quote:) }

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
      context "when order_form is nil" do
        let(:order_form) { nil }

        it "returns a not found failure" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.resource).to eq("order_form")
        end
      end

      context "when order_form is not generated" do
        let(:order_form) { create(:order_form, :signed, customer:, organization:, quote:) }

        it "returns a not allowed failure" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
          expect(result.error.code).to eq("not_signable")
        end
      end

      context "when order_form is voided" do
        let(:order_form) { create(:order_form, :voided, customer:, organization:, quote:) }

        it "returns a not allowed failure" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
          expect(result.error.code).to eq("not_signable")
        end
      end

      context "when order_form is expired" do
        let(:order_form) { create(:order_form, :expired, customer:, organization:, quote:) }

        it "returns a not allowed failure" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
          expect(result.error.code).to eq("not_signable")
        end
      end

      context "when order_form is generated" do
        it "transitions the order form to signed" do
          result = service.call

          expect(result).to be_success
          expect(result.order_form).to be_signed
          expect(result.order_form.signed_at).to be_present
        end
      end
    end
  end
end
