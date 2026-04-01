# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrderForms::VoidService do
  subject(:service) { described_class.new(order_form:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, customer:, organization:) }
  let(:order_form) { create(:order_form, customer:, organization:, quote:) }

  describe "#call" do
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
        expect(result.error.code).to eq("not_voidable")
      end
    end

    context "when order_form is generated" do
      it "transitions the order form to voided" do
        result = service.call

        expect(result).to be_success
        expect(result.order_form).to be_voided
        expect(result.order_form.voided_at).to be_present
        expect(result.order_form.void_reason).to eq("manual")
      end

      it "enqueues a webhook" do
        expect { service.call }
          .to have_enqueued_job(SendWebhookJob).with("order_form.voided", order_form)
      end

      # TODO: Test Quote cascade when Quotes::VoidService is implemented
      pending "cascades void to parent quote"
    end
  end
end
