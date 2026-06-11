# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrderForms::VoidService do
  subject(:service) { described_class.new(order_form:) }

  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:) }
  let(:quote_version) { create(:quote_version, :approved, organization:, quote:) }
  let(:order_form) { create(:order_form, customer:, organization:, quote_version:) }

  describe "#call" do
    context "when license is not premium" do
      it "returns a forbidden failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("feature_unavailable")
      end
    end

    context "with a premium license", :premium do
      context "when the order form does not exist" do
        let(:order_form) { nil }

        it "returns a not found failure" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::NotFoundFailure)
          expect(result.error.resource).to eq("order_form")
        end
      end

      context "when the order form is not generated" do
        let(:order_form) { create(:order_form, :signed, customer:, organization:) }

        it "returns a not allowed failure" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
          expect(result.error.code).to eq("not_voidable")
        end
      end

      context "when the order form is generated" do
        it "transitions the order form to voided" do
          result = service.call

          expect(result).to be_success
          expect(result.order_form).to be_voided
          expect(result.order_form.voided_at).to be_present
          expect(result.order_form.void_reason).to eq("manual")
        end

        it "cascades the void to the parent quote version" do
          service.call

          expect(quote_version.reload).to be_voided
          expect(quote_version.void_reason).to eq("cascade_of_voided")
        end
      end
    end
  end
end
