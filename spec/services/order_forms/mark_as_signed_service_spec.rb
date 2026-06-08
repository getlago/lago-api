# frozen_string_literal: true

require "rails_helper"

RSpec.describe OrderForms::MarkAsSignedService do
  subject(:service) { described_class.new(order_form:, signed_document:, execution_mode:, execute_at:) }

  let(:organization) { create(:organization, feature_flags: ["order_forms"]) }
  let(:customer) { create(:customer, organization:) }
  let(:quote) { create(:quote, customer:, organization:, order_type: :subscription_creation) }
  let(:order_form) { create(:order_form, customer:, organization:, quote:) }
  let(:signed_document) { nil }
  let(:execution_mode) { nil }
  let(:execute_at) { nil }

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

      context "when the order_forms feature flag is disabled" do
        let(:organization) { create(:organization) }

        it "returns a forbidden failure" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ForbiddenFailure)
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

      context "when the signed_document is malformed" do
        let(:signed_document) { "not-a-data-uri" }

        it "returns a validation failure without signing" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:signed_document]).to eq(["invalid_format"])
          expect(order_form.reload).to be_generated
        end
      end

      context "when the signed_document exceeds the max size" do
        let(:signed_document) { "data:application/pdf;base64,#{Base64.strict_encode64("pdf")}" }

        before do
          decoded = Utils::Base64File::Decoded.new(io: instance_double(StringIO, size: 11.megabytes), content_type: "application/pdf")
          allow(Utils::Base64File).to receive(:decode).and_return(decoded)
        end

        it "returns a validation failure without uploading" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages).to have_key(:signed_document)
          expect(order_form.reload).to be_generated
        end
      end

      context "when saving fails after the document is uploaded" do
        let(:signed_document) { "data:application/pdf;base64,#{Base64.strict_encode64("pdf")}" }
        let(:uploaded_blob) do
          ActiveStorage::Blob.create_and_upload!(io: StringIO.new("pdf"), filename: "doc", content_type: "application/pdf")
        end

        before do
          allow(ActiveStorage::Blob).to receive(:create_and_upload!).and_return(uploaded_blob)
          allow(uploaded_blob).to receive(:purge_later)
          allow(order_form).to receive(:save!).and_raise(ActiveRecord::RecordInvalid.new(order_form))
        end

        it "purges the orphaned blob and returns a validation failure" do
          result = service.call

          expect(result).not_to be_success
          expect(uploaded_blob).to have_received(:purge_later)
        end
      end

      context "when execution_mode and execute_at are provided" do
        let(:execution_mode) { "execute_in_lago" }
        let(:execute_at) { 1.month.from_now.iso8601 }

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

      context "when execute_at is set without execution_mode" do
        let(:execute_at) { 1.month.from_now.iso8601 }

        it "returns a validation failure on execution_mode" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:execution_mode]).to eq(["value_is_mandatory"])
        end
      end

      context "when execute_at is not a date" do
        let(:execution_mode) { "execute_in_lago" }
        let(:execute_at) { "not-a-date" }

        it "returns a validation failure on execute_at" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages).to have_key(:execute_at)
        end
      end

      context "when execute_at is in the past" do
        let(:execution_mode) { "execute_in_lago" }
        let(:execute_at) { 1.day.ago.iso8601 }

        it "returns a validation failure on execute_at" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:execute_at]).to eq(["invalid_date"])
        end
      end

      context "when execute_at is the current date" do
        let(:execution_mode) { "execute_in_lago" }
        let(:execute_at) { Date.current.iso8601 }

        it "returns a validation failure on execute_at" do
          result = service.call

          expect(result).not_to be_success
          expect(result.error).to be_a(BaseService::ValidationFailure)
          expect(result.error.messages[:execute_at]).to eq(["invalid_date"])
        end
      end
    end
  end
end
