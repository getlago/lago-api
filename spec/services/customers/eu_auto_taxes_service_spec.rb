# frozen_string_literal: true

require "rails_helper"

RSpec.describe Customers::EuAutoTaxesService do
  subject(:eu_tax_service) { described_class.new(customer:, new_record:, tax_attributes_changed:) }

  let(:organization) { create(:organization, country: "IT", eu_tax_management: true) }
  let(:billing_entity) { create(:billing_entity, organization:, country: "FR", eu_tax_management: true) }
  let(:customer) { create(:customer, organization:, billing_entity:, tax_identification_number:, zipcode: nil) }
  let(:new_record) { true }
  let(:tax_attributes_changed) { true }
  let(:tax_identification_number) { "IT12345678901" }

  shared_examples "a VIES check error" do |exception_class:, error_message:, error_type:|
    let(:full_error_message) { "The  web service returned the error: #{error_message}" }

    before do
      allow_any_instance_of(Valvat).to receive(:exists?) # rubocop:disable RSpec/AnyInstance
        .and_raise(exception_class.new(error_message, nil))
      customer.update!(country: "DE")
    end

    it "returns an error" do
      result = eu_tax_service.call

      expect(result).not_to be_success
      expect(result.tax_code).to be_nil
      expect(result.error.code).to eq("vies_check_failed")
      expect(result.error.message).to eq("vies_check_failed: #{full_error_message}")

      expect(SendWebhookJob).to have_been_enqueued.with("customer.vies_check", customer, vies_check: {
        valid: false,
        valid_format: true,
        error: full_error_message
      }).once
    end

    it "enqueues RetryViesCheckJob" do
      eu_tax_service.call

      expect(Customers::RetryViesCheckJob).to have_been_enqueued.at(4.minutes.from_now..6.minutes.from_now).with(customer.id).once
    end

    it "creates a pending_vies_check record" do
      expect { eu_tax_service.call }.to change(PendingViesCheck, :count).by(1)

      pending_check = customer.pending_vies_check
      expect(pending_check).to have_attributes(
        organization: customer.organization,
        billing_entity: customer.billing_entity,
        tax_identification_number: customer.tax_identification_number,
        attempts_count: 1,
        last_error_type: error_type,
        last_error_message: full_error_message
      )
      expect(pending_check.last_attempt_at).to be_present
    end

    context "when pending_vies_check already exists" do
      let(:existing_check) { create(:pending_vies_check, customer:, attempts_count: 2, last_error_type: "unknown") }

      before { existing_check }

      it "updates the existing record and increments attempts_count" do
        expect { eu_tax_service.call }.not_to change(PendingViesCheck, :count)

        existing_check.reload
        expect(existing_check.attempts_count).to eq(3)
        expect(existing_check.last_error_type).to eq(error_type)
      end

      it "uses exponential backoff for retry delay" do
        eu_tax_service.call

        expect(Customers::RetryViesCheckJob).to have_been_enqueued.at(9.minutes.from_now..11.minutes.from_now).with(customer.id)
      end
    end

    context "when pending_vies_check has many attempts" do
      let(:existing_check) { create(:pending_vies_check, customer:, attempts_count: 5, last_error_type: "unknown") }

      before { existing_check }

      it "caps retry delay at 1 hour" do
        eu_tax_service.call

        expect(Customers::RetryViesCheckJob).to have_been_enqueued.at(59.minutes.from_now..61.minutes.from_now).with(customer.id)
      end
    end
  end

  describe ".call" do
    before do
      allow_any_instance_of(Valvat).to receive(:exists?).and_return(vies_response) # rubocop:disable RSpec/AnyInstance
    end

    context "with B2B organization" do
      let(:vies_response) { {} }

      context "when tax_identification_number is blank" do
        let(:tax_identification_number) { nil }

        before { customer.update!(country: "DE") }

        it "returns the billing entity country tax code" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_fr_standard")
          expect(SendWebhookJob).not_to have_been_enqueued
        end
      end

      context "when vat number is invalid" do
        let(:tax_identification_number) { "invalid_vat_number" }

        before do
          # No call to the API is made when the format is invalid
          allow_any_instance_of(Valvat).to receive(:exists?).and_call_original # rubocop:disable RSpec/AnyInstance
          customer.update!(country: "DE")
        end

        it "returns the billing entity country tax code" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_fr_standard")
          expect(SendWebhookJob).to have_been_enqueued.with("customer.vies_check", customer, vies_check: {
            valid: false,
            valid_format: false
          }).once
        end
      end

      context "when VIES check raises RateLimitError" do
        it_behaves_like "a VIES check error",
          exception_class: Valvat::RateLimitError,
          error_message: "rate limit reached",
          error_type: "rate_limit"
      end

      context "when VIES check raises MemberStateUnavailable error" do
        it_behaves_like "a VIES check error",
          exception_class: Valvat::MemberStateUnavailable,
          error_message: "member state unavailable",
          error_type: "member_state_unavailable"
      end

      context "when VIES check raises ServiceUnavailable error" do
        it_behaves_like "a VIES check error",
          exception_class: Valvat::ServiceUnavailable,
          error_message: "service unavailable",
          error_type: "service_unavailable"
      end

      context "when VIES check raises HTTPError with 307" do
        it_behaves_like "a VIES check error",
          exception_class: Valvat::HTTPError,
          error_message: "The VIES web service returned the error: 307 ",
          error_type: "service_unavailable"
      end

      context "when VIES check raises HTTPError without 307" do
        before do
          allow_any_instance_of(Valvat).to receive(:exists?) # rubocop:disable RSpec/AnyInstance
            .and_raise(Valvat::HTTPError.new("The VIES web service returned the error: 301 ", nil))
          customer.update!(country: "DE")
        end

        it "re-raises the error" do
          expect { eu_tax_service.call }.to raise_error(Valvat::HTTPError, /301/)
        end
      end

      context "when VIES check raises Timeout error" do
        it_behaves_like "a VIES check error",
          exception_class: Valvat::Timeout,
          error_message: "connection timed out",
          error_type: "timeout"
      end

      context "when VIES check raises BlockedError" do
        it_behaves_like "a VIES check error",
          exception_class: Valvat::BlockedError,
          error_message: "request blocked",
          error_type: "blocked"
      end

      context "when VIES check raises InvalidRequester error" do
        it_behaves_like "a VIES check error",
          exception_class: Valvat::InvalidRequester,
          error_message: "invalid requester",
          error_type: "invalid_requester"
      end

      context "when eu_tax_management is false" do
        let(:organization) { create(:organization, country: "IT", eu_tax_management: false) }
        let(:billing_entity) { create(:billing_entity, organization:, country: "FR", eu_tax_management: false) }

        it "returns error" do
          result = eu_tax_service.call

          expect(result).not_to be_success
          expect(result.error.code).to eq("eu_tax_not_applicable")
        end
      end

      context "when customer is updated and there are eu taxes" do
        let(:new_record) { false }
        let(:tax_attributes_changed) { false }
        let(:applied_tax) { create(:customer_applied_tax, tax:, customer:) }
        let(:tax) { create(:tax, organization:, code: "lago_eu_tax_exempt") }

        before { applied_tax }

        it "returns error" do
          result = eu_tax_service.call

          expect(result).not_to be_success
          expect(result.error.code).to eq("eu_tax_not_applicable")
        end
      end

      context "when customer is updated and there are no eu taxes" do
        let(:new_record) { false }
        let(:tax_attributes_changed) { false }
        let(:applied_tax) { create(:customer_applied_tax, tax:, customer:) }
        let(:tax) { create(:tax, organization:, code: "unknown_eu_tax_exempt") }
        let(:vies_response) do
          {
            country_code: "FR"
          }
        end

        before { applied_tax }

        it "returns the billing_entity country tax code" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_fr_standard")
        end
      end

      context "with same country as the billing_entity" do
        let(:vies_response) do
          {
            country_code: "FR"
          }
        end

        it "returns the organization country tax code" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_fr_standard")
        end

        it "enqueues a SendWebhookJob" do
          eu_tax_service.call

          expect(SendWebhookJob).to have_been_enqueued
            .with("customer.vies_check", customer, vies_check: vies_response)
            .once
        end

        context "when a pending_vies_check exists from a previous failure" do
          let(:pending_check) { create(:pending_vies_check, customer:) }

          before { pending_check }

          it "deletes the pending_vies_check record" do
            expect { eu_tax_service.call }.to change(PendingViesCheck, :count).by(-1)
            expect(customer.reload.pending_vies_check).to be_nil
          end
        end
      end

      context "with a different country from the billing_entity one" do
        let(:vies_response) do
          {
            country_code: "DE"
          }
        end

        it "returns the reverse charge tax" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_reverse_charge")
        end
      end

      context "when country has exceptions" do
        let(:vies_response) do
          {
            country_code: "FR"
          }
        end

        context "when customer has no zipcode" do
          it "returns the customer country standard tax" do
            result = eu_tax_service.call
            expect(result.tax_code).to eq("lago_eu_fr_standard")
          end
        end

        context "when customer has a zipcode" do
          context "when zipcode has applicable exceptions" do
            before do
              customer.update(zipcode: "97412")
            end

            it "returns the exception tax code" do
              result = eu_tax_service.call
              expect(result.tax_code).to eq("lago_eu_fr_exception_reunion")
            end
          end

          context "when zipcode has no applicable exceptions" do
            before do
              customer.update(zipcode: "12345")
            end

            it "returns the customer counrty standard tax" do
              result = eu_tax_service.call
              expect(result.tax_code).to eq("lago_eu_fr_standard")
            end
          end
        end
      end
    end

    context "with non B2B" do
      let(:vies_response) { false }

      context "when the customer has no country" do
        before do
          customer.update(country: nil)
        end

        it "returns the billing entity country tax code" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_fr_standard")
        end
      end

      context "when the customer country is in europe" do
        before do
          customer.update(country: "DE")
        end

        it "returns the billing entity country tax code" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_fr_standard")
        end
      end

      context "when the customer country is out of europe" do
        before do
          customer.update(country: "US")
        end

        it "returns the tax exempt tax code" do
          result = eu_tax_service.call

          expect(result.tax_code).to eq("lago_eu_tax_exempt")
        end
      end
    end
  end
end
