# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrderForms::ExpireService do
  subject(:service) { described_class.new(order_form:) }

  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, organization:, customer:) }
  let(:quote_version) { create(:quote_version, :approved, organization:, quote:) }
  let(:order_form) { create(:order_form, :expired_yesterday, customer:, organization:, quote_version:) }

  describe "#call" do
    context "without premium license" do
      it "returns a forbidden failure" do
        result = service.call

        expect(result).not_to be_success
        expect(result.error).to be_a(BaseService::ForbiddenFailure)
        expect(result.error.code).to eq("feature_unavailable")
      end
    end

    context "when the order_forms feature flag is disabled", :premium do
      let(:organization) { create(:organization) }

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

      context "with concurrent mutations" do
        it "wraps the work in a per-quote lock" do
          allow(Quotes::LockService).to receive(:call).and_call_original

          service.call

          expect(Quotes::LockService).to have_received(:call).with(quote: order_form.quote_version.quote).at_least(:once)
        end

        it "re-checks the status under the lock and skips an order form voided concurrently" do
          order_form
          OrderForm.find(order_form.id).update!(status: :voided, void_reason: :manual, voided_at: Time.current)

          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ForbiddenFailure)
          expect(result.error.code).to eq("order_form_is_voided")
        end
      end

      context "when order_form is already expired" do
        let(:order_form) { create(:order_form, :expired, customer:, organization:) }

        it "returns success without changes" do
          result = service.call

          expect(result).to be_success
          expect(result.order_form).to be_expired
        end

        it "does not enqueue a webhook" do
          expect do
            ApplicationRecord.transaction { service.call }
          end.not_to have_enqueued_job(SendWebhookJob)
        end

        it "does not produce an activity log" do
          service.call

          expect(Utils::ActivityLog).not_to have_produced("order_form.expired")
        end
      end

      context "when order_form is already voided" do
        let(:order_form) { create(:order_form, :voided, customer:, organization:) }

        it "returns a forbidden failure" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ForbiddenFailure)
          expect(result.error.code).to eq("order_form_is_voided")
        end
      end

      context "when order_form is already signed" do
        let(:order_form) { create(:order_form, :signed, customer:, organization:) }

        it "returns a forbidden failure" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ForbiddenFailure)
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

        it "cascades the expiration by voiding the quote version" do
          service.call

          expect(quote_version.reload).to be_voided
          expect(quote_version.void_reason).to eq("cascade_of_expired")
        end

        it "enqueues an order_form.expired webhook" do
          expect { service.call }
            .to have_enqueued_job_after_commit(SendWebhookJob)
            .with("order_form.expired", order_form)
        end

        it "enqueues a cascaded quote.voided webhook" do
          expect { service.call }
            .to have_enqueued_job_after_commit(SendWebhookJob)
            .with("quote.voided", quote_version)
        end

        it "produces an order_form.expired activity log" do
          service.call

          expect(Utils::ActivityLog).to have_produced("order_form.expired").after_commit.with(order_form)
        end

        it "produces a cascaded quote.voided activity log" do
          service.call

          expect(Utils::ActivityLog).to have_produced("quote.voided").after_commit.with(quote_version)
        end
      end
    end
  end
end
