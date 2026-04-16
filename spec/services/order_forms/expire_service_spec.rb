# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrderForms::ExpireService do
  subject(:service) { described_class.new(order_form:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, customer:, organization:) }
  let(:order_form) { create(:order_form, :expired_yesterday, customer:, organization:, quote:) }

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

      context "when order_form is already expired" do
        let(:order_form) { create(:order_form, :expired, customer:, organization:, quote:) }

        it "returns success without changes" do
          result = service.call

          expect(result).to be_success
          expect(result.order_form).to be_expired
        end

        it "does not enqueue a webhook" do
          expect { service.call }
            .not_to have_enqueued_job(SendWebhookJob)
        end
      end

      context "when order_form is already voided" do
        let(:order_form) { create(:order_form, :voided, customer:, organization:, quote:) }

        it "returns a not allowed failure" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
          expect(result.error.code).to eq("order_form_is_voided")
        end
      end

      context "when order_form is already signed" do
        let(:order_form) { create(:order_form, :signed, customer:, organization:, quote:) }

        it "returns a not allowed failure" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::MethodNotAllowedFailure)
          expect(result.error.code).to eq("order_form_is_signed")
        end
      end

      context "when order_form is generated" do
        it "transitions the order form to expired" do
          result = service.call

          expect(result).to be_success
          expect(result.order_form).to be_expired
          expect(result.order_form.voided_at).to be_present
          expect(result.order_form.void_reason).to eq("expired")
        end

        it "enqueues a webhook" do
          expect { service.call }
            .to have_enqueued_job(SendWebhookJob).with("order_form.expired", order_form)
        end

        # TODO: Test Quote cascade when Quotes::VoidService is implemented
        pending "cascades expiration to parent quote"
      end
    end
  end
end
