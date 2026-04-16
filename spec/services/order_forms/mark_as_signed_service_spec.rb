# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrderForms::MarkAsSignedService do
  subject(:service) { described_class.new(order_form:, user:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:user) { create(:user) }
  let(:quote) { create(:quote, customer:, organization:, currency: "EUR", order_type: :subscription_creation) }
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
          expect(result.order_form.signed_by_user_id).to eq(user.id)
        end

        it "creates an order with copied snapshot" do
          result = service.call

          expect(result.order).to be_persisted
          expect(result.order).to be_created
          expect(result.order.organization).to eq(organization)
          expect(result.order.customer).to eq(customer)
          expect(result.order.order_form).to eq(order_form)
          expect(result.order.billing_snapshot).to eq(order_form.billing_snapshot)
          expect(result.order.order_type).to eq(quote.order_type)
          expect(result.order.currency).to eq(quote.currency)
        end

        it "enqueues webhooks" do
          expect { service.call }
            .to have_enqueued_job(SendWebhookJob).with("order_form.signed", order_form)
            .and have_enqueued_job(SendWebhookJob).with("order.created", an_instance_of(Order))
        end

        context "when quote has execution_mode and backdated_billing" do
          let(:quote) do
            create(:quote,
              customer:,
              organization:,
              currency: "EUR",
              order_type: :subscription_creation,
              execution_mode: :execute_in_lago,
              backdated_billing: :generate_past_invoices)
          end

          it "copies execution_mode and backdated_billing to the order" do
            result = service.call

            expect(result.order.execution_mode).to eq("execute_in_lago")
            expect(result.order.backdated_billing).to eq("generate_past_invoices")
          end
        end

        context "when quote has nil execution_mode" do
          let(:quote) do
            create(:quote,
              customer:,
              organization:,
              currency: "EUR",
              order_type: :subscription_creation,
              execution_mode: nil)
          end

          it "creates order with nil execution_mode" do
            result = service.call

            expect(result.order.execution_mode).to be_nil
          end
        end
      end
    end
  end
end
