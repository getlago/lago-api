# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrderForms::MarkAsSignedService do
  subject(:service) { described_class.new(order_form:, signed_document:, execution_mode:, execution_date:) }

  let(:organization) { create(:organization) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, customer:, organization:, order_type: :subscription_creation) }
  let(:order_form) { create(:order_form, customer:, organization:, quote:) }
  let(:signed_document) { nil }
  let(:execution_mode) { nil }
  let(:execution_date) { nil }

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

      context "when a signed_document is provided" do
        let(:signed_document) do
          "data:application/pdf;base64,#{Base64.encode64(File.read(Rails.root.join("spec/fixtures/blank.pdf")))}"
        end

        it "signs the order form and attaches the document" do
          result = service.call

          expect(result).to be_success
          expect(result.order_form).to be_signed
          expect(result.order_form.signed_document).to be_attached
          expect(result.order_form.signed_document.blob.content_type).to eq("application/pdf")
        end
      end

      context "when the signed_document type is unsupported" do
        let(:signed_document) { "data:text/plain;base64,#{Base64.encode64("not a pdf")}" }

        it "returns a validation failure and does not sign the order form" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages).to have_key(:signed_document)
          expect(order_form.reload).to be_generated
        end
      end

      context "when execution_mode and execution_date are provided" do
        let(:execution_mode) { "execute_in_lago" }
        let(:execution_date) { "2026-06-15" }

        it "signs the order form without acting on them" do
          result = service.call

          expect(result).to be_success
          expect(result.order_form).to be_signed
        end
      end

      context "when execution_mode is invalid" do
        let(:execution_mode) { "unknown" }

        it "returns a validation failure on execution_mode" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages).to have_key(:execution_mode)
        end
      end

      context "when execution_date is not a date" do
        let(:execution_date) { "not-a-date" }

        it "returns a validation failure on execution_date" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages).to have_key(:execution_date)
        end
      end
    end
  end
end
